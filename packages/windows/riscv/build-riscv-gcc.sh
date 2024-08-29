#!/bin/bash

set -euo pipefail

BITNESS=$1
ARCH=$2

INSTALLDIR="riscv-install"
rm -rf $INSTALLDIR
mkdir -p $INSTALLDIR

BUILDDIR=$(pwd)

cd riscv-gnu-toolchain
./configure --prefix=$BUILDDIR/$INSTALLDIR --with-arch=rv32ima_zicsr_zifencei_zba_zbb_zbs_zbkb_zca_zcb --with-abi=ilp32 --with-multilib-generator="rv32ima_zicsr_zifencei_zba_zbb_zbs_zbkb_zca_zcb-ilp32--;rv32imac_zicsr_zifencei_zba_zbb_zbs_zbkb-ilp32--" --with-gcc-src=$BUILDDIR/gcc
make -j$(nproc) gcc
make -j$(nproc) gdb
make -j$(nproc) newlib
make -j$(nproc)
