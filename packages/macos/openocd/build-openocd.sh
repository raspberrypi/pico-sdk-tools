#!/bin/bash

set -euo pipefail

cd openocd

./bootstrap
# See https://github.com/raspberrypi/openocd/issues/30
# ./configure --disable-werror CAPSTONE_CFLAGS="$(pkg-config capstone --cflags | sed s/.capstone\$//)"
./configure --disable-werror
make clean
make
INSTALLDIR="$PWD/../openocd-install-$(uname -m)/usr/local/bin"
rm -rf "$PWD/../openocd-install-$(uname -m)"
DESTDIR="$PWD/../openocd-install-$(uname -m)" make install
