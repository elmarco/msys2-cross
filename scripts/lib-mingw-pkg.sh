#!/bin/bash
# Shared helpers for working with MINGW-packages.
# Source this file after setting REPO_DIR to the msys2-cross project root.
#
# Provides: normalize_pkg, ensure_mingw_packages, checkout_pkg,
#           download_sources, fetch_cargo_deps, msg, warn, err
#
# Expects:  REPO_DIR set by the caller

: "${REPO_DIR:?REPO_DIR must be set before sourcing lib-mingw-pkg.sh}"

MINGW_PACKAGES_DIR="${REPO_DIR}/MINGW-packages"
DOWNLOAD_CONF="${REPO_DIR}/config/makepkg-download.conf"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BOLD='\033[1m'
NC='\033[0m'

msg()  { echo -e "${GREEN}==>${NC} ${BOLD}$1${NC}"; }
warn() { echo -e "${YELLOW}==> WARNING:${NC} ${BOLD}$1${NC}"; }
err()  { echo -e "${RED}==> ERROR:${NC} ${BOLD}$1${NC}" >&2; }

# Normalize package name: "libpng" → "mingw-w64-libpng"
normalize_pkg() {
    local pkg="$1"
    if [[ "$pkg" != mingw-w64-* ]]; then
        pkg="mingw-w64-${pkg}"
    fi
    echo "$pkg"
}

# Ensure MINGW-packages is cloned
ensure_mingw_packages() {
    if [[ ! -d "${MINGW_PACKAGES_DIR}/.git" ]]; then
        msg "Cloning MINGW-packages (sparse)..."
        git clone --filter=blob:none --sparse \
            https://github.com/msys2/MINGW-packages.git \
            "${MINGW_PACKAGES_DIR}"
    fi
}

# Sparse checkout a package. Handles split packages by:
# 1. Direct directory lookup
# 2. Suffix stripping (e.g., mingw-w64-gettext-runtime → mingw-w64-gettext)
# 3. Searching checked-out PKGBUILDs for pkgname=() that provides it
# Sets _checkout_actual to the source directory name.
checkout_pkg() {
    local pkg="$1"
    ensure_mingw_packages
    cd "${MINGW_PACKAGES_DIR}"
    if [[ ! -d "${pkg}" ]]; then
        git sparse-checkout add "${pkg}" 2>/dev/null
    fi
    if [[ ! -d "${pkg}" ]]; then
        for suffix in -runtime -tools -libs -devel -git; do
            local base="${pkg%${suffix}}"
            if [[ "$base" != "$pkg" ]]; then
                git sparse-checkout add "${base}" 2>/dev/null
                if [[ -d "${base}" ]]; then
                    _checkout_actual="${base}"
                    return 0
                fi
            fi
        done
        local short="${pkg#mingw-w64-}"
        local provider
        provider=$(grep -l "pkgname=.*${short}" "${MINGW_PACKAGES_DIR}"/mingw-w64-*/PKGBUILD 2>/dev/null \
            | head -1 | xargs -r dirname | xargs -r basename)
        if [[ -n "$provider" && -d "${MINGW_PACKAGES_DIR}/${provider}" ]]; then
            _checkout_actual="${provider}"
            return 0
        fi
        err "Package ${pkg} not found in MINGW-packages"
        return 1
    fi
    _checkout_actual="${pkg}"
}

# Download sources for a single package (runs on host, no container needed)
download_sources() {
    local pkg="$1"
    msg "Downloading sources for ${pkg}..."
    (
        export MINGW_PACKAGE_PREFIX=mingw-w64-ucrt-x86_64
        export MINGW_PREFIX=/ucrt64
        export MINGW_CHOST=x86_64-w64-mingw32
        export MSYSTEM=UCRT64
        cd "${MINGW_PACKAGES_DIR}/${pkg}"
        # Workaround: Fedora's makepkg 7.0.0 has a bug (---mirror instead of
        # --mirror) that breaks git clone for VCS sources. Pre-clone any git
        # sources so makepkg finds existing mirrors and skips the buggy clone.
        _pre_clone_git_sources
        makepkg --verifysource --skippgpcheck \
            --config "${DOWNLOAD_CONF}" --nodeps -f
    )
    fetch_cargo_deps "$pkg"
}

# Pre-clone git sources from a PKGBUILD to work around Fedora makepkg bugs.
# Must be called from the PKGBUILD directory with MINGW vars exported.
_pre_clone_git_sources() {
    local sources
    sources=$(
        mingw_arch() { :; }
        source PKGBUILD 2>/dev/null
        printf '%s\n' "${source[@]}"
    )
    while IFS= read -r src; do
        [[ "$src" == *git+* ]] || continue
        local name url
        if [[ "$src" == *::* ]]; then
            name="${src%%::*}"
            url="${src#*::}"
        else
            url="$src"
            name=$(basename "${url%%#*}" .git)
        fi
        url="${url#git+}"
        url="${url%%#*}"
        url="${url%%\?*}"
        [[ -d "$name" ]] && continue
        msg "Pre-cloning ${name} git repo..."
        git clone --mirror "$url" "$name" || warn "Failed to pre-clone ${name}"
    done <<< "$sources"
}

# Pre-fetch Rust crate dependencies so offline builds can find them.
fetch_cargo_deps() {
    local pkg="$1"
    local pkgdir="${MINGW_PACKAGES_DIR}/${pkg}"

    for tarball in "${pkgdir}"/*.tar.{xz,gz,bz2,zst}; do
        [[ -f "$tarball" ]] || continue
        bsdtar -tf "$tarball" 2>/dev/null | grep -q '^[^/]*/Cargo\.lock$' || continue

        msg "Fetching Rust crates for ${pkg}..."
        local tmpdir
        tmpdir=$(mktemp -d)
        bsdtar -xf "$tarball" -C "$tmpdir" 2>/dev/null || { rm -rf "$tmpdir"; continue; }
        local cargo_toml
        cargo_toml=$(find "$tmpdir" -maxdepth 2 -name Cargo.toml -print -quit)
        if [[ -n "$cargo_toml" ]]; then
            cargo fetch --manifest-path "$cargo_toml" --locked 2>&1 | sed 's/^/  /' || warn "cargo fetch failed (crates may be missing at build time)"
        fi
        rm -rf "$tmpdir"
        return
    done
}

# Parse a PKGBUILD and print shell variable assignments for key fields.
# Usage: eval "$(parse_pkgbuild /path/to/PKGBUILD)"
# Sets: _pkgbase, _pkgname (array as string), _pkgver, _pkgrel,
#       _pkgdesc, _url, _license, _depends, _makedepends, _source, _sha256sums
parse_pkgbuild() {
    local pkgbuild="$1"
    (
        # Provide the variables PKGBUILDs expect
        export MINGW_PACKAGE_PREFIX=mingw-w64-ucrt-x86_64
        export MINGW_PREFIX=/ucrt64
        export MINGW_CHOST=x86_64-w64-mingw32
        export MSYSTEM=UCRT64
        export CARCH=x86_64

        # Stub functions PKGBUILDs may call at top level
        mingw_arch() { :; }

        # Source in a subshell to avoid polluting the caller
        cd "$(dirname "$pkgbuild")"
        source "$(basename "$pkgbuild")" 2>/dev/null

        # Emit assignments
        echo "_pkgbase=${pkgbase:-${pkgname[0]:-unknown}}"
        echo "_pkgver=${pkgver}"
        echo "_pkgrel=${pkgrel}"
        echo "_pkgdesc=$(printf '%q' "${pkgdesc}")"
        echo "_url=$(printf '%q' "${url}")"
        echo "_license=($(printf '%q ' "${license[@]}"))"

        echo "_pkgname=($(printf '%q ' "${pkgname[@]}"))"
        echo "_depends=($(printf '%q ' "${depends[@]}"))"
        echo "_makedepends=($(printf '%q ' "${makedepends[@]}"))"
        echo "_source=($(printf '%q ' "${source[@]}"))"
        echo "_sha256sums=($(printf '%q ' "${sha256sums[@]}"))"
    )
}

# Load the dummy packages list into an associative array.
# Usage: declare -A dummies; load_dummy_packages dummies
load_dummy_packages() {
    local -n _map=$1
    local list="${REPO_DIR}/config/dummy-packages.list"
    while IFS= read -r name; do
        [[ -z "$name" || "$name" == \#* ]] && continue
        _map["$name"]=1
    done < "$list"

    # Toolchain packages from packages/ dir are also host-provided
    for dir in "${REPO_DIR}"/packages/*/; do
        [[ -d "$dir" ]] || continue
        local pname
        pname=$(basename "$dir")
        _map["$pname"]=1
        # Also add the provides
        if [[ -f "${dir}/PKGBUILD" ]]; then
            local provides
            provides=$(grep -oP "(?<=')[^']+(?=')" "${dir}/PKGBUILD" | grep "^mingw-w64-ucrt-x86_64-" || true)
            for p in $provides; do
                _map["$p"]=1
            done
        fi
    done
}
