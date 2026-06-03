#!/bin/bash
# Environment variables for the UCRT64 cross-compilation environment.
# Sourced by makepkg-mingw and available to users interactively.

export MSYSTEM=UCRT64
export MINGW_PREFIX=/ucrt64
export MINGW_CHOST=x86_64-w64-mingw32
export MINGW_PACKAGE_PREFIX=mingw-w64-ucrt-x86_64

export CC="${MINGW_CHOST}-gcc"
export CXX="${MINGW_CHOST}-g++"
export AR="${MINGW_CHOST}-ar"
export AS="${MINGW_CHOST}-as"
export LD="${MINGW_CHOST}-ld"
export NM="${MINGW_CHOST}-nm"
export OBJCOPY="${MINGW_CHOST}-objcopy"
export OBJDUMP="${MINGW_CHOST}-objdump"
export RANLIB="${MINGW_CHOST}-ranlib"
export STRIP="${MINGW_CHOST}-strip"
export WINDRES="${MINGW_CHOST}-windres"
export DLLTOOL="${MINGW_CHOST}-dlltool"
export RC="${MINGW_CHOST}-windres"

export PKG_CONFIG_PATH="${MINGW_PREFIX}/lib/pkgconfig:${MINGW_PREFIX}/share/pkgconfig"
export PKG_CONFIG_SYSROOT_DIR="${MINGW_PREFIX}"
export PKG_CONFIG_LIBDIR="${MINGW_PREFIX}/lib/pkgconfig:${MINGW_PREFIX}/share/pkgconfig"

export PATH="/opt/msys2-bootstrap/wrappers:${MINGW_PREFIX}/bin:${PATH}"
