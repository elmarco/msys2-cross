# Break freetype/harfbuzz circular dep — build without harfbuzz first
sed -i 's/_with_harfbuzz="yes"/_with_harfbuzz="no"/' PKGBUILD
