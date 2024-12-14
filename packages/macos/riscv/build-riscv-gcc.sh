#!/bin/bash

set -euo pipefail

# INSTALLDIR="riscv-install-$(uname -m)"
INSTALLDIR="riscv-install"
rm -rf $INSTALLDIR
mkdir -p $INSTALLDIR

BUILDDIR=$(pwd)

GDB_TARGET_FLAGS_EXTRA="--with-gmp=/opt/homebrew --with-mpfr=/opt/homebrew"
export GDB_TARGET_FLAGS_EXTRA

cd riscv-gnu-toolchain
./configure --prefix=$BUILDDIR/$INSTALLDIR --with-arch=rv32ima_zicsr_zifencei_zba_zbb_zbs_zbkb_zca_zcb --with-abi=ilp32 --with-multilib-generator="rv32ima_zicsr_zifencei_zba_zbb_zbs_zbkb_zca_zcb-ilp32--;rv32imac_zicsr_zifencei_zba_zbb_zbs_zbkb-ilp32--" --with-gcc-src=$BUILDDIR/gcc
# 4 threads, as 8 threads runs out of memory
make -j4

# Make x64 and Windows toolchains, by copying multilib into existing toolchains
cd ..
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

$SCRIPT_DIR/build-riscv-gcc-other.sh "https://buildbot.embecosm.com/job/riscv32-gcc-macos-release/21/artifact/riscv32-embecosm-macos-gcc13.3.0.zip" "x64-mac"
