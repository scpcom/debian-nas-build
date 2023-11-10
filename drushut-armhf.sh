#!/bin/bash

PREFIX=`pwd`/armhf
FOUND=0

for ROOT in /proc/*/root; do
    LINK=$(readlink $ROOT)
    if [ "x$LINK" != "x" ]; then
        if [ "x${LINK:0:${#PREFIX}}" = "x$PREFIX" ]; then
            # this process is in the chroot...
            PID=$(basename $(dirname "$ROOT"))
            kill -9 "$PID"
            FOUND=1
        fi
    fi
done

if [ "x$FOUND" = "x1" ]; then
    $0 $*
fi

COUNT=0

while grep -q "$PREFIX" /proc/mounts; do
    COUNT=$(($COUNT+1))
    if [ $COUNT -ge 20 ]; then
        echo "failed to umount $PREFIX"
        if [ -x /usr/bin/lsof ]; then
            /usr/bin/lsof "$PREFIX"
        fi
        exit 1
    fi
    grep "$PREFIX" /proc/mounts |         cut -d\  -f2 | LANG=C sort -r | xargs -r -n 1 umount || sleep 1
done
