#!/bin/bash

set -euo pipefail

INSTALLDIR="riscv-install-$(uname -m)"
rm -rf $INSTALLDIR
mkdir -p $INSTALLDIR

BUILDDIR=$(pwd)

if [[ $(uname -m) == 'arm64' ]]; then
    BREW_PREFIX=/opt/homebrew
else
    BREW_PREFIX=/usr/local
fi

GDB_TARGET_FLAGS_EXTRA="--with-gmp=$BREW_PREFIX --with-mpfr=$BREW_PREFIX --with-libmpc=$BREW_PREFIX"
export GDB_TARGET_FLAGS_EXTRA

export NEWLIB_TUPLE=riscv32-pico-elf
export CFLAGS_FOR_TARGET_EXTRA="-mtune=hazard3"

cd riscv-gnu-toolchain
./configure --prefix=$BUILDDIR/$INSTALLDIR --enable-strip --disable-linux \
    --with-arch=rv32ima_zicsr_zifencei_zba_zbb_zbs_zbkb_zca_zcb_zcmp --with-abi=ilp32 \
    --with-multilib-generator="\
        rv32ima_zicsr_zifencei_zba_zbb_zbs_zbkb_zca_zcb_zcmp-ilp32--;\
        rv32imac_zicsr_zifencei_zba_zbb_zbs_zbkb-ilp32--;\
        rv32ima_zicsr_zifencei_zilsd_zba_zbb_zbs_zbkb_zbkx_zca_zcb_zclsd_zcmp_zibi-ilp32---hazard3_sim"
# 4 threads, as 8 threads runs out of memory
gmake -j4
