#!/bin/bash
cd /tmp/claude-0/pkg/sc
cmake -S src -B build -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/tmp/claude-0/pkg/sc/install \
  -DAUDIOAPI=jack -DSC_QT=OFF -DSC_IDE=OFF -DSUPERNOVA=OFF -DSC_EL=OFF -DSC_VIM=OFF -DSC_ED=OFF \
  -DNO_X11=ON -DSC_ABLETON_LINK=OFF -DINSTALL_HELP=OFF -DENABLE_TESTSUITE=OFF -DSC_USE_QTWEBENGINE=OFF > cmake.log 2>&1
echo "cmake exit $?" >> cmake.log
[ "$(tail -1 cmake.log)" = "cmake exit 0" ] && { ninja -C build > ninja.log 2>&1; echo "ninja exit $?" >> ninja.log; ninja -C build install > install.log 2>&1; echo "install exit $?" >> install.log; }
echo finished > done.flag
