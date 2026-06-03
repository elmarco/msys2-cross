#!/bin/bash
set -euo pipefail

# Smoke test: cross-compile a Meson project using our toolchain.
# Run inside the msys2-cross container.

echo "=== Test: Meson cross-compilation ==="

WORKDIR=$(mktemp -d)
trap "rm -rf ${WORKDIR}" EXIT

# Create a minimal Meson project
mkdir -p "${WORKDIR}/src"
cat > "${WORKDIR}/src/meson.build" << 'MESON'
project('hello', 'c', version: '1.0')
executable('hello', 'hello.c')
MESON

cat > "${WORKDIR}/src/hello.c" << 'CSRC'
#include <stdio.h>

int main(void) {
    printf("Hello from meson cross-compiled binary!\n");
    return 0;
}
CSRC

cd "${WORKDIR}"

# Build using our meson wrapper
mingw-meson builddir src
ninja -C builddir

# Verify output
if ! file builddir/hello.exe | grep -q "PE32+"; then
    echo "FAIL: hello.exe is not a PE32+ binary"
    file builddir/hello.exe
    exit 1
fi

echo "PASS: Produced a Windows PE32+ executable via Meson"
file builddir/hello.exe
