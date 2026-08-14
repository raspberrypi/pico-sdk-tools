#!/bin/bash

set -euo pipefail

export CFLAGS=-static
export LDFLAGS=-static

INSTALLDIR="riscv-install"
rm -rf $INSTALLDIR
mkdir -p $INSTALLDIR

BUILDDIR=$(pwd)

export NEWLIB_TUPLE=riscv32-pico-elf
# Force newlib codegen to disable misaligned access, and use the hazard3 tune
export CFLAGS_FOR_TARGET_EXTRA="-mstrict-align -mtune=hazard3"
# This isn't necessary, because newlib configure picks up -mstrict-align
# and sets _HAVE_HW_MISALIGNED_ACCESS=no, but leaving in case of future
# bugs in newlib that do require this
# export NEWLIB_TARGET_FLAGS_EXTRA="--disable-newlib-hw-misaligned-access"

cd riscv-gnu-toolchain
./configure --prefix=$BUILDDIR/$INSTALLDIR --enable-strip --disable-linux \
    --with-arch=rv32ima_zicsr_zifencei_zba_zbb_zbs_zbkb_zca_zcb_zcmp --with-abi=ilp32 \
    --with-multilib-generator="\
        rv32ima_zicsr_zifencei_zba_zbb_zbs_zbkb_zca_zcb_zcmp-ilp32--;\
        rv32imac_zicsr_zifencei_zba_zbb_zbs_zbkb-ilp32--;\
        rv32ima_zicsr_zifencei_zilsd_zba_zbb_zbs_zbkb_zbkx_zca_zcb_zclsd_zcmp_zibi-ilp32---hazard3_sim"
make -j$(nproc)
