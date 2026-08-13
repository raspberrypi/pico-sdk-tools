#!/bin/bash

set -euo pipefail

export CXXFLAGS="-fno-char8_t"

INSTALLDIR="riscv-install/${MSYSTEM,,}"
rm -rf $INSTALLDIR
mkdir -p $INSTALLDIR

BUILDDIR=$(pwd)

export NEWLIB_TUPLE=riscv32-pico-elf
export CFLAGS_FOR_TARGET_EXTRA="-mtune=hazard3"

cd riscv-gnu-toolchain
./configure --prefix=$BUILDDIR/$INSTALLDIR --enable-strip --disable-linux \
    --with-arch=rv32ima_zicsr_zifencei_zba_zbb_zbs_zbkb_zca_zcb_zcmp --with-abi=ilp32 \
    --with-multilib-generator="\
        rv32ima_zicsr_zifencei_zba_zbb_zbs_zbkb_zca_zcb_zcmp-ilp32--;\
        rv32imac_zicsr_zifencei_zba_zbb_zbs_zbkb-ilp32--;\
        rv32ima_zicsr_zifencei_zilsd_zba_zbb_zbs_zbkb_zbkx_zca_zcb_zclsd_zcmp_zibi-ilp32---hazard3_sim"
make -j$(nproc)

cd "$BUILDDIR/$INSTALLDIR"
"$BUILDDIR/../packages/windows/copy-deps.sh"
