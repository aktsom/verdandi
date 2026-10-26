#!/bin/bash
cd /tmp/claude-0/pkg
unshare -m sh -c '
 mount --bind /tmp/claude-0/pkg/prog /tmp/claude-0/pkg/prog && mount -o remount,ro,bind /tmp/claude-0/pkg/prog
 PATH=/tmp/claude-0/pkg/sc/install/bin:$PATH NORNS_HOME=/tmp/claude-0/pkg/home2 /tmp/claude-0/pkg/prog/linux/tests/norns_probe.sh /tmp/claude-0/pkg/ro.lua /tmp/claude-0/pkg/ro2.log > /tmp/claude-0/pkg/ro2.out 2>&1'
echo finished >> /tmp/claude-0/pkg/ro2.out
