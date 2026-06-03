#!/bin/bash
set -euo pipefail

# Smoke test: cross-compile a CMake project using our toolchain.
# Run inside the msys2-cross container.

echo "=== Test: CMake cross-compilation ==="

WORKDIR=$(mktemp -d)
trap "rm -rf ${WORKDIR}" EXIT

# Create a minimal CMake project
mkdir -p "${WORKDIR}/src"
cat > "${WORKDIR}/src/CMakeLists.txt" << 'CMAKE'
cmake_minimum_required(VERSION 3.10)
project(hello C)
add_executable(hello hello.c)
find_package(ZLIB)
if(ZLIB_FOUND)
    target_link_libraries(hello ZLIB::ZLIB)
    target_compile_definitions(hello PRIVATE HAS_ZLIB)
endif()
CMAKE

cat > "${WORKDIR}/src/hello.c" << 'CSRC'
#include <stdio.h>
#ifdef HAS_ZLIB
#include <zlib.h>
#endif

int main(void) {
    printf("Hello from cross-compiled Windows binary!\n");
#ifdef HAS_ZLIB
    printf("Linked with zlib %s\n", zlibVersion());
#endif
    return 0;
}
CSRC

mkdir -p "${WORKDIR}/build"
cd "${WORKDIR}/build"

# Build using our cmake wrapper
mingw-cmake "${WORKDIR}/src" -G Ninja
ninja

# Verify the output is a Windows PE binary
if ! file hello.exe | grep -q "PE32+"; then
    echo "FAIL: hello.exe is not a PE32+ binary"
    file hello.exe
    exit 1
fi

echo "PASS: Produced a Windows PE32+ executable"
file hello.exe
