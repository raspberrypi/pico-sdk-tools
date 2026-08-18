#!/bin/bash

# Apply the patches under packages/common/patches to the repositories cloned by
# the top level build scripts (config/repositories.json).  Run from the build
# directory, as those scripts do.
#
# Each directory holding patches is named for the tree they apply to, relative
# to the build directory:
#
#     patches/gcc/*.patch                     -> build/gcc
#     patches/binutils-gdb/*.patch            -> build/binutils-gdb
#     patches/riscv-gnu-toolchain/gdb/*.patch -> build/riscv-gnu-toolchain/gdb
#
# so anything below the top level is a submodule of the repository above it, and
# is checked out before its patches are applied.

set -euo pipefail
shopt -s nullglob

BUILDDIR=$(pwd)
PATCHESDIR=$BUILDDIR/../packages/common/patches

while IFS= read -r patchdir; do
    patches=("${patchdir}"/*.patch)
    [[ ${#patches[@]} -gt 0 ]] || continue

    rel="${patchdir#"${PATCHESDIR}"/}"

    IFS='/' read -r -a parts <<< "${rel}"

    if [[ ! -d "${BUILDDIR}/${parts[0]}" ]]; then
        echo "Skipping ${rel}, as ${parts[0]} was not cloned for this build"
        continue
    fi

    # Walk down to the tree being patched, checking out each submodule on the
    # way.  Nothing to check out for a top level repository: the build scripts
    # have cloned it already.
    srcdir="${BUILDDIR}"
    for (( i = 0; i < ${#parts[@]}; i++ )); do
        if (( i > 0 )); then
            echo "Checking out ${parts[i]} in ${srcdir}"
            git -C "${srcdir}" \
                submodule update --init --progress --depth 1 "${parts[i]}"
        fi
        srcdir="${srcdir}/${parts[i]}"
    done

    if [[ ! -d "${srcdir}" ]]; then
        echo "No tree at ${srcdir} for the patches in ${patchdir}" >&2
        exit 1
    fi

    # git am requires user name and email
    echo "Setting Git user for ${rel}"
    git -C "${srcdir}" config user.name 'github-actions[bot]'
    git -C "${srcdir}" config user.email 'github-actions[bot]@users.noreply.github.com'

    for patch in "${patches[@]}"; do
        # A patch that reverses cleanly is one that is already in, and
        # applying it again would only fail.
        if git -C "${srcdir}" apply --reverse --check "${patch}" 2> /dev/null; then
            echo "Skipping $(basename "${patch}"), already applied to ${rel}"
            continue
        fi

        echo "Applying $(basename "${patch}") to ${rel}"
        git -C "${srcdir}" am "${patch}"
    done
done < <(find "${PATCHESDIR}" -type d | sort)
