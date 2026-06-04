#!/bin/bash
set -euo pipefail

# Download all source tarballs needed for the bootstrap.
# Run this BEFORE `podman build` so the container build is fully offline.
#
# Usage: ./scripts/download-sources.sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

CACHE_DIR="${SCRIPT_DIR}/../sources"
mkdir -p "${CACHE_DIR}"

download() {
    local url="$1"
    local dest="${CACHE_DIR}/${url##*/}"
    if [[ -f "${dest}" ]]; then
        echo "  Already cached: ${dest##*/}"
    else
        echo "  Downloading: ${url##*/}"
        curl -fSL -o "${dest}" "$url"
    fi
}

echo "==> Downloading toolchain sources..."
download "${BINUTILS_URL}"
download "${GCC_URL}"
download "${MINGW_W64_URL}"

echo "==> Downloading MINGW-packages sources..."

# Clone/update MINGW-packages (sparse) for PKGBUILDs
MINGW_PKG_DIR="${SCRIPT_DIR}/../MINGW-packages"
if [[ ! -d "${MINGW_PKG_DIR}" ]]; then
    git clone --filter=blob:none --sparse \
        https://github.com/msys2/MINGW-packages.git \
        "${MINGW_PKG_DIR}"
fi

CORE_PACKAGES=(
    mingw-w64-bzip2
    mingw-w64-zlib
    mingw-w64-xz
    mingw-w64-zstd
    mingw-w64-libiconv
    mingw-w64-gettext
    mingw-w64-libffi
    mingw-w64-pcre2
    mingw-w64-expat
)

cd "${MINGW_PKG_DIR}"
for pkg in "${CORE_PACKAGES[@]}"; do
    git sparse-checkout add "${pkg}" 2>/dev/null || true
done

# Download each package's sources using makepkg --allsource
for pkg in "${CORE_PACKAGES[@]}"; do
    if [[ -d "${MINGW_PKG_DIR}/${pkg}" ]]; then
        echo "  Fetching sources for ${pkg}..."
        cd "${MINGW_PKG_DIR}/${pkg}"
        makepkg --nobuild --nodeps --noprepare \
            --skipchecksums --skippgpcheck \
            --config /dev/null \
            SRCDEST="${CACHE_DIR}" \
            2>/dev/null || true
        cd "${MINGW_PKG_DIR}"
    fi
done

echo ""
echo "==> All sources cached in ${CACHE_DIR}/"
echo "==> MINGW-packages checked out in ${MINGW_PKG_DIR}/"
echo ""
echo "Now build with: podman build -t msys2-cross ."
