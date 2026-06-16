#!/bin/bash
set -euo pipefail

_ENV_CONFIG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${_ENV_CONFIG_DIR}/common.sh"

: "${MSYSTEM:=UCRT64}"

case "${MSYSTEM}" in
    UCRT64)
        TARGET=x86_64-w64-mingw32
        MINGW_PREFIX=/ucrt64
        CC_FAMILY=gcc
        MINGW_PACKAGE_PREFIX=mingw-w64-ucrt-x86_64
        RUST_TARGET=x86_64-pc-windows-gnu
        CMAKE_SYSTEM_PROCESSOR=x86_64
        MESON_CPU_FAMILY=x86_64
        ;;
    CLANG64)
        TARGET=x86_64-w64-mingw32
        MINGW_PREFIX=/clang64
        CC_FAMILY=clang
        MINGW_PACKAGE_PREFIX=mingw-w64-clang-x86_64
        RUST_TARGET=x86_64-pc-windows-gnu
        CMAKE_SYSTEM_PROCESSOR=x86_64
        MESON_CPU_FAMILY=x86_64
        ;;
    CLANGARM64)
        TARGET=aarch64-w64-mingw32
        MINGW_PREFIX=/clangarm64
        CC_FAMILY=clang
        MINGW_PACKAGE_PREFIX=mingw-w64-clang-aarch64
        RUST_TARGET=aarch64-pc-windows-gnu
        CMAKE_SYSTEM_PROCESSOR=aarch64
        MESON_CPU_FAMILY=aarch64
        ;;
    *) echo "Unknown MSYSTEM: ${MSYSTEM}" >&2; exit 1 ;;
esac

MINGW_CHOST="${TARGET}"
SYSROOT="${MINGW_PREFIX}"
MSYSTEM_LOWER="${MSYSTEM,,}"

if [ "$CC_FAMILY" = "gcc" ]; then
    CROSS_CC="${TARGET}-gcc"
    CROSS_CXX="${TARGET}-g++"
    CROSS_AR="${TARGET}-ar"
    CROSS_STRIP="${TARGET}-strip"
    CROSS_OBJCOPY="${TARGET}-objcopy"
    CROSS_RANLIB="${TARGET}-ranlib"
    CROSS_WINDRES="${TARGET}-windres"
    CROSS_DLLTOOL="${TARGET}-dlltool"
else
    CROSS_CC="${TARGET}-clang"
    CROSS_CXX="${TARGET}-clang++"
    CROSS_AR="llvm-ar"
    CROSS_STRIP="llvm-strip"
    CROSS_OBJCOPY="llvm-objcopy"
    CROSS_RANLIB="llvm-ranlib"
    CROSS_WINDRES="llvm-windres"
    CROSS_DLLTOOL="llvm-dlltool"
fi

case "${CC_FAMILY}:${CMAKE_SYSTEM_PROCESSOR}" in
    gcc:x86_64)
        CROSS_CFLAGS="-march=nocona -msahf -mtune=generic -O2 -pipe"
        ;;
    clang:x86_64)
        CROSS_CFLAGS="-O2 -pipe"
        ;;
    clang:aarch64)
        CROSS_CFLAGS="-O2 -pipe"
        ;;
esac
CROSS_CXXFLAGS="${CROSS_CFLAGS}"
