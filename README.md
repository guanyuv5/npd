# npd

### 开发测试

#### node-problem-detector 开发环境准备
```bash
# echo $GOPATH
/root/code/gopath
# git clone https://github.com/kubernetes/kubernetes.git
# git clone https://github.com/kubernetes/node-problem-detector.git
# cd node-problem-detector/
切换到最新的版本 tag: 
# git checkout -b v0.8.4 v0.8.4
```

#### 编译 node-problem-detector
```bash
[root@VM_10_60_centos ~/code/gopath/src/k8s.io/node-problem-detector/deployment]# make
[root@VM_10_60_centos ~/code/gopath/src/k8s.io/node-problem-detector]# docker images
REPOSITORY                                                            TAG                            IMAGE ID            CREATED             SIZE
staging-k8s.gcr.io/node-problem-detector                              v0.8.4                         23e7b55562b0        2 minutes ago       155MB
```

#### 开发自定义插件-文件描述符资源检查
1. 自定义插件配置

```json
{
    "plugin": "custom",
    "pluginConfig": {
      "invoke_interval": "30s",
      "timeout": "5s",
      "max_output_length": 512,
      "concurrency": 2,
      "enable_message_change_based_condition_update": true
    },
    "source": "npd_fd-custom-plugin-monitor",
    "metricsReporting": true,
    "conditions": [
      {
        "type": "FDPressure",
        "reason": "FDUnderPressure",
        "message": "FD is Under Pressure"
      }
    ],
    "rules": [
      {
        "type": "temporary",
        "reason": "FDUpperPressure",
        "path": "/config/plugin/check_file_nr.sh",
        "timeout": "3s"
      },
      {
        "type": "permanent",
        "condition": "FDPressure",
        "reason": "FDUpperPressure",
        "path": "/config/plugin/check_file_nr.sh",
        "timeout": "3s"
      }
    ]
  }
```
字段说明：
```
conditions: 代表该插件的事件是需要上报到node conditions中的；
rules: 代表该插件需要执行的脚本，以及根据脚本执行的返回值，判断描述符资源的使用是否满足小于总资源的80%，并根据脚本执行结果，上报不同的 events 和 conditions ， rules.type为 "temporary" 表示发送 event， rules.type为 "permanent" 表示发送 condition ；
rules.reason: 代表事件的具体原因；
rules.path: 代表资源检测执行脚本的路径；
rules.timeout: 代表执行脚本的超时资源；
```

2. 文件描述符资源检测脚本

```sh
#!/bin/bash
OK=0
NONOK=1
UNKNOWD=2
percentage=0.8


if [[ ! -f /proc/sys/fs/file-nr ]] ; then
        echo "/proc/sys/fs/file-nr is not exist"
        exit $UNKNOWD;
fi
read curr alloc limit < /proc/sys/fs/file-nr
used=`echo "scale=5; (${curr} + ${alloc}) / ${limit} > ${percentage}" | bc`

if [[ $used -eq 1 ]] ; then
        echo "curr: ${curr}  alloc: ${alloc}  limit: ${limit}"
        exit $NONOK
else
        echo "fd is undder pressure"
        exit $OK
fi
```

#### 将插件植入到 node-problem-detector

复制配置文件和检测脚本到 node-problem-detector 源码树：
```
# git clone https://github.com/guanyuv5/npd.git
# cp npd/config/custom-plugin-fd-pressure.json $GOPATH/src/k8s.io/node-problem-detector/config/
# cp npd/plugin/check_file_nr.sh  $GOPATH/src/k8s.io/node-problem-detector/config/plugin/
```

重新编译 node-problem-detector：
```
# cd $GOPATH/src/k8s.io/node-problem-detector
# make
```
将容器镜像 node-problem-detector 上传到个人的镜像仓库： 
```
[root@VM_10_60_centos ~/code/gopath/src/k8s.io/node-problem-detector]# docker tag staging-k8s.gcr.io/node-problem-detector:v0.8.4  ccr.ccs.tencentyun.com/npd-test/node-problem-detector:v0.8.4
[root@VM_10_60_centos ~/code/gopath/src/k8s.io/node-problem-detector]# docker push ccr.ccs.tencentyun.com/npd-test/node-problem-detector:v0.8.4
```

#### 部署测试

1. 部署 node-problem-detector


```bash
[root@VM-7-14-centos ~]# kubectl  create -f deployment/node-problem-detector.yaml
[root@VM-7-14-centos ~]# kubectl  get pod -n kube-system |grep node-problem-detector
node-problem-detector-2mz5g           1/1     Running   0          7m48s
```

1. 查看node condition中是否包含 FDPressure Conditions：

```bash
[root@VM-7-14-centos ~]# kubectl  get node
NAME        STATUS   ROLES    AGE   VERSION
10.0.7.14   Ready    <none>   11m   v1.16.3

[root@VM-7-14-centos ~]# kubectl  describe node 10.0.7.14
Name:               10.0.7.14
Roles:              <none>
Labels:             beta.kubernetes.io/arch=amd64
                    beta.kubernetes.io/os=linux
                    kubernetes.io/arch=amd64
                    kubernetes.io/hostname=10.0.7.14
                    kubernetes.io/os=linux
CreationTimestamp:  Wed, 23 Sep 2020 19:19:21 +0800
Taints:             <none>
Unschedulable:      false
Conditions:
  Type                    Status  LastHeartbeatTime                 LastTransitionTime                Reason                       Message
  ----                    ------  -----------------                 ------------------                ------                       -------
  CorruptDockerOverlay2   False   Wed, 23 Sep 2020 19:30:27 +0800   Wed, 23 Sep 2020 19:30:26 +0800   NoCorruptDockerOverlay2      docker overlay2 is functioning properly
  FDPressure              False   Wed, 23 Sep 2020 19:30:27 +0800   Wed, 23 Sep 2020 19:30:26 +0800   FDUnderPressure              FD is Under Pressure
  ...
```
2. 功能验证

```bash
[root@VM-7-14-centos ~]# cat /proc/sys/fs/file-nr
1472    0       838860
[root@VM-7-14-centos ~]# echo 2000 > /proc/sys/fs/file-max
[root@VM-7-14-centos ~]# cat /proc/sys/fs/file-max 
2000
```
3. 写一个脚本，循环使用描述符，使其达到文件描述符资源的应用瓶颈:

```bash
[root@VM-7-14-centos ~]# cat test.sh 
COUNTER=0
while [ $COUNTER -lt 500 ] 
do
    echo "$COUNTER"
    ping 127.0.0.1 >/dev/null &
    let COUNTER+=1
done

[root@VM-7-14-centos ~]# sh test.sh
```

4. 查看节点状态, 看node conditions 中，FDPressure 的状态是否发生变化:

```bash
[root@VM-7-14-centos ~]# kubectl  describe node 10.0.7.14 
Name:               10.0.7.14
Roles:              <none>
Labels:             beta.kubernetes.io/arch=amd64
                    beta.kubernetes.io/instance-type=QCLOUD
                    beta.kubernetes.io/os=linux
                    cloud.tencent.com/node-instance-id=ins-09mqcjtt
                    failure-domain.beta.kubernetes.io/region=bj
                    failure-domain.beta.kubernetes.io/zone=800002
                    kubernetes.io/arch=amd64
                    kubernetes.io/hostname=10.0.7.14
                    kubernetes.io/os=linux
Annotations:        node.alpha.kubernetes.io/ttl: 0
                    volumes.kubernetes.io/controller-managed-attach-detach: true
CreationTimestamp:  Wed, 23 Sep 2020 19:19:21 +0800
Taints:             <none>
Unschedulable:      false
Conditions:
  Type                    Status  LastHeartbeatTime                 LastTransitionTime                Reason                       Message
  ----                    ------  -----------------                 ------------------                ------                       -------
  FDPressure              True    Wed, 23 Sep 2020 20:20:12 +0800   Wed, 23 Sep 2020 20:20:12 +0800   FDUpperPressure              curr: 2048  alloc: 0  limit: 2000
```
我们发现， FDPressure 的Status 已经发生了变化，并更新了 Reason 信息.

5. FDPressure 状态恢复 

将系统中的ping进展全部杀死:
```
[root@VM-7-14-centos ~]# killall ping
[root@VM-7-14-centos ~]# cat /proc/sys/fs/file-nr
1312    0       2000
```
查看节点状态, 看node conditions 中，FDPressure 的状态是恢复:
```bash
[root@VM-7-14-centos ~]# kubectl  describe node 10.0.7.14 
Name:               10.0.7.14
Roles:              <none>
Labels:             beta.kubernetes.io/arch=amd64
                    beta.kubernetes.io/instance-type=QCLOUD
                    beta.kubernetes.io/os=linux
                    cloud.tencent.com/node-instance-id=ins-09mqcjtt
                    failure-domain.beta.kubernetes.io/region=bj
                    failure-domain.beta.kubernetes.io/zone=800002
                    kubernetes.io/arch=amd64
                    kubernetes.io/hostname=10.0.7.14
                    kubernetes.io/os=linux
Annotations:        node.alpha.kubernetes.io/ttl: 0
                    volumes.kubernetes.io/controller-managed-attach-detach: true
CreationTimestamp:  Wed, 23 Sep 2020 19:19:21 +0800
Taints:             <none>
Unschedulable:      false
Conditions:
  Type                    Status  LastHeartbeatTime                 LastTransitionTime                Reason                       Message
  ----                    ------  -----------------                 ------------------                ------                       -------
  FDPressure              False   Wed, 23 Sep 2020 20:26:12 +0800   Wed, 23 Sep 2020 20:26:12 +0800   FDUnderPressure              FD is Under Pressure
```
FDPressure 的Status 已经恢复了。

#### 结论
FDPressure 的状态默认值为false，表示该节点没有资源使用压力；该 node conditions 会随着节点上文件描述符的占用率的改变而改变，通过这种方式可以检测节点的文件描述符资源使用情况，因为文件描述符资源是没有进行隔离的，是个节点级别的全局资源，一点文件描述符用尽，将影响节点上所有容器和业务，所以，对节点中文件描述符的应用监控，是非常有必要的。
