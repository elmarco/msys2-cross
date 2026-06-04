#!/bin/bash
set -euo pipefail

# Version pins — matched to MSYS2 MINGW-packages as of 2026-06-03
GCC_VERSION=16.1.0
BINUTILS_VERSION=2.46
MINGW_W64_COMMIT=93753750c96c8a36a1db2e1b30753f6e9e7aba28
MINGW_W64_VERSION=14.0.0

# Target triple
TARGET=x86_64-w64-mingw32
MINGW_PREFIX=/ucrt64
SYSROOT=/ucrt64

# Build parallelism
JOBS=$(nproc)

# Directories
SRC_DIR=/build/src
BUILD_DIR=/build/build
INSTALL_STAGING=/build/staging
# Pre-downloaded sources (populated by download-sources.sh, COPY'd in)
SOURCES_CACHE=/build/sources

# Source URLs
GCC_URL="https://ftp.gnu.org/gnu/gcc/gcc-${GCC_VERSION}/gcc-${GCC_VERSION}.tar.xz"
BINUTILS_URL="https://ftp.gnu.org/gnu/binutils/binutils-with-gold-${BINUTILS_VERSION}.tar.bz2"
MINGW_W64_URL="https://github.com/mingw-w64/mingw-w64/archive/${MINGW_W64_COMMIT}.tar.gz"

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

# Create build directories (only inside containers)
if [[ -w /build ]] || mkdir -p "${SRC_DIR}" "${BUILD_DIR}" "${INSTALL_STAGING}" 2>/dev/null; then
    true
fi
