#!/bin/bash

set -euo pipefail

BUILDDIR=$(pwd)
INSTALLDIR="openocd-install"

cd openocd

./bootstrap
./configure --disable-werror --enable-internal-jimtcl
make clean
make
DESTDIR="$BUILDDIR/$INSTALLDIR" make install

cd "$BUILDDIR/$INSTALLDIR/${MSYSTEM,,}/bin"
"$BUILDDIR/../packages/windows/copy-deps.sh"
