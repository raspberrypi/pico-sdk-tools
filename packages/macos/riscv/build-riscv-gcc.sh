#!/bin/bash

set -euo pipefail

INSTALLDIR="riscv-install-$(uname -m)"
rm -rf $INSTALLDIR
mkdir -p $INSTALLDIR

BUILDDIR=$(pwd)

if [[ $(uname -m) == 'arm64' ]]; then
    GDB_TARGET_FLAGS_EXTRA="--with-gmp=/opt/homebrew --with-mpfr=/opt/homebrew"
    export GDB_TARGET_FLAGS_EXTRA
fi

cd riscv-gnu-toolchain
./configure --prefix=$BUILDDIR/$INSTALLDIR --enable-strip --with-arch=rv32ima_zicsr_zifencei_zba_zbb_zbs_zbkb_zca_zcb --with-abi=ilp32 --with-multilib-generator="rv32ima_zicsr_zifencei_zba_zbb_zbs_zbkb_zca_zcb-ilp32--;rv32imac_zicsr_zifencei_zba_zbb_zbs_zbkb-ilp32--"
# 4 threads, as 8 threads runs out of memory
gmake -j4
