#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/common.sh"

echo "========================================="
echo "Stage 8: Build core MINGW libraries"
echo "========================================="

MAKEPKG_MINGW=/opt/msys2-cross/config/makepkg-mingw
REPO_DIR=/opt/msys2-cross/repo
PACMAN_CONF=/opt/msys2-cross/config/pacman-mingw.conf
MINGW_PACKAGES_DIR=/build/MINGW-packages

# MINGW-packages should be pre-populated by download-sources.sh and
# COPY'd in by the Containerfile. No network access needed.
if [[ ! -d "${MINGW_PACKAGES_DIR}" ]]; then
    echo "==> ERROR: ${MINGW_PACKAGES_DIR} not found."
    echo "==> Run scripts/download-sources.sh first."
    exit 1
fi

# Core packages to build, in dependency order.
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

build_and_install() {
    local pkg="$1"

    echo ""
    echo "========================================="
    echo "Building ${pkg}"
    echo "========================================="

    cd "${MINGW_PACKAGES_DIR}"
    git sparse-checkout add "${pkg}"

    if [[ ! -d "${MINGW_PACKAGES_DIR}/${pkg}" ]]; then
        echo "WARNING: ${pkg} not found in MINGW-packages, skipping"
        return 0
    fi

    local _pkgdir="${MINGW_PACKAGES_DIR}/${pkg}"

    if [[ "$(id -u)" == "0" ]]; then
        chown -R builduser: "${_pkgdir}" "${REPO_DIR}"
        su builduser -s /bin/bash -c "cd '${_pkgdir}' && '${MAKEPKG_MINGW}' --skipchecksums --skippgpcheck --nocheck --force" \
            2>&1 || {
                echo "==> ERROR: Failed to build ${pkg}"
                exit 1
            }
    else
        cd "${_pkgdir}"
        "${MAKEPKG_MINGW}" --skipchecksums --skippgpcheck --nocheck --force \
            2>&1 || {
                echo "==> ERROR: Failed to build ${pkg}"
                exit 1
            }
    fi

    # Move packages to repo
    mv "${_pkgdir}"/*.pkg.tar.* "${REPO_DIR}/" 2>/dev/null || true

    # Install immediately so later packages can depend on them
    for pkgfile in "${REPO_DIR}"/mingw-w64-ucrt-x86_64-*"${pkg#mingw-w64-}"*.pkg.tar.*; do
        if [[ -f "${pkgfile}" ]]; then
            echo "==> Installing ${pkgfile##*/}"
            pacman --config "${PACMAN_CONF}" -U --noconfirm --overwrite='*' "${pkgfile}" || {
                echo "==> ERROR: Failed to install ${pkgfile##*/}"
                exit 1
            }
        fi
    done
}

for pkg in "${CORE_PACKAGES[@]}"; do
    build_and_install "${pkg}"
done

# Update repo database and install ALL packages in one pass.
# Individual installs above may fail on dep ordering (e.g., xz needs
# gettext-runtime which is a split package from gettext). A single
# pacman -U with all packages resolves inter-dependencies correctly.
repo-add "${REPO_DIR}/msys2-cross.db.tar.zst" "${REPO_DIR}"/*.pkg.tar.*
echo "==> Installing all built packages..."
pacman --config "${PACMAN_CONF}" -Udd --noconfirm --overwrite='*' "${REPO_DIR}"/*.pkg.tar.*

echo ""
echo "========================================="
echo "Core libraries build complete"
echo "========================================="
echo "Installed packages:"
pacman --config "${PACMAN_CONF}" -Q
