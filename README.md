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


