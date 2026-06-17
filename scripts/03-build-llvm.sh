#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/env-config.sh"

echo "========================================="
echo "Stage 3: LLVM/Clang/LLD ${LLVM_VERSION}"
echo "========================================="

if [[ "${CC_FAMILY}" != "clang" ]]; then
    echo "==> Skipping LLVM build (CC_FAMILY=${CC_FAMILY})"
    exit 0
fi

download_and_extract "${LLVM_URL}" "${SRC_DIR}/llvm-project-${LLVM_VERSION}.src"

case "${CMAKE_SYSTEM_PROCESSOR}" in
    x86_64)  LLVM_TARGETS="X86" ;;
    aarch64) LLVM_TARGETS="AArch64" ;;
    *) echo "Unsupported arch: ${CMAKE_SYSTEM_PROCESSOR}" >&2; exit 1 ;;
esac

mkdir -p "${BUILD_DIR}/llvm"
cd "${BUILD_DIR}/llvm"

cmake -G Ninja \
    "${SRC_DIR}/llvm-project-${LLVM_VERSION}.src/llvm" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX=/usr \
    -DLLVM_ENABLE_PROJECTS="clang;lld" \
    -DLLVM_TARGETS_TO_BUILD="${LLVM_TARGETS}" \
    -DLLVM_DEFAULT_TARGET_TRIPLE="${TARGET}" \
    -DLLVM_INSTALL_TOOLCHAIN_ONLY=ON \
    -DLLVM_ENABLE_LLD=OFF \
    -DLLVM_ENABLE_LTO=OFF \
    -DLLVM_INCLUDE_TESTS=OFF \
    -DLLVM_INCLUDE_DOCS=OFF \
    -DLLVM_INCLUDE_EXAMPLES=OFF \
    -DCLANG_DEFAULT_LINKER=lld \
    -DCLANG_DEFAULT_CXX_STDLIB=libc++ \
    -DCLANG_DEFAULT_RTLIB=compiler-rt

ninja -j"${JOBS}"
DESTDIR="${DESTDIR}" ninja install

cd "${DESTDIR}/usr/bin"
for tool in clang clang++; do
    ln -sf "${tool}" "${TARGET}-${tool}"
done
ln -sf ld.lld "${TARGET}-ld"

if [[ -f llvm-rc && ! -f llvm-windres ]]; then
    ln -sf llvm-rc llvm-windres
fi
for tool in windres dlltool; do
    if [[ -f "llvm-${tool}" && ! -f "${TARGET}-${tool}" ]]; then
        ln -sf "llvm-${tool}" "${TARGET}-${tool}"
    fi
done

echo "==> LLVM/Clang/LLD ${LLVM_VERSION} installed"
echo "==> Cross-compiler: ${CROSS_CC}"
