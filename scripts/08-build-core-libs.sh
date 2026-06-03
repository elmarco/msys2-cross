#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/common.sh"

echo "========================================="
echo "Stage 8: Build core MINGW libraries"
echo "========================================="

MAKEPKG_MINGW=/opt/msys2-bootstrap/config/makepkg-mingw
REPO_DIR=/opt/msys2-bootstrap/repo
PACMAN_CONF=/opt/msys2-bootstrap/config/pacman-mingw.conf
MINGW_PACKAGES_DIR=/build/MINGW-packages

# Clone MINGW-packages if not present
if [[ ! -d "${MINGW_PACKAGES_DIR}" ]]; then
    echo "==> Cloning MINGW-packages (sparse)..."
    git clone --filter=blob:none --sparse \
        https://github.com/msys2/MINGW-packages.git \
        "${MINGW_PACKAGES_DIR}"
fi

# Core packages to build, in dependency order.
# These are the minimal set needed to bootstrap further builds.
CORE_PACKAGES=(
    mingw-w64-zlib
    mingw-w64-bzip2
    mingw-w64-xz
    mingw-w64-zstd
    mingw-w64-libiconv
    mingw-w64-gettext-runtime
    mingw-w64-libffi
    mingw-w64-pcre2
    mingw-w64-expat
    mingw-w64-gmp
    mingw-w64-mpfr
    mingw-w64-mpc
)

build_mingw_package() {
    local pkg="$1"

    echo ""
    echo "========================================="
    echo "Building ${pkg}"
    echo "========================================="

    # Sparse checkout just this package
    cd "${MINGW_PACKAGES_DIR}"
    git sparse-checkout add "${pkg}"

    if [[ ! -d "${MINGW_PACKAGES_DIR}/${pkg}" ]]; then
        echo "WARNING: ${pkg} not found in MINGW-packages, skipping"
        return 0
    fi

    cd "${MINGW_PACKAGES_DIR}/${pkg}"

    # Build with our cross-compilation makepkg-mingw
    PKGDEST="${REPO_DIR}" \
    "${MAKEPKG_MINGW}" \
        --skipchecksums \
        --skippgpcheck \
        --nocheck \
        --force \
        --log \
        2>&1 || {
            echo "WARNING: Failed to build ${pkg}, continuing..."
            return 0
        }

    # Update repo database with new packages
    repo-add "${REPO_DIR}/local.db.tar.zst" "${REPO_DIR}"/*.pkg.tar.zst 2>/dev/null || true

    # Install the built packages
    for pkgfile in "${REPO_DIR}"/mingw-w64-ucrt-x86_64-*"${pkg#mingw-w64-}"*.pkg.tar.zst; do
        if [[ -f "${pkgfile}" ]]; then
            pacman --config "${PACMAN_CONF}" -U --noconfirm "${pkgfile}" 2>/dev/null || true
        fi
    done
}

for pkg in "${CORE_PACKAGES[@]}"; do
    build_mingw_package "${pkg}"
done

echo ""
echo "========================================="
echo "Core libraries build complete"
echo "========================================="
echo "Installed packages:"
pacman --config "${PACMAN_CONF}" -Q
