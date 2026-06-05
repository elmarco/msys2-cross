#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/common.sh"

echo "========================================="
echo "Stage 7: Set up pacman + local repo"
echo "========================================="

REPO_DIR=/opt/msys2-cross/repo
PACMAN_CONF=/opt/msys2-cross/config/pacman-mingw.conf
PKG_DIR=/opt/msys2-cross/packages

# makepkg refuses to run as root; create a build user
if [[ "$(id -u)" == "0" ]]; then
    useradd -m builduser 2>/dev/null || true
    # Give builduser write access to directories makepkg needs
    chown -R builduser: "${PKG_DIR}"
fi

# Create pacman directories
mkdir -p /var/lib/pacman/mingw
mkdir -p /var/cache/pacman/mingw/pkg
mkdir -p "${REPO_DIR}"

# Initialize pacman database
pacman --config "${PACMAN_CONF}" -Sy --noconfirm 2>/dev/null || true

# Make wrappers executable
chmod +x /opt/msys2-cross/wrappers/*
chmod +x /opt/msys2-cross/config/makepkg-mingw

# Build toolchain packages from the bootstrap artifacts.
# These are "repackaging" PKGBUILDs that capture the already-installed
# cross-compiler into pacman packages.
build_package() {
    local pkgdir="$1"
    local pkgname
    pkgname=$(basename "${pkgdir}")

    echo "==> Packaging ${pkgname}..."

    # Use host makepkg (not makepkg-mingw) since these are packaging
    # scripts, not cross-compilation builds.
    local _conf=/opt/msys2-cross/config/makepkg_mingw.conf

    if [[ "$(id -u)" == "0" ]]; then
        chown -R builduser: "${pkgdir}"
        su builduser -s /bin/bash -c "cd '${pkgdir}' && makepkg --config '${_conf}' --nodeps --skipinteg --nocheck --force"
    else
        cd "${pkgdir}"
        makepkg --config "${_conf}" --nodeps --skipinteg --nocheck --force
    fi

    # Move built packages to the repo (match any pkg.tar.* extension)
    mv "${pkgdir}"/*.pkg.tar.* "${REPO_DIR}/" 2>/dev/null || true
    echo "==> Packages in repo: $(ls "${REPO_DIR}"/*.pkg.tar.* 2>/dev/null | wc -l)"
}

# Package in dependency order
build_package "${PKG_DIR}/mingw-w64-ucrt-x86_64-cross-binutils"
build_package "${PKG_DIR}/mingw-w64-ucrt-x86_64-cross-headers"
build_package "${PKG_DIR}/mingw-w64-ucrt-x86_64-cross-crt"
build_package "${PKG_DIR}/mingw-w64-ucrt-x86_64-cross-winpthreads"
build_package "${PKG_DIR}/mingw-w64-ucrt-x86_64-cross-gcc"
build_package "${PKG_DIR}/mingw-w64-ucrt-x86_64-autotools"
build_package "${PKG_DIR}/mingw-w64-ucrt-x86_64-cmake"
build_package "${PKG_DIR}/mingw-w64-ucrt-x86_64-ninja"
build_package "${PKG_DIR}/mingw-w64-ucrt-x86_64-meson"
build_package "${PKG_DIR}/mingw-w64-ucrt-x86_64-pkgconf"
build_package "${PKG_DIR}/mingw-w64-ucrt-x86_64-python-docutils"
build_package "${PKG_DIR}/mingw-w64-ucrt-x86_64-gi-docgen"
build_package "${PKG_DIR}/mingw-w64-ucrt-x86_64-gobject-introspection"

# Create repo database
echo "==> Creating repo database..."
repo-add "${REPO_DIR}/msys2-cross.db.tar.zst" "${REPO_DIR}"/*.pkg.tar.*

# Sync pacman with the new repo
pacman --config "${PACMAN_CONF}" -Sy --noconfirm

# Install all toolchain packages
pacman --config "${PACMAN_CONF}" -U --noconfirm --overwrite='*' "${REPO_DIR}"/*.pkg.tar.*

echo "==> Pacman local repo ready at ${REPO_DIR}"
echo "==> Installed toolchain packages:"
pacman --config "${PACMAN_CONF}" -Q
