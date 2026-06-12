#!/bin/bash
#
# Resolve missing transitive dependencies for a MINGW package.
# Runs inside the container with MINGW-packages bind-mounted at /src.
#
# Usage: resolve-deps.sh <srcpkg>
# Output: missing source package names in topological (build) order
#
set -o pipefail
# +eu is intentional: sourcing PKGBUILDs references many unset variables,
# and pacman queries use non-zero exit as control flow.
set +eu

source /opt/msys2-cross/config/mingw-env.sh
PACMAN_CONF=/opt/msys2-cross/config/pacman-mingw.conf

# Find the source directory for a package (handles split packages).
# e.g., mingw-w64-gtk-update-icon-cache → mingw-w64-gtk3
find_srcdir() {
    local pkg=$1
    if [[ -d /src/$pkg ]]; then
        echo "$pkg"
        return
    fi
    # Try suffix stripping
    for suffix in -runtime -tools -libs -devel -git; do
        local base="${pkg%${suffix}}"
        if [[ "$base" != "$pkg" && -d /src/$base ]]; then
            echo "$base"
            return
        fi
    done
    # Search pkgname= in checked-out PKGBUILDs
    local short="${pkg#mingw-w64-}"
    local match
    match=$(grep -l "pkgname=.*${short}" /src/mingw-w64-*/PKGBUILD 2>/dev/null | head -1)
    if [[ -n "$match" ]]; then
        basename "$(dirname "$match")"
        return
    fi
}

get_deps() {
    local srcpkg=$1
    local srcdir
    srcdir=$(find_srcdir "$srcpkg")
    [[ -z "$srcdir" ]] && return

    local tmpdir=$(mktemp -d)
    cp /src/$srcdir/PKGBUILD "$tmpdir/PKGBUILD"
    cd "$tmpdir"

    local _patch=/opt/msys2-cross/patches/${srcdir}.sh
    [[ -f "$_patch" ]] && source "$_patch" 2>/dev/null

    source PKGBUILD 2>/dev/null
    for dep in "${depends[@]}" "${makedepends[@]}"; do
        dep="${dep%%[><=]*}"
        if [[ "$dep" == mingw-w64-ucrt-x86_64-* ]]; then
            echo "$dep"
        fi
    done
    rm -rf "$tmpdir"
    cd /
}

declare -A visited=()
declare -A in_stack=()
declare -A rebuild_set=()
cycle_pairs=()
result=()

resolve() {
    local srcpkg=$1
    [[ -n "${visited[$srcpkg]+x}" ]] && return
    visited[$srcpkg]=1
    in_stack[$srcpkg]=1

    local deps=$(get_deps "$srcpkg" | sort -u)
    for dep in $deps; do
        pacman --config $PACMAN_CONF -Qq "$dep" &>/dev/null && continue
        local name="${dep#mingw-w64-ucrt-x86_64-}"
        local child="mingw-w64-$name"
        if [[ -n "${in_stack[$child]+x}" ]]; then
            echo "  -> circular dependency: ${srcpkg} <-> ${child} (will rebuild ${child})" >&2
            cycle_pairs+=("${srcpkg}:${child}")
            rebuild_set[$child]=1
            continue
        fi
        resolve "$child"
    done

    unset 'in_stack[$srcpkg]'

    local ipkg="mingw-w64-ucrt-x86_64-${srcpkg#mingw-w64-}"
    if ! pacman --config $PACMAN_CONF -Qq "$ipkg" &>/dev/null; then
        result+=("$srcpkg")
    fi
}

resolve "$1"

# Fix cycle ordering: DFS post-order puts the descendant (e.g. libxslt)
# before the ancestor (e.g. libxml2), but the descendant needs the ancestor
# to build. Move each descendant to right after its ancestor.
fix_cycle_ordering() {
    for pair in "${cycle_pairs[@]}"; do
        IFS=: read -r desc anc <<< "$pair"

        local i_desc=-1 i_anc=-1 i=0
        for p in "${result[@]}"; do
            [[ "$p" == "$desc" ]] && i_desc=$i
            [[ "$p" == "$anc" ]] && i_anc=$i
            i=$((i + 1))
        done

        if [[ $i_desc -ge 0 && $i_anc -ge 0 && $i_desc -lt $i_anc ]]; then
            local -a new_result=()
            for p in "${result[@]}"; do
                [[ "$p" == "$desc" ]] && continue
                new_result+=("$p")
                [[ "$p" == "$anc" ]] && new_result+=("$desc")
            done
            result=("${new_result[@]}")
        fi
    done
}
fix_cycle_ordering

for p in "${result[@]}"; do
    echo "$p"
done

if [[ ${#rebuild_set[@]} -gt 0 ]]; then
    echo "---rebuild---"
    for p in "${result[@]}"; do
        if [[ -n "${rebuild_set[$p]+x}" ]]; then
            echo "$p"
        fi
    done
fi
