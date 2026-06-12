#!/bin/bash
set -euo pipefail

# Version pins — matched to MSYS2 MINGW-packages as of 2026-06-03
GCC_VERSION=16.1.0
BINUTILS_VERSION=2.46
MINGW_W64_COMMIT=818fa65100f7
MINGW_W64_VERSION=14.0.0

# Target triple
TARGET=x86_64-w64-mingw32
MINGW_PREFIX=/ucrt64
SYSROOT=/ucrt64

# Build parallelism
JOBS=$(nproc)

# Directories (overridable for RPM builds / bare-host usage)
SRC_DIR=${SRC_DIR:-/build/src}
BUILD_DIR=${BUILD_DIR:-/build/build}
INSTALL_STAGING=${INSTALL_STAGING:-/build/staging}
SOURCES_CACHE=${SOURCES_CACHE:-/build/sources}

# DESTDIR for staged installs (empty = install directly, as in container)
DESTDIR=${DESTDIR:-}
export DESTDIR

# When staging, ensure cross-tools are found in the staging tree
if [[ -n "${DESTDIR}" ]]; then
    export PATH="${DESTDIR}/usr/bin:${PATH}"
fi

# Source URLs
GCC_URL="https://ftp.gnu.org/gnu/gcc/gcc-${GCC_VERSION}/gcc-${GCC_VERSION}.tar.xz"
BINUTILS_URL="https://ftp.gnu.org/gnu/binutils/binutils-with-gold-${BINUTILS_VERSION}.tar.bz2"
MINGW_W64_URL="https://github.com/mingw-w64/mingw-w64/archive/${MINGW_W64_COMMIT}.tar.gz"

# Rust (std library cross-compiled for mingw target)
RUST_VERSION=1.96.0
RUST_SRC_URL="https://static.rust-lang.org/dist/rustc-${RUST_VERSION}-src.tar.xz"


download_and_extract() {
    local url="$1"
    local dest="$2"
    local archive="${url##*/}"

    if [[ ! -d "$dest" ]]; then
        # Use pre-downloaded source if available, otherwise download
        if [[ -f "${SOURCES_CACHE}/${archive}" ]]; then
            echo "==> Using cached ${archive}"
            cp "${SOURCES_CACHE}/${archive}" "${SRC_DIR}/${archive}"
        else
            echo "==> Downloading ${archive}..."
            curl -fSL -o "${SRC_DIR}/${archive}" "$url"
        fi
        echo "==> Extracting ${archive}..."
        mkdir -p "$dest"
        tar xf "${SRC_DIR}/${archive}" -C "$dest" --strip-components=1
    else
        echo "==> ${dest} already exists, skipping download"
    fi
}

mkdir -p "${SRC_DIR}" "${BUILD_DIR}" "${INSTALL_STAGING}" 2>/dev/null || true
