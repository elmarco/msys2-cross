#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/common.sh"

echo "========================================="
echo "Stage 7: Set up pacman + local repo"
echo "========================================="

REPO_DIR=/opt/msys2-bootstrap/repo
PACMAN_CONF=/opt/msys2-bootstrap/config/pacman-mingw.conf
PKG_DIR=/opt/msys2-bootstrap/packages

# Create pacman directories
mkdir -p /var/lib/pacman/mingw
mkdir -p /var/cache/pacman/mingw/pkg
mkdir -p "${REPO_DIR}"

# Initialize pacman database
pacman --config "${PACMAN_CONF}" -Sy --noconfirm 2>/dev/null || true

# Make wrappers executable
chmod +x /opt/msys2-bootstrap/wrappers/*
chmod +x /opt/msys2-bootstrap/config/makepkg-mingw

# Build toolchain packages from the bootstrap artifacts.
# These are "repackaging" PKGBUILDs that capture the already-installed
# cross-compiler into pacman packages.
build_package() {
    local pkgdir="$1"
    local pkgname
    pkgname=$(basename "${pkgdir}")

    echo "==> Packaging ${pkgname}..."

    cd "${pkgdir}"

    # Use host makepkg (not makepkg-mingw) since these are packaging
    # scripts, not cross-compilation builds.
    PKGDEST="${REPO_DIR}" \
    makepkg \
        --nodeps \
        --skipinteg \
        --nocheck \
        --force \
        2>&1 | tail -5
}

# Package in dependency order
build_package "${PKG_DIR}/mingw-w64-ucrt-x86_64-cross-binutils"
build_package "${PKG_DIR}/mingw-w64-ucrt-x86_64-cross-headers"
build_package "${PKG_DIR}/mingw-w64-ucrt-x86_64-cross-crt"
build_package "${PKG_DIR}/mingw-w64-ucrt-x86_64-cross-winpthreads"
build_package "${PKG_DIR}/mingw-w64-ucrt-x86_64-cross-gcc"
build_package "${PKG_DIR}/mingw-w64-ucrt-x86_64-cmake"
build_package "${PKG_DIR}/mingw-w64-ucrt-x86_64-meson"
build_package "${PKG_DIR}/mingw-w64-ucrt-x86_64-pkgconf"

# Create repo database
echo "==> Creating repo database..."
repo-add "${REPO_DIR}/local.db.tar.zst" "${REPO_DIR}"/*.pkg.tar.zst

# Sync pacman with the new repo
pacman --config "${PACMAN_CONF}" -Sy --noconfirm

# Install all toolchain packages
pacman --config "${PACMAN_CONF}" -U --noconfirm "${REPO_DIR}"/*.pkg.tar.zst

echo "==> Pacman local repo ready at ${REPO_DIR}"
echo "==> Installed toolchain packages:"
pacman --config "${PACMAN_CONF}" -Q
