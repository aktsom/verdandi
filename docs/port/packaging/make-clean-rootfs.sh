#!/bin/bash
cd /tmp/claude-0/pkg
rm -rf rootfs
debootstrap --variant=minbase --include=ca-certificates noble rootfs http://archive.ubuntu.com/ubuntu > debootstrap.log 2>&1
echo "debootstrap exit $?" >> debootstrap.log
echo finished > mkroot.flag
