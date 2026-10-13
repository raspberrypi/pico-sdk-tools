#!/bin/bash

# Build and package the SDK tools on Linux, macOS, or Windows (from an MSYS2
# UCRT64, MINGW64, CLANG64 or CLANGARM64 shell).  Packages are written to bin/.
#
# Usage: ./build.sh [options]
#
#   --sdk-version VER    Build the tools for this pico-sdk tree, rather than
#                        the one in version.txt.
#   --skip-download      Don't install prerequisites or clone repositories,
#                        but use what is already in build/.  Components
#                        already built are not rebuilt.
#   --merge              macOS only: merge the arm64 and x86_64 builds into
#                        universal binaries, and package those.  Each build
#                        leaves its binaries in build/*-<arch> for this.
#
# Set SKIP_RISCV, SKIP_OPENOCD or SKIP_PICOTOOL to 1 to skip that component.

set -euo pipefail

cd "$(dirname "$0")"

SKIP_RISCV=${SKIP_RISCV-0}
SKIP_OPENOCD=${SKIP_OPENOCD-0}
SKIP_PICOTOOL=${SKIP_PICOTOOL-0}

sdk_version=
skip_download=0
merge=0
while [[ $# -gt 0 ]]; do
    case $1 in
        --sdk-version) sdk_version=$2; shift 2 ;;
        --skip-download) skip_download=1; shift ;;
        --merge) merge=1; shift ;;
        *) echo "Unknown option $1" >&2; exit 1 ;;
    esac
done

case "$(uname -s)" in
    Linux*) PLATFORM=linux ;;
    Darwin*) PLATFORM=macos ;;
    MINGW*|MSYS*|UCRT*|CLANG*) PLATFORM=windows ;;
    *) echo "Unsupported host $(uname -s)" >&2; exit 1 ;;
esac

if [[ $PLATFORM == windows ]]; then
    # The plain MSYS environment has no native toolchain, and pacboy needs the prefix
    if ! command -v pacman > /dev/null || [[ -z ${MINGW_PACKAGE_PREFIX-} ]]; then
        echo "On Windows, run this from an MSYS2 UCRT64, MINGW64, CLANG64 or CLANGARM64 shell (https://www.msys2.org)" >&2
        exit 1
    fi
    # Use real symlinks
    export MSYS=winsymlinks:nativestrict
fi

echo "Building on ${PLATFORM} $(uname -m)"

case $PLATFORM in
    linux)
        suffix="$(uname -m)-lin"
        ext=tar.gz
        tar=tar
        ARCH_SUFFIX=
        ;;
    macos)
        suffix=mac
        ext=zip
        tar=tar
        # make-universal.sh merges build/<dir>-arm64 and build/<dir>-x86_64
        ARCH_SUFFIX="-$(uname -m)"
        export MACOSX_DEPLOYMENT_TARGET=14.0
        ;;
    windows)
        # Not uname -m, which is the x86_64 MSYS2 runtime even on Arm
        case $MSYSTEM_CARCH in
            aarch64) suffix=arm64-win ;;
            *) suffix=x64-win ;;
        esac
        ext=zip
        # GNU tar cannot write zip files
        tar=bsdtar
        ARCH_SUFFIX=
        ;;
esac

if [[ -n $sdk_version ]]; then
    echo "Version set to $sdk_version"
    version=$sdk_version
else
    version=$(tr -d '[:space:]' < version.txt)
fi
sdk_major=${version%%.*}

# Used by the scripts under packages/
export PLATFORM ARCH_SUFFIX version

topd=$PWD

install_prerequisites() {
    case $PLATFORM in
        linux)
            sudo apt install -y jq cmake libtool automake libusb-1.0-0-dev libhidapi-dev libftdi1-dev patchelf
            # RISC-V prerequisites
            sudo apt install -y autoconf automake autotools-dev curl python3 python3-pip libmpc-dev libmpfr-dev libgmp-dev gawk build-essential bison flex texinfo gperf libtool patchutils bc zlib1g-dev ninja-build git cmake libglib2.0-dev libslirp-dev
            # RPi Only prerequisites
            if [[ $(uname -m) == 'aarch64' ]]; then
                sudo apt install -y libgpiod-dev
            fi
            ;;
        macos)
            local brew
            if [[ $(uname -m) == 'arm64' ]]; then
                brew=/opt/homebrew/bin/brew
            else
                brew=/usr/local/bin/brew
            fi
            arch -"$(uname -m)" "$brew" install jq libtool libusb automake hidapi --quiet
            # RISC-V prerequisites, less python3 and libslirp which are only for QEMU
            arch -"$(uname -m)" "$brew" install gawk gnu-sed make gmp mpfr libmpc isl zlib expat texinfo flock --quiet
            ;;
        windows)
            pacman -S --noconfirm --needed autoconf automake base-devel expat git libtool texinfo pactoys patchutils pkg-config jq
            # pacboy adds MINGW_PACKAGE_PREFIX to package names suffixed with :p
            pacboy -S --noconfirm --needed cmake:p ninja:p toolchain:p libusb:p hidapi:p libslirp:p libarchive:p
            ;;
    esac
}

clone_repositories() {
    local repo tree href repodir skip
    while read -r repo; do
        tree=$(jq -r .tree <<< "$repo")
        href=$(jq -r .href <<< "$repo")
        repodir=$(basename "$href" .git)
        repodir="build/${repodir%-rp2350}"

        skip=
        if [[ $(jq -r .riscv <<< "$repo") == true && $SKIP_RISCV == 1 ]]; then
            skip=SKIP_RISCV
        elif [[ $(jq -r .openocd <<< "$repo") == true && $SKIP_OPENOCD == 1 ]]; then
            skip=SKIP_OPENOCD
        elif [[ $(jq -r .pi_only <<< "$repo") == true && ! ($PLATFORM == linux && $(uname -m) == aarch64) ]]; then
            skip="pi_only"
        fi
        if [[ -n $skip ]]; then
            echo "Skipping ${href} as ${skip} is set"
            continue
        fi

        if [[ $skip_download == 1 ]]; then
            echo "Checking ${repodir}"
            git -C "${repodir}" describe --all
            continue
        fi

        echo "${href} ${tree} ${repodir}"
        rm -rf "${repodir}"
        git clone -b "${tree}" --depth=1 -c advice.detachedHead=false "${href}" "${repodir}"
        if [[ $(jq -r .submodules <<< "$repo") == true ]]; then
            git -C "${repodir}" submodule update --init --depth=1
        fi
    done < <(jq -c --arg v "$sdk_version" \
        '.repositories | (if $v != "" then .[0].tree = $v else . end) | .[]' \
        config/repositories.json)
}

# Whether to skip building a component, as --skip-download is reusing the last build
already_built() {
    if [[ $skip_download == 1 && -d "$1" ]]; then
        echo "Not rebuilding $1, as it already exists"
        return 0
    fi
    return 1
}

build_components() {
    cd build

    # Apply any patches, including the host specific ones
    ../packages/common/apply-patches.sh "../packages/${PLATFORM}/patches"

    if [[ $SKIP_OPENOCD != 1 ]] && ! already_built "openocd-install${ARCH_SUFFIX}"; then
        if ! ../packages/openocd/build-openocd.sh; then
            echo "::error title=openocd-fail-${suffix}::OpenOCD Build Failed on ${PLATFORM} $(uname -m)"
            SKIP_OPENOCD=1
        elif [[ $PLATFORM == macos ]]; then
            ../packages/macos/get-dylibs.sh "openocd-install${ARCH_SUFFIX}"
            echo "OpenOCD dylibs copied"
        fi
    fi

    if [[ $SKIP_RISCV != 1 ]] && ! already_built "riscv-install${ARCH_SUFFIX}"; then
        # Takes ages to build
        ../packages/riscv/build-riscv-gcc.sh
        echo "RISC-V Build Complete"
        if [[ $PLATFORM == macos ]]; then
            ../packages/macos/get-dylibs.sh "riscv-install${ARCH_SUFFIX}"
            echo "RISC-V dylibs copied"
        fi
    fi

    if [[ $SKIP_PICOTOOL != 1 ]] && ! already_built "picotool-install${ARCH_SUFFIX}"; then
        ../packages/picotool/build-picotool.sh
        echo "Picotool Build Complete"
        if [[ $PLATFORM == macos ]]; then
            ../packages/macos/get-dylibs.sh "picotool-install${ARCH_SUFFIX}"
            echo "Picotool dylibs copied"
        fi
    fi

    cd ..
}

merge_macos() {
    cd build
    if [[ $SKIP_OPENOCD != 1 ]]; then
        ../packages/macos/make-universal.sh openocd-install
        echo "OpenOCD Merge Complete"
    fi
    if [[ $SKIP_RISCV != 1 ]]; then
        ../packages/macos/make-universal.sh riscv-install
        echo "RISC-V Merge Complete"
    fi
    if [[ $SKIP_PICOTOOL != 1 ]]; then
        ../packages/macos/make-universal.sh picotool-install
        echo "Picotool Merge Complete"
        if [[ $sdk_major -ge 2 ]]; then
            ../packages/macos/make-universal.sh pico-sdk-tools
            echo "Pico SDK Tools Merge Complete"
        fi
    fi
    cd ..
}

# package <directory> <package name, without suffix>
package() {
    local filename="$2-${suffix}.${ext}"
    echo "Saving $2 package to bin/${filename}"
    (cd "$1" && shopt -s dotglob && "$tar" -a -cf "${topd}/bin/${filename}" *)
}

package_all() {
    local v

    if [[ $SKIP_PICOTOOL != 1 ]]; then
        # Windows packages the elf2uf2 and pioasm built for SDK 1.x too
        if [[ $sdk_major -ge 2 || $PLATFORM == windows ]]; then
            package build/pico-sdk-tools "pico-sdk-tools-${version}"
        fi

        v=$(build/picotool-install/picotool/picotool version -s)
        echo "Picotool version $v"
        package build/picotool-install "picotool-${v}"
    fi

    if [[ $SKIP_OPENOCD != 1 ]]; then
        if [[ $PLATFORM == windows ]]; then
            # Files with non-ASCII names (1986ве1т.cfg, к1879xб1я.cfg) upset
            # some decompression libraries
            LC_ALL=C find build/openocd-install/install/openocd/scripts -name '*[! -~]*' -print -delete
        fi

        # "Open On-Chip Debugger 0.12.0+dev-gabcdef (date)" -> 0.12.0+dev
        v=$(build/openocd-install/install/openocd/openocd --version 2>&1 | awk 'NR == 1 { print $4 }' | cut -d- -f1)
        echo "OpenOCD version $v"
        package build/openocd-install/install/openocd "openocd-${v}"
    fi

    if [[ $SKIP_RISCV != 1 ]]; then
        v=$(build/riscv-install/bin/riscv32-pico-elf-gcc -dumpversion | cut -d. -f1)
        echo "RISC-V Toolchain version $v"
        package build/riscv-install "riscv-toolchain-${v}"
    fi
}

mkdir -p build bin

if [[ $merge == 1 ]]; then
    if [[ $PLATFORM != macos ]]; then
        echo "--merge is only for macOS" >&2
        exit 1
    fi
    merge_macos
    package_all
    exit 0
fi

if [[ $skip_download != 1 ]]; then
    install_prerequisites
fi

if [[ $PLATFORM == windows ]]; then
    git config --global core.autocrlf false
fi

clone_repositories
build_components

# macOS packages the universal binaries, after --merge
if [[ $PLATFORM != macos ]]; then
    package_all
fi
