#!/bin/bash

set -euo pipefail

cd dtc

# build
make clean
make -j$(nproc) NO_PYTHON=1

INSTALLDIR="$PWD/../dtc-install"
make NO_PYTHON=1 DESTDIR="$INSTALLDIR" PREFIX="" install
