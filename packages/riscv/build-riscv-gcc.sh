#!/bin/bash

# Build the RISC-V toolchain.  Run from the build directory, by build.sh.

set -euo pipefail

BUILDDIR=$(pwd)
INSTALLDIR="riscv-install${ARCH_SUFFIX}"
rm -rf "$INSTALLDIR"
mkdir -p "$INSTALLDIR"

case $PLATFORM in
    linux)
        export CFLAGS=-static
        export LDFLAGS=-static
        MAKE=make
        JOBS=$(nproc)
        ;;
    macos)
        if [[ $(uname -m) == 'arm64' ]]; then
            BREW_PREFIX=/opt/homebrew
        else
            BREW_PREFIX=/usr/local
        fi
        export GDB_TARGET_FLAGS_EXTRA="--with-gmp=$BREW_PREFIX --with-mpfr=$BREW_PREFIX --with-libmpc=$BREW_PREFIX"
        MAKE=gmake
        # 4 threads, as 8 threads runs out of memory
        JOBS=4
        ;;
    windows)
        export CXXFLAGS="-fno-char8_t"
        MAKE=make
        JOBS=$(nproc)
        ;;
esac

export NEWLIB_TUPLE=riscv32-pico-elf
# Force newlib codegen to disable misaligned access, and use the hazard3 tune
export CFLAGS_FOR_TARGET_EXTRA="-mstrict-align -mtune=hazard3"
# This isn't necessary, because newlib configure picks up -mstrict-align
# and sets _HAVE_HW_MISALIGNED_ACCESS=no, but leaving in case of future
# bugs in newlib that do require this
# export NEWLIB_TARGET_FLAGS_EXTRA="--disable-newlib-hw-misaligned-access"

cd riscv-gnu-toolchain
./configure --prefix="$BUILDDIR/$INSTALLDIR" --enable-strip --disable-linux \
    --with-gcc-src="$BUILDDIR/gcc" --with-binutils-src="$BUILDDIR/binutils-gdb" \
    --with-arch=rv32ima_zicsr_zifencei_zba_zbb_zbs_zbkb_zca_zcb_zcmp --with-abi=ilp32 \
    --with-multilib-generator="\
        rv32ima_zicsr_zifencei_zba_zbb_zbs_zbkb_zca_zcb_zcmp-ilp32--;\
        rv32imac_zicsr_zifencei_zba_zbb_zbs_zbkb-ilp32--;\
        rv32ima_zicsr_zifencei_zilsd_zba_zbb_zbs_zbkb_zbkx_zca_zcb_zclsd_zcmp_zibi-ilp32---hazard3_sim"
"$MAKE" -j"$JOBS"

if [[ $PLATFORM == windows ]]; then
    cd "$BUILDDIR/$INSTALLDIR"
    "$BUILDDIR/../packages/windows/copy-deps.sh"
fi
