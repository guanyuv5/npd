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
if ((  curr > limit * 8 /10 )); then

        echo "curr: ${curr}  alloc: ${alloc}  limit: ${limit}"
        exit $NONOK
else
        echo "fd is undder pressure"
        exit $OK
fi
