#!/bin/bash
# Environment variables for the cross-compilation environment.
# Sourced by makepkg-mingw and available to users interactively.
#
# CC/CXX are NOT exported here. Autotools finds the cross-compiler via
# --host=${MINGW_CHOST} (which makes it look for ${MINGW_CHOST}-gcc).
# Setting CC globally breaks config.guess — it uses $CC -dumpmachine and
# misidentifies the build machine as mingw32.

source /opt/msys2-cross/scripts/env-config.sh

export MSYSTEM MINGW_PREFIX MINGW_CHOST MINGW_PACKAGE_PREFIX
export CC_FAMILY CROSS_CC CROSS_CXX CROSS_AR CROSS_STRIP CROSS_OBJCOPY
export CROSS_RANLIB CROSS_WINDRES CROSS_DLLTOOL
export CROSS_CFLAGS CROSS_CXXFLAGS
export CMAKE_SYSTEM_PROCESSOR MESON_CPU_FAMILY
export RUST_TARGET TARGET MSYSTEM_LOWER

export PKG_CONFIG_PATH="${MINGW_PREFIX}/lib/pkgconfig:${MINGW_PREFIX}/share/pkgconfig"
export PKG_CONFIG_SYSROOT_DIR="${MINGW_PREFIX}"
export PKG_CONFIG_LIBDIR="${MINGW_PREFIX}/lib/pkgconfig:${MINGW_PREFIX}/share/pkgconfig"

export host_alias="${MINGW_CHOST}"
export build_alias="$(gcc -dumpmachine)"

export PATH="/opt/msys2-cross/wrappers:${MINGW_PREFIX}/bin:${PATH}"

# Libtool uses host file-magic to validate target libraries before creating
# shared libs with -no-undefined.  Cross-compiled PE/COFF archives fail the
# check → libtool falls back to static-only → breaks packages expecting DLLs.
export lt_cv_deplibs_check_method=pass_all
