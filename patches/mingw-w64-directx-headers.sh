# Fix case-sensitive directory name (GitHub extracts to DirectX-Headers-*, PKGBUILD expects directx-headers-*)
# Only fix cd/path references, not the source URL
sed -i '/^source=/!s|${_realname}-${pkgver}|DirectX-Headers-${pkgver}|g' PKGBUILD
