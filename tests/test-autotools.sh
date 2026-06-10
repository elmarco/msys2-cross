#!/bin/bash
set -euo pipefail

# Smoke test: cross-compile an autotools project using the toolchain.
# This exercises the most common PKGBUILD build pattern (./configure && make)
# and validates that --host/--build injection works correctly.
# Run inside the msys2-cross container.

echo "=== Test: Autotools cross-compilation ==="

WORKDIR=$(mktemp -d)
trap "rm -rf ${WORKDIR}" EXIT

source /opt/msys2-cross/config/mingw-env.sh

# Create a minimal autotools project
mkdir -p "${WORKDIR}/src"
cat > "${WORKDIR}/src/hello.c" << 'CSRC'
#include <stdio.h>

#ifdef HAVE_CONFIG_H
#include "config.h"
#endif

int main(void) {
#ifdef PACKAGE_STRING
    printf("%s\n", PACKAGE_STRING);
#else
    printf("Hello from autotools cross-compiled binary!\n");
#endif
    return 0;
}
CSRC

cat > "${WORKDIR}/src/configure.ac" << 'M4'
AC_INIT([hello-cross], [1.0])
AM_INIT_AUTOMAKE([foreign -Wall])
AC_PROG_CC
AC_CONFIG_HEADERS([config.h])
AC_CONFIG_FILES([Makefile])
AC_OUTPUT
M4

cat > "${WORKDIR}/src/Makefile.am" << 'AM'
bin_PROGRAMS = hello
hello_SOURCES = hello.c
AM

cd "${WORKDIR}/src"
autoreconf -fi

# Build using the same pattern makepkg-mingw would produce
mkdir -p "${WORKDIR}/build"
cd "${WORKDIR}/build"

"${WORKDIR}/src/configure" \
    --host="${MINGW_CHOST}" \
    --build="$(gcc -dumpmachine)" \
    --prefix="${MINGW_PREFIX}"

make -j"$(nproc)"

# Verify output
if ! file hello.exe | grep -q "PE32+"; then
    echo "FAIL: hello.exe is not a PE32+ binary"
    file hello.exe
    exit 1
fi

echo "PASS: Autotools cross-compilation produced PE32+ executable"
file hello.exe

# Verify config.h was generated with correct values
if ! grep -q 'PACKAGE_STRING.*hello-cross' config.h; then
    echo "FAIL: config.h missing expected PACKAGE_STRING"
    exit 1
fi
echo "PASS: configure generated correct config.h"

echo ""
echo "=== Autotools test passed ==="
