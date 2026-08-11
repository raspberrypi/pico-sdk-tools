#!/bin/bash

set -euo pipefail

INSTALLDIR="riscv-install-$(uname -m)"
rm -rf $INSTALLDIR
mkdir -p $INSTALLDIR

BUILDDIR=$(pwd)

# Hazard3 traps on misaligned accesses, but GCC reports __riscv_misaligned_slow
# ("works, just slowly") for our -march, and newlib 4.6.0 reads that as "hardware
# can do it" and compiles the alignment checks out of its string functions. The
# result hangs on RP2350 -- see raspberrypi/pico-sdk#3118. Upstream newlib fixed
# this in d110c88b4, but riscv-gnu-toolchain still pins newlib-4.6.0, so tell
# newlib explicitly rather than letting it probe.
export NEWLIB_TARGET_FLAGS_EXTRA="--disable-newlib-hw-misaligned-access"

if [[ $(uname -m) == 'arm64' ]]; then
    GDB_TARGET_FLAGS_EXTRA="--with-gmp=/opt/homebrew --with-mpfr=/opt/homebrew"
    export GDB_TARGET_FLAGS_EXTRA
fi

cd riscv-gnu-toolchain
./configure --prefix=$BUILDDIR/$INSTALLDIR --enable-strip --with-arch=rv32ima_zicsr_zifencei_zba_zbb_zbs_zbkb_zca_zcb_zcmp --with-abi=ilp32 --with-multilib-generator="rv32ima_zicsr_zifencei_zba_zbb_zbs_zbkb_zca_zcb_zcmp-ilp32--;rv32imac_zicsr_zifencei_zba_zbb_zbs_zbkb-ilp32--"
# 4 threads, as 8 threads runs out of memory
gmake -j4
