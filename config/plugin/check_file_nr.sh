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

if (( (${curr} + ${alloc}) > ${limit} * 8 /10 )); then
        echo "curr: ${curr}  alloc: ${alloc}  limit: ${limit}"
        exit $NONOK
else
        echo "fd is undder pressure"
        exit $OK
fi
