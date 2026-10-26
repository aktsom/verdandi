#!/bin/bash
cd /tmp/claude-0/pkg
unshare -m sh -c '
 mount -t proc proc rootfs/proc && mount --rbind /dev rootfs/dev && mount -t tmpfs tmpfs rootfs/tmp && mkdir -p rootfs/tmp/.X11-unix
 cp /etc/resolv.conf rootfs/etc/resolv.conf 2>/dev/null
 chroot rootfs /bin/bash -c "export http_proxy='"$http_proxy"' https_proxy='"$https_proxy"'; /root/inner.sh"' > clean-install.out 2>&1
echo finished >> clean-install.out
