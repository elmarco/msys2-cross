#!/bin/bash
set -euo pipefail

echo "========================================="
echo "Stage 8: Set up pacman + local repo"
echo "========================================="

# INSTALL_ROOT: prefix for all installed paths (empty = install to system root).
# Separate from DESTDIR to avoid polluting common.sh's PATH/env.
_ROOT="${INSTALL_ROOT:-}"

# --- Generate config files from templates ---
source "${_ROOT}/opt/msys2-cross/scripts/env-config.sh"

_generate_config() {
    local template="$1"
    local output="$2"
    mkdir -p "$(dirname "$output")"

    # Build meson c_args from CROSS_CFLAGS
    local meson_c_args=""
    for flag in ${CROSS_CFLAGS}; do
        [[ -n "$meson_c_args" ]] && meson_c_args+=", "
        meson_c_args+="'${flag}'"
    done

    sed \
        -e "s|@CROSS_CC@|${CROSS_CC}|g" \
        -e "s|@CROSS_CXX@|${CROSS_CXX}|g" \
        -e "s|@CROSS_AR@|${CROSS_AR}|g" \
        -e "s|@CROSS_STRIP@|${CROSS_STRIP}|g" \
        -e "s|@CROSS_RANLIB@|${CROSS_RANLIB}|g" \
        -e "s|@CROSS_WINDRES@|${CROSS_WINDRES}|g" \
        -e "s|@CROSS_DLLTOOL@|${CROSS_DLLTOOL}|g" \
        -e "s|@MINGW_PREFIX@|${MINGW_PREFIX}|g" \
        -e "s|@RUST_TARGET@|${RUST_TARGET}|g" \
        -e "s|@CMAKE_SYSTEM_PROCESSOR@|${CMAKE_SYSTEM_PROCESSOR}|g" \
        -e "s|@MESON_CPU_FAMILY@|${MESON_CPU_FAMILY}|g" \
        -e "s|@MESON_C_ARGS@|${meson_c_args}|g" \
        "$template" > "$output"
}

GENERATED_DIR="${_ROOT}/opt/msys2-cross/generated"
TEMPLATE_DIR="${_ROOT}/opt/msys2-cross/config"

_generate_config "${TEMPLATE_DIR}/cross-file.meson.in" "${GENERATED_DIR}/cross-file.meson"
_generate_config "${TEMPLATE_DIR}/toolchain.cmake.in" "${GENERATED_DIR}/toolchain.cmake"
_generate_config "${TEMPLATE_DIR}/cargo-cross.toml.in" "${GENERATED_DIR}/cargo-cross.toml"

echo "==> Generated config files in ${GENERATED_DIR}/"

REPO_DIR=${_ROOT}/opt/msys2-cross/repo
PKG_DIR=${_ROOT}/opt/msys2-cross/packages

# makepkg refuses to run as root; create a build user
if [[ "$(id -u)" == "0" ]]; then
    useradd -m builduser 2>/dev/null || true
    chown -R builduser: "${PKG_DIR}"
fi

# Container overlay filesystems don't support xattrs. Wrap bsdtar so
# repo-add and pacman extraction don't fail on "Cannot restore extended
# attributes". Only inject flags in extraction (-x) mode.
mkdir -p "${_ROOT}/usr/local/bin"
install -m755 /dev/stdin "${_ROOT}/usr/local/bin/bsdtar" <<'WRAPPER'
#!/bin/bash
for arg in "$@"; do
    case "$arg" in
        -x*|--extract) exec /usr/bin/bsdtar --no-xattrs --no-fflags "$@" ;;
    esac
done
exec /usr/bin/bsdtar "$@"
WRAPPER
export PATH="${_ROOT}/usr/local/bin:${PATH}"

# Create pacman directories
mkdir -p "${_ROOT}/var/lib/pacman/mingw"
mkdir -p "${_ROOT}/var/cache/pacman/mingw/pkg"
mkdir -p "${REPO_DIR}"

# Build a pacman config with correct paths
if [[ -n "${_ROOT}" ]]; then
    PACMAN_CONF=$(mktemp)
    trap "rm -f '${PACMAN_CONF}'" EXIT
    cat > "${PACMAN_CONF}" <<EOF
[options]
RootDir     = ${_ROOT}/
DBPath      = ${_ROOT}/var/lib/pacman/mingw/
CacheDir    = ${_ROOT}/var/cache/pacman/mingw/pkg/
LogFile     = /dev/null
Architecture = ${CMAKE_SYSTEM_PROCESSOR} auto
SigLevel = Never

[msys2-cross]
Server = file://${_ROOT}/opt/msys2-cross/repo
EOF
else
    PACMAN_CONF=/opt/msys2-cross/config/pacman-mingw.conf
fi

# Initialize pacman database
pacman --config "${PACMAN_CONF}" -Sy --noconfirm 2>/dev/null || true

# Make wrappers executable
chmod +x "${_ROOT}"/opt/msys2-cross/wrappers/*
chmod +x "${_ROOT}"/opt/msys2-cross/config/makepkg-mingw

# Minimal makepkg config for building repo packages (not cross-compilation).
# The full makepkg_mingw.conf references cross-tools that may not be installed yet.
_MAKEPKG_CONF=$(mktemp)
chmod 644 "${_MAKEPKG_CONF}"
cat > "${_MAKEPKG_CONF}" <<MKCFG
CARCH="${CMAKE_SYSTEM_PROCESSOR}"
CHOST="${MINGW_CHOST}"
PKGEXT='.pkg.tar.zst'
SRCEXT='.src.tar.zst'
COMPRESSZST=(zstd -c -z -q --threads=0 -)
BUILDENV=(!distcc !color !ccache !check !sign)
OPTIONS=(!strip !docs !libtool staticlibs emptydirs !zipman !purge !debug !lto !autodeps)
PACKAGER="msys2-cross <msys2-cross@localhost>"
MKCFG

_run_makepkg() {
    local dir="$1"
    # In RPM builds (_ROOT set), package() functions reference absolute paths
    # that only exist in the container.  The RPM handles file installation;
    # pacman packages only need correct metadata (provides, conflicts).
    if [[ -n "${_ROOT}" ]]; then
        sed -i '/^package()/,/^}/c\package() { mkdir -p "${pkgdir}/opt/msys2-cross"; }' "${dir}/PKGBUILD"
    fi
    if [[ "$(id -u)" == "0" ]]; then
        chown -R builduser: "${dir}"
        su builduser -s /bin/bash -c "cd '${dir}' && makepkg --config '${_MAKEPKG_CONF}' --nodeps --skipinteg --nocheck --force"
    else
        (cd "${dir}" && makepkg --config "${_MAKEPKG_CONF}" --nodeps --skipinteg --nocheck --force)
    fi
    mv "${dir}"/*.pkg.tar.* "${REPO_DIR}/"
    # Clean makepkg build artifacts (pkg/, src/) to avoid check-buildroot failures
    rm -rf "${dir}/pkg" "${dir}/src"
}

# Build dummy packages from the list file (section-aware)
DUMMY_LIST=${_ROOT}/opt/msys2-cross/config/dummy-packages.list
_dummy_dir=$(mktemp -d)
chmod 755 "${_dummy_dir}"

_current_section="host"
while IFS= read -r line; do
    # Detect section markers before stripping comments
    if [[ "$line" =~ ^#\ *\[([a-z]+)\] ]]; then
        _current_section="${BASH_REMATCH[1]}"
        continue
    fi

    # Skip comments and blank lines
    [[ -z "$line" || "$line" == \#* ]] && continue

    # Filter by section
    case "$_current_section" in
        host)   name="$line" ;;
        shared) name="${MINGW_PACKAGE_PREFIX}-${line}" ;;
        gcc)
            [[ "$CC_FAMILY" != "gcc" ]] && continue
            name="${MINGW_PACKAGE_PREFIX}-${line}"
            ;;
        clang)
            [[ "$CC_FAMILY" != "clang" ]] && continue
            name="${MINGW_PACKAGE_PREFIX}-${line}"
            ;;
        *) continue ;;
    esac

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
# The source PKGBUILDs use UCRT64 prefixes; transform them to match the current
# environment by substituting package prefixes and sysroot paths.
_UCRT_PKG_PREFIX="mingw-w64-ucrt-x86_64"
_pkg_tmpdir=$(mktemp -d)
chmod 755 "${_pkg_tmpdir}"

for pkgdir in "${PKG_DIR}"/*/; do
    _base=$(basename "${pkgdir%/}")

    # Skip GCC-only packages for clang builds
    if [[ "${CC_FAMILY}" = "clang" ]]; then
        case "${_base}" in
            *-cross-gcc|*-cross-binutils) echo "==> Skipping ${_base} (gcc-only)"; continue ;;
        esac
    fi

    echo "==> Packaging ${_base} (as ${MINGW_PACKAGE_PREFIX})..."
    _transformed="${_pkg_tmpdir}/${_base}"
    mkdir -p "${_transformed}"
    cp "${pkgdir}PKGBUILD" "${_transformed}/PKGBUILD"

    # Substitute UCRT64 → current environment
    sed -i \
        -e "s|${_UCRT_PKG_PREFIX}|${MINGW_PACKAGE_PREFIX}|g" \
        -e "s|/ucrt64|${MINGW_PREFIX}|g" \
        "${_transformed}/PKGBUILD"

    # For clang CRT: also exclude LLVM runtime libs (packaged separately)
    if [[ "${CC_FAMILY}" = "clang" && "${_base}" = *-cross-crt ]]; then
        sed -i '/rm -f.*libgcc/a\
    rm -f "${pkgdir}"'"${MINGW_PREFIX}"'/lib/libc++* 2>/dev/null || true\
    rm -f "${pkgdir}"'"${MINGW_PREFIX}"'/lib/libunwind* 2>/dev/null || true' \
            "${_transformed}/PKGBUILD"
    fi

    _run_makepkg "${_transformed}"
done

# For clang builds: generate cross-clang package (replaces cross-gcc + cross-binutils)
if [[ "${CC_FAMILY}" = "clang" ]]; then
    echo "==> Packaging ${MINGW_PACKAGE_PREFIX}-cross-clang..."
    _clang_dir="${_pkg_tmpdir}/${MINGW_PACKAGE_PREFIX}-cross-clang"
    mkdir -p "${_clang_dir}"
    cat > "${_clang_dir}/PKGBUILD" <<CLANGPKG
pkgname=${MINGW_PACKAGE_PREFIX}-cross-clang
pkgver=${LLVM_VERSION}
pkgrel=1
pkgdesc="LLVM/Clang cross-compiler for ${TARGET} (bootstrap)"
arch=('x86_64')
url="https://llvm.org/"
license=('Apache-2.0')
depends=(
    '${MINGW_PACKAGE_PREFIX}-cross-crt'
    '${MINGW_PACKAGE_PREFIX}-cross-winpthreads'
)
provides=(
    '${MINGW_PACKAGE_PREFIX}-clang'
    '${MINGW_PACKAGE_PREFIX}-lld'
    '${MINGW_PACKAGE_PREFIX}-llvm'
    '${MINGW_PACKAGE_PREFIX}-compiler-rt'
    '${MINGW_PACKAGE_PREFIX}-libc++'
    '${MINGW_PACKAGE_PREFIX}-libunwind'
    '${MINGW_PACKAGE_PREFIX}-gcc'
    '${MINGW_PACKAGE_PREFIX}-gcc-libs'
    '${MINGW_PACKAGE_PREFIX}-cc'
    '${MINGW_PACKAGE_PREFIX}-cc-libs'
    '${MINGW_PACKAGE_PREFIX}-binutils'
)
conflicts=(
    '${MINGW_PACKAGE_PREFIX}-clang'
    '${MINGW_PACKAGE_PREFIX}-gcc'
    '${MINGW_PACKAGE_PREFIX}-gcc-libs'
)

package() {
    mkdir -p "\${pkgdir}/usr/bin"
    # LLVM cross-tools
    for f in /usr/bin/${TARGET}-*; do
        [[ -f "\$f" ]] && install -Dm755 "\$f" "\${pkgdir}\$f"
    done
    for f in /usr/bin/llvm-* /usr/bin/clang* /usr/bin/lld* /usr/bin/ld.lld*; do
        [[ -f "\$f" ]] && install -Dm755 "\$f" "\${pkgdir}\$f"
    done

    # Clang resource dir (compiler-rt builtins)
    if [[ -d "/usr/lib/clang" ]]; then
        mkdir -p "\${pkgdir}/usr/lib"
        cp -a /usr/lib/clang "\${pkgdir}/usr/lib/"
    fi

    # LLVM runtime libs in sysroot
    mkdir -p "\${pkgdir}${MINGW_PREFIX}/"{bin,lib}
    cp -a ${MINGW_PREFIX}/lib/libc++* "\${pkgdir}${MINGW_PREFIX}/lib/" 2>/dev/null || true
    cp -a ${MINGW_PREFIX}/lib/libunwind* "\${pkgdir}${MINGW_PREFIX}/lib/" 2>/dev/null || true
    cp -a ${MINGW_PREFIX}/bin/libc++*.dll "\${pkgdir}${MINGW_PREFIX}/bin/" 2>/dev/null || true
    cp -a ${MINGW_PREFIX}/bin/libunwind*.dll "\${pkgdir}${MINGW_PREFIX}/bin/" 2>/dev/null || true
}
CLANGPKG
    _run_makepkg "${_clang_dir}"
fi

rm -rf "${_pkg_tmpdir}"

# Create repo database
echo "==> Creating repo database..."
repo-add "${REPO_DIR}/msys2-cross.db.tar.zst" "${REPO_DIR}"/*.pkg.tar.*

# Sync pacman with the new repo and install all toolchain packages.
# pacman requires root for -U; use fakeroot when running as non-root (RPM build).
_PACMAN="pacman --config ${PACMAN_CONF}"
if [[ "$(id -u)" != "0" ]]; then
    _PACMAN="fakeroot ${_PACMAN}"
fi
${_PACMAN} -Sy --noconfirm
${_PACMAN} -U --noconfirm --overwrite='*' "${REPO_DIR}"/*.pkg.tar.*

echo "==> Pacman local repo ready at ${REPO_DIR}"
echo "==> Installed toolchain packages:"
${_PACMAN} -Q
