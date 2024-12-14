#!/bin/bash

set -euo pipefail

BUILDDIR=$(pwd)
INSTALLDIR="openocd-install"

cd openocd
sed -i -e 's/uint /unsigned int /g' ./src/flash/nor/rp2040.c
./bootstrap
./configure --disable-werror
make clean
make -j$(nproc)
DESTDIR="$BUILDDIR/$INSTALLDIR" make install

cd "$BUILDDIR/$INSTALLDIR/${MSYSTEM,,}/bin"
"$BUILDDIR/../packages/windows/copy-deps.sh"
