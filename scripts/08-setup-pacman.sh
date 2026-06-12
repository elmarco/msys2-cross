#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/common.sh"

echo "========================================="
echo "Stage 8: Set up pacman + local repo"
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

# Container overlay filesystems don't support xattrs. Wrap bsdtar so
# repo-add and pacman extraction don't fail on "Cannot restore extended
# attributes". Only inject flags in extraction (-x) mode.
install -m755 /dev/stdin /usr/local/bin/bsdtar <<'WRAPPER'
#!/bin/bash
for arg in "$@"; do
    case "$arg" in
        -x*|--extract) exec /usr/bin/bsdtar --no-xattrs --no-fflags "$@" ;;
    esac
done
exec /usr/bin/bsdtar "$@"
WRAPPER

# Create pacman directories
mkdir -p /var/lib/pacman/mingw
mkdir -p /var/cache/pacman/mingw/pkg
mkdir -p "${REPO_DIR}"

# Initialize pacman database
pacman --config "${PACMAN_CONF}" -Sy --noconfirm 2>/dev/null || true

# Make wrappers executable
chmod +x /opt/msys2-cross/wrappers/*
chmod +x /opt/msys2-cross/config/makepkg-mingw

# Use host makepkg (not makepkg-mingw) since these are packaging
# scripts, not cross-compilation builds.
MAKEPKG_CONF=/opt/msys2-cross/config/makepkg_mingw.conf

_run_makepkg() {
    local dir="$1"
    if [[ "$(id -u)" == "0" ]]; then
        chown -R builduser: "${dir}"
        su builduser -s /bin/bash -c "cd '${dir}' && makepkg --config '${MAKEPKG_CONF}' --nodeps --skipinteg --nocheck --force"
    else
        (cd "${dir}" && makepkg --config "${MAKEPKG_CONF}" --nodeps --skipinteg --nocheck --force)
    fi
    mv "${dir}"/*.pkg.tar.* "${REPO_DIR}/"
}

# Build dummy packages from the list file
DUMMY_LIST=/opt/msys2-cross/config/dummy-packages.list
_dummy_dir=$(mktemp -d)
chmod 755 "${_dummy_dir}"
while IFS= read -r name; do
    [[ -z "$name" || "$name" == \#* ]] && continue
    echo "==> Dummy: ${name}"
    mkdir -p "${_dummy_dir}/${name}"
    cat > "${_dummy_dir}/${name}/PKGBUILD" <<EOF
pkgname=${name}
pkgver=1.0
pkgrel=1
pkgdesc="Dummy — satisfied by host toolchain"
arch=('any')
license=('GPL')
package() { mkdir -p "\${pkgdir}/opt/msys2-cross"; }
EOF
    _run_makepkg "${_dummy_dir}/${name}"
done < "${DUMMY_LIST}"
rm -rf "${_dummy_dir}"

# Build real packages (toolchain repackaging, wrappers with provides=, etc.)
for pkgdir in "${PKG_DIR}"/*/; do
    echo "==> Packaging $(basename "${pkgdir%/}")..."
    _run_makepkg "${pkgdir%/}"
done

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
