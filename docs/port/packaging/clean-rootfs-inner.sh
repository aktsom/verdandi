#!/bin/bash
# runs INSIDE the clean Ubuntu 24.04 rootfs
export DEBIAN_FRONTEND=noninteractive
cat > /etc/apt/sources.list <<S
deb http://archive.ubuntu.com/ubuntu noble main universe
deb http://archive.ubuntu.com/ubuntu noble-updates main universe
S
rm -f /etc/apt/sources.list.d/*
apt-get update -q > /root/apt-update.log 2>&1; echo "apt update exit $?"
echo "== apt-get install ./verdandi-exp.deb (a clean system, nothing else installed)"
apt-get install -y -q ./root/verdandi-exp.deb > /root/apt-install.log 2>&1; echo "install exit $?"
grep -E "newly installed|Setting up verdandi" /root/apt-install.log
dpkg -l | grep -c '^ii' | sed 's/^/packages installed: /'
echo "libjack chosen:"; dpkg -l | grep -E "libjack|pipewire-jack|jackd" | awk '{print $2}' | tr '\n' ' '; echo
echo "== which of the program's libraries are missing (ldd)"
LD_LIBRARY_PATH=/opt/verdandi/lib ldd /opt/verdandi/build/norns/norns | grep -c "not found"
LD_LIBRARY_PATH=/opt/verdandi/lib ldd /opt/verdandi/supercollider/bin/sclang | grep -c "not found"
echo "== test-only tools (a display and a JACK server for the headless run)"
apt-get install -y -q xvfb xauth jackd2 x11-apps imagemagick > /root/apt-test.log 2>&1; echo "test tools exit $?"
dpkg -l | grep -E "libjack|pipewire-jack|jackd2" | awk '{print $2}' | tr '\n' ' '; echo
mkdir -p /root/vhome && ln -sfn /opt/verdandi /root/vhome/norns
export LD_LIBRARY_PATH=/opt/verdandi/lib PATH=/opt/verdandi/supercollider/bin:$PATH
NORNS_HOME=/root/vhome /opt/verdandi/linux/tests/norns_probe.sh /root/ro.lua /root/probe.log > /root/probe.out 2>&1
echo "boot: startup_status.ok x$(grep -ac startup_status.ok /root/probe.log); engines: $(grep -a 'engines: \[' /root/vhome/sclang.log | cut -c1-90)"
grep -a "SUPERCOLLIDER\|PROBE" /root/probe.log | head -3
