#!/bin/bash
# Environment variables for the UCRT64 cross-compilation environment.
# Sourced by makepkg-mingw and available to users interactively.
#
# CC/CXX are NOT exported here. Autotools finds the cross-compiler via
# --host=${MINGW_CHOST} (which makes it look for ${MINGW_CHOST}-gcc).
# Setting CC globally breaks config.guess — it uses $CC -dumpmachine and
# misidentifies the build machine as mingw32.

export MSYSTEM=UCRT64
export MINGW_PREFIX=/ucrt64
export MINGW_CHOST=x86_64-w64-mingw32
export MINGW_PACKAGE_PREFIX=mingw-w64-ucrt-x86_64

export PKG_CONFIG_PATH="${MINGW_PREFIX}/lib/pkgconfig:${MINGW_PREFIX}/share/pkgconfig"
export PKG_CONFIG_SYSROOT_DIR="${MINGW_PREFIX}"
export PKG_CONFIG_LIBDIR="${MINGW_PREFIX}/lib/pkgconfig:${MINGW_PREFIX}/share/pkgconfig"

export PATH="/opt/msys2-cross/wrappers:${MINGW_PREFIX}/bin:${PATH}"
