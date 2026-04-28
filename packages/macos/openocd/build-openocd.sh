#!/bin/bash

set -euo pipefail

BUILDDIR=$(pwd)
INSTALLDIR="openocd-install-$(uname -m)"
BINDIR="/openocd"
DATADIR="/"

cd openocd

./bootstrap
# See https://github.com/raspberrypi/openocd/issues/30
# ./configure --disable-werror CAPSTONE_CFLAGS="$(pkg-config capstone --cflags | sed s/.capstone\$//)"
./configure --disable-werror --enable-internal-jimtcl --bindir="$BINDIR" --datadir="$DATADIR"
make clean
make
rm -rf "$BUILDDIR/$INSTALLDIR"
DESTDIR="$BUILDDIR/$INSTALLDIR" make install

cd "$BUILDDIR/$INSTALLDIR/$BINDIR"
find . -maxdepth 1 ! -name . ! -name .. ! -name openocd ! -name scripts -exec rm -r {} +
