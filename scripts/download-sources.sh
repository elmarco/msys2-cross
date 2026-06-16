#!/bin/bash
set -euo pipefail

# Download all source tarballs needed for the bootstrap.
# Run this BEFORE `podman build` so the container build is fully offline.
#
# Usage: ./scripts/download-sources.sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/env-config.sh"

CACHE_DIR="${SCRIPT_DIR}/../sources"
mkdir -p "${CACHE_DIR}"

download() {
    local url="$1"
    local filename="${2:-${url##*/}}"
    local dest="${CACHE_DIR}/${filename}"
    if [[ -f "${dest}" ]]; then
        echo "  Already cached: ${filename}"
    else
        echo "  Downloading: ${filename}"
        curl -fSL -o "${dest}" "$url"
    fi
}

echo "==> Downloading toolchain sources..."
download "${BINUTILS_URL}"
download "${GCC_URL}"
download "${MINGW_W64_URL}"

echo "==> Downloading Rust source..."
download "${RUST_SRC_URL}"

echo "==> Downloading LLVM source..."
download "${LLVM_URL}"

echo ""
echo "==> All sources cached in ${CACHE_DIR}/"
echo ""
echo "Now build with: ./msys2-cross setup"
