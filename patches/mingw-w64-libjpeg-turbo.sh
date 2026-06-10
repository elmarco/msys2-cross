# WHY: nasm assembler not wired into cmake cross-compilation toolchain
# Disable SIMD — nasm not available for cross-compilation.
# Flag isn't in the PKGBUILD, so inject it after the cmake call.
sed -i 's|${MINGW_PREFIX}/bin/cmake \\|${MINGW_PREFIX}/bin/cmake -DWITH_SIMD=OFF \\|' PKGBUILD
