# Disable SIMD/NASM — cross-compiled nasm not available
sed -i 's|-DWITH_SIMD=ON|-DWITH_SIMD=OFF|' PKGBUILD
sed -i 's|-DREQUIRE_SIMD=ON|-DREQUIRE_SIMD=OFF|' PKGBUILD
