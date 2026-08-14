#!/bin/bash

set -euo pipefail

export CXXFLAGS="-fno-char8_t"

# Hazard3 traps on misaligned accesses, but GCC reports __riscv_misaligned_slow
# ("works, just slowly") for our -march, and newlib reads that as "the hardware
# can do it" and drops the alignment checks from its string functions. The result
# hangs on RP2350 -- see raspberrypi/pico-sdk#3118.
#
# newlib decides this in two independent places, and -mstrict-align covers both:
#
#   - the RISC-V specific routines (strcmp.S, rv_string.h, memcpy.c, memmove.c,
#     setjmp.S) test __riscv_misaligned_slow/_fast directly. -mstrict-align makes
#     GCC report __riscv_misaligned_avoid instead, so their guards are kept.
#
#   - the generic C routines (strncmp, memcmp, ...) test
#     _HAVE_HW_MISALIGNED_ACCESS, which newlib's configure sets by probing those
#     same macros. Under -mstrict-align the probe answers no and the macro is
#     left undefined, so --disable-newlib-hw-misaligned-access is not needed.
#
# Both arrived in newlib 4.6.0, from commit dcf5d237f. Do not assume a newer
# newlib makes this unnecessary: the upstream fix, d110c88b4, only relaxes the
# configure probe. It leaves strcmp.S and friends testing the compiler macros
# directly, so on a core GCC calls "slow" they stay unguarded no matter which
# newlib is pinned. -mstrict-align is the permanent fix here, not a stopgap.
export CFLAGS_FOR_TARGET_EXTRA="-mstrict-align"

INSTALLDIR="riscv-install/${MSYSTEM,,}"
rm -rf $INSTALLDIR
mkdir -p $INSTALLDIR

BUILDDIR=$(pwd)

cd riscv-gnu-toolchain
./configure --prefix=$BUILDDIR/$INSTALLDIR --enable-strip --with-arch=rv32ima_zicsr_zifencei_zba_zbb_zbs_zbkb_zca_zcb_zcmp --with-abi=ilp32 --with-multilib-generator="rv32ima_zicsr_zifencei_zba_zbb_zbs_zbkb_zca_zcb_zcmp-ilp32--;rv32imac_zicsr_zifencei_zba_zbb_zbs_zbkb-ilp32--"
make -j$(nproc)

cd "$BUILDDIR/$INSTALLDIR"
"$BUILDDIR/../packages/windows/copy-deps.sh"
