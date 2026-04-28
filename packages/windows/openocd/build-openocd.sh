#!/bin/bash

set -euo pipefail

BUILDDIR=$(pwd)
INSTALLDIR="openocd-install"
BINDIR="/openocd"
DATADIR="/"

cd openocd

./bootstrap
./configure --disable-werror --enable-internal-jimtcl --bindir="$BINDIR" --datadir="$DATADIR"
make clean
make
DESTDIR="$BUILDDIR/$INSTALLDIR" make install

cd "$BUILDDIR/$INSTALLDIR/$BINDIR"
find . -maxdepth 1 ! -name . ! -name .. ! -name openocd.exe ! -name scripts -exec rm -r {} +
"$BUILDDIR/../packages/windows/copy-deps.sh"
