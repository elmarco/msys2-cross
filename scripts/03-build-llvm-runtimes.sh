#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/env-config.sh"

echo "========================================="
echo "Stage 3b: LLVM runtimes (compiler-rt, libc++)"
echo "========================================="

if [[ "${CC_FAMILY}" != "clang" ]]; then
    echo "==> Skipping LLVM runtimes (CC_FAMILY=${CC_FAMILY})"
    exit 0
fi

LLVM_SRC="${SRC_DIR}/llvm-project-${LLVM_VERSION}.src"

case "${CMAKE_SYSTEM_PROCESSOR}" in
    x86_64)  LLVM_TARGETS="X86" ;;
    aarch64) LLVM_TARGETS="AArch64" ;;
    *) echo "Unsupported arch: ${CMAKE_SYSTEM_PROCESSOR}" >&2; exit 1 ;;
esac

echo "==> Building compiler-rt builtins..."
mkdir -p "${BUILD_DIR}/compiler-rt"
cd "${BUILD_DIR}/compiler-rt"

cmake -G Ninja \
    "${LLVM_SRC}/compiler-rt" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_C_COMPILER="${CROSS_CC}" \
    -DCMAKE_CXX_COMPILER="${CROSS_CXX}" \
    -DCMAKE_AR=/usr/bin/llvm-ar \
    -DCMAKE_RANLIB=/usr/bin/llvm-ranlib \
    -DCMAKE_SYSTEM_NAME=Windows \
    -DCMAKE_SYSTEM_PROCESSOR="${CMAKE_SYSTEM_PROCESSOR}" \
    -DCMAKE_FIND_ROOT_PATH="${MINGW_PREFIX}" \
    -DCMAKE_SYSROOT="${MINGW_PREFIX}" \
    -DCOMPILER_RT_DEFAULT_TARGET_TRIPLE="${TARGET}" \
    -DCOMPILER_RT_USE_BUILTINS_LIBRARY=ON \
    -DCOMPILER_RT_BUILD_BUILTINS=ON \
    -DCOMPILER_RT_BUILD_CRT=OFF \
    -DCOMPILER_RT_BUILD_SANITIZERS=OFF \
    -DCOMPILER_RT_BUILD_XRAY=OFF \
    -DCOMPILER_RT_BUILD_LIBFUZZER=OFF \
    -DCOMPILER_RT_BUILD_PROFILE=OFF \
    -DCOMPILER_RT_BUILD_ORC=OFF

ninja -j"${JOBS}"
DESTDIR="${DESTDIR}" ninja install

echo "==> Building libunwind..."
mkdir -p "${BUILD_DIR}/libunwind"
cd "${BUILD_DIR}/libunwind"

cmake -G Ninja \
    "${LLVM_SRC}/libunwind" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_C_COMPILER="${CROSS_CC}" \
    -DCMAKE_CXX_COMPILER="${CROSS_CXX}" \
    -DCMAKE_AR=/usr/bin/llvm-ar \
    -DCMAKE_RANLIB=/usr/bin/llvm-ranlib \
    -DCMAKE_SYSTEM_NAME=Windows \
    -DCMAKE_INSTALL_PREFIX="${MINGW_PREFIX}" \
    -DCMAKE_FIND_ROOT_PATH="${MINGW_PREFIX}" \
    -DCMAKE_SYSROOT="${MINGW_PREFIX}" \
    -DLIBUNWIND_USE_COMPILER_RT=ON \
    -DLIBUNWIND_ENABLE_SHARED=ON \
    -DLIBUNWIND_ENABLE_STATIC=ON

ninja -j"${JOBS}"
DESTDIR="${DESTDIR}" ninja install

echo "==> Building libc++ and libc++abi..."
mkdir -p "${BUILD_DIR}/libcxx"
cd "${BUILD_DIR}/libcxx"

cmake -G Ninja \
    "${LLVM_SRC}/runtimes" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_C_COMPILER="${CROSS_CC}" \
    -DCMAKE_CXX_COMPILER="${CROSS_CXX}" \
    -DCMAKE_AR=/usr/bin/llvm-ar \
    -DCMAKE_RANLIB=/usr/bin/llvm-ranlib \
    -DCMAKE_SYSTEM_NAME=Windows \
    -DCMAKE_INSTALL_PREFIX="${MINGW_PREFIX}" \
    -DCMAKE_FIND_ROOT_PATH="${MINGW_PREFIX}" \
    -DCMAKE_SYSROOT="${MINGW_PREFIX}" \
    -DLLVM_ENABLE_RUNTIMES="libcxx;libcxxabi" \
    -DLIBCXX_USE_COMPILER_RT=ON \
    -DLIBCXX_ENABLE_STATIC_ABI_LIBRARY=ON \
    -DLIBCXX_CXX_ABI=libcxxabi \
    -DLIBCXX_ENABLE_SHARED=ON \
    -DLIBCXX_ENABLE_STATIC=ON \
    -DLIBCXXABI_USE_COMPILER_RT=ON \
    -DLIBCXXABI_USE_LLVM_UNWINDER=ON \
    -DLIBCXXABI_ENABLE_SHARED=ON

ninja -j"${JOBS}"
DESTDIR="${DESTDIR}" ninja install

echo "==> LLVM runtimes installed to ${DESTDIR}${MINGW_PREFIX}/"
