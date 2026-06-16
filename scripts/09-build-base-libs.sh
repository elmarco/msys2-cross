#!/bin/bash
set -euo pipefail

# Build the minimal set of cross-compiled libraries that MSYS2 packages
# implicitly assume are always present (the MSYS2 "base" system).
# These are built with --nodeps to break circular dependencies
# (libiconv ↔ gettext), then installed into the mingw pacman DB.

echo "========================================="
echo "Stage 9: Build base libraries"
echo "========================================="

MINGW_PACKAGES_DIR=/tmp/mingw-packages
BOOTSTRAP_DIR=/opt/msys2-cross
PACMAN_CONF="${BOOTSTRAP_DIR}/config/pacman-mingw.conf"
REPO_DIR="${BOOTSTRAP_DIR}/repo"

source "${BOOTSTRAP_DIR}/scripts/env-config.sh"
export MSYSTEM MINGW_PREFIX MINGW_CHOST MINGW_PACKAGE_PREFIX
export PATH="${BOOTSTRAP_DIR}/wrappers:${BOOTSTRAP_DIR}/config:${PATH}"

# Sparse-clone MINGW-packages once, then add directories as needed
git clone --filter=blob:none --sparse --depth=1 \
    https://github.com/msys2/MINGW-packages.git \
    "${MINGW_PACKAGES_DIR}"

build_base_pkg() {
    local pkgbase="$1"

    echo "==> Building base library: ${pkgbase}"
    git -C "${MINGW_PACKAGES_DIR}" sparse-checkout add "${pkgbase}"

    local pkgdir="${MINGW_PACKAGES_DIR}/${pkgbase}"
    chown -R builduser: "${pkgdir}"

    su builduser -s /bin/bash -c \
        "cd '${pkgdir}' && makepkg-mingw --skipchecksums --nodeps"

    # Install all split packages into the mingw DB
    cp "${pkgdir}"/*.pkg.tar.* "${REPO_DIR}/"
    pacman --config "${PACMAN_CONF}" -Udd --noconfirm --overwrite='*' "${pkgdir}"/*.pkg.tar.*
}

# Build order matters: libiconv first (gettext depends on it)
build_base_pkg mingw-w64-libiconv
build_base_pkg mingw-w64-gettext

# Rebuild repo database with the new packages
repo-add "${REPO_DIR}/msys2-cross.db.tar.zst" "${REPO_DIR}"/*.pkg.tar.*
pacman --config "${PACMAN_CONF}" -Sy --noconfirm

echo "==> Base libraries installed:"
pacman --config "${PACMAN_CONF}" -Q | grep -E 'iconv|gettext'

rm -rf "${MINGW_PACKAGES_DIR}"
