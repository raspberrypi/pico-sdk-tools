#!/bin/bash

set -euo pipefail

BUILDDIR=$(pwd)
INSTALLDIR="dtc-install"

cd dtc
make clean
make -j$(nproc) NO_PYTHON=1

make NO_PYTHON=1 DESTDIR="$BUILDDIR/$INSTALLDIR" PREFIX="" install

cd "$BUILDDIR/$INSTALLDIR/${MSYSTEM,,}/bin"
"$BUILDDIR/../packages/windows/copy-deps.sh"
