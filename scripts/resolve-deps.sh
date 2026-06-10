#!/bin/bash
#
# Resolve missing transitive dependencies for a MINGW package.
# Runs inside the container with MINGW-packages bind-mounted at /src.
#
# Usage: resolve-deps.sh <srcpkg>
# Output: missing source package names in topological (build) order
#
set +eu

source /opt/msys2-cross/config/mingw-env.sh
PACMAN_CONF=/opt/msys2-cross/config/pacman-mingw.conf

get_deps() {
    local srcpkg=$1
    [[ -d /src/$srcpkg ]] || return

    local tmpdir=$(mktemp -d)
    cp /src/$srcpkg/PKGBUILD "$tmpdir/PKGBUILD"
    cd "$tmpdir"

    local _patch=/opt/msys2-cross/patches/${srcpkg}.sh
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
result=()

resolve() {
    local srcpkg=$1
    [[ -n "${visited[$srcpkg]+x}" ]] && return
    visited[$srcpkg]=1

    local deps=$(get_deps "$srcpkg" | sort -u)
    for dep in $deps; do
        pacman --config $PACMAN_CONF -Qq "$dep" &>/dev/null && continue
        local name="${dep#mingw-w64-ucrt-x86_64-}"
        local child="mingw-w64-$name"
        resolve "$child"
    done

    local ipkg="mingw-w64-ucrt-x86_64-${srcpkg#mingw-w64-}"
    if ! pacman --config $PACMAN_CONF -Qq "$ipkg" &>/dev/null; then
        result+=("$srcpkg")
    fi
}

resolve "$1"

for p in "${result[@]}"; do
    echo "$p"
done
