#!/bin/bash
set -euo pipefail

# Smoke test: verify the cross-compilation toolchain is functional.
# Checks GCC, G++, binutils, and correct CRT linkage (UCRT).
# Run inside the msys2-cross container.

echo "=== Test: Cross-compilation toolchain ==="

WORKDIR=$(mktemp -d)
trap "rm -rf ${WORKDIR}" EXIT

CROSS=x86_64-w64-mingw32

# --- Check tools exist ---
echo "--- Checking tool availability ---"
for tool in gcc g++ ld ar as objdump strip windres; do
    cmd="${CROSS}-${tool}"
    if ! command -v "$cmd" &>/dev/null; then
        echo "FAIL: ${cmd} not found in PATH"
        exit 1
    fi
done
echo "PASS: All cross-tools found"

# --- C compilation ---
echo "--- Testing C compilation ---"
cat > "${WORKDIR}/hello.c" << 'CSRC'
#include <stdio.h>
#include <stdlib.h>

int main(void) {
    printf("Hello from cross-compiled C!\n");
    void *p = malloc(42);
    free(p);
    return 0;
}
CSRC

${CROSS}-gcc -o "${WORKDIR}/hello.exe" "${WORKDIR}/hello.c"
if ! file "${WORKDIR}/hello.exe" | grep -q "PE32+"; then
    echo "FAIL: hello.exe is not a PE32+ binary"
    file "${WORKDIR}/hello.exe"
    exit 1
fi
echo "PASS: C compilation produces PE32+"

# --- C++ compilation ---
echo "--- Testing C++ compilation ---"
cat > "${WORKDIR}/hello.cpp" << 'CPPSRC'
#include <iostream>
#include <vector>
#include <string>

int main() {
    std::vector<std::string> v = {"Hello", "from", "C++!"};
    for (const auto& s : v) std::cout << s << " ";
    std::cout << std::endl;
    return 0;
}
CPPSRC

${CROSS}-g++ -o "${WORKDIR}/hello_cpp.exe" "${WORKDIR}/hello.cpp"
if ! file "${WORKDIR}/hello_cpp.exe" | grep -q "PE32+"; then
    echo "FAIL: hello_cpp.exe is not a PE32+ binary"
    exit 1
fi
echo "PASS: C++ compilation produces PE32+"

# --- UCRT linkage verification ---
echo "--- Verifying UCRT linkage ---"
imports=$(${CROSS}-objdump -p "${WORKDIR}/hello.exe" | grep "DLL Name" || true)
if echo "$imports" | grep -qi "msvcrt\.dll"; then
    echo "FAIL: Binary links against msvcrt.dll instead of UCRT"
    echo "$imports"
    exit 1
fi
echo "PASS: Binary does not link against legacy msvcrt.dll"
echo "  Linked DLLs:"
echo "$imports" | sed 's/^/    /'

# --- Static library creation ---
echo "--- Testing static library (ar) ---"
cat > "${WORKDIR}/mylib.c" << 'CSRC'
int my_add(int a, int b) { return a + b; }
CSRC

${CROSS}-gcc -c -o "${WORKDIR}/mylib.o" "${WORKDIR}/mylib.c"
${CROSS}-ar rcs "${WORKDIR}/libmy.a" "${WORKDIR}/mylib.o"

cat > "${WORKDIR}/use_lib.c" << 'CSRC'
#include <stdio.h>
extern int my_add(int, int);
int main(void) {
    printf("3 + 4 = %d\n", my_add(3, 4));
    return 0;
}
CSRC

${CROSS}-gcc -o "${WORKDIR}/use_lib.exe" "${WORKDIR}/use_lib.c" -L"${WORKDIR}" -lmy
if ! file "${WORKDIR}/use_lib.exe" | grep -q "PE32+"; then
    echo "FAIL: use_lib.exe is not a PE32+ binary"
    exit 1
fi
echo "PASS: Static library linking works"

# --- Shared library (DLL) creation ---
echo "--- Testing shared library (DLL) ---"
${CROSS}-gcc -shared -o "${WORKDIR}/mylib.dll" "${WORKDIR}/mylib.c" -Wl,--out-implib,"${WORKDIR}/libmy.dll.a"
if ! file "${WORKDIR}/mylib.dll" | grep -q "PE32+"; then
    echo "FAIL: mylib.dll is not a PE32+ binary"
    exit 1
fi
echo "PASS: Shared library (DLL) creation works"

# --- Windows resource compilation ---
echo "--- Testing resource compilation (windres) ---"
cat > "${WORKDIR}/test.rc" << 'RC'
#include <winver.h>
VS_VERSION_INFO VERSIONINFO
FILEVERSION 1,0,0,0
BEGIN
    BLOCK "StringFileInfo"
    BEGIN
        BLOCK "040904E4"
        BEGIN
            VALUE "ProductName", "Test"
        END
    END
END
RC

${CROSS}-windres "${WORKDIR}/test.rc" "${WORKDIR}/test.res"
echo "PASS: Resource compilation works"

echo ""
echo "=== All toolchain tests passed ==="
