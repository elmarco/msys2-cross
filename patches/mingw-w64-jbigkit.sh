# Replace CC=${CC} (empty since CC is not exported in our env)
sed -i 's|CC=${CC}|CC=x86_64-w64-mingw32-gcc|g' PKGBUILD
# Add CC to package() make call (install target triggers sub-makes)
sed -i '/DESTDIR/s|make |make CC=x86_64-w64-mingw32-gcc |' PKGBUILD
# Cross-compiled tools get .exe extension, install expects without
sed -i '/DESTDIR/i\  for f in pbmtools/*.exe; do [ -f "$f" ] \&\& mv "$f" "${f%.exe}"; done' PKGBUILD
# libtool puts DLL in current dir during cross-compilation, install expects .libs/
sed -i '/make CC=x86_64-w64-mingw32-gcc prefix/a\  cp libjbig/libjbig-0.dll libjbig/.libs/' PKGBUILD
# manfiles patch creates files that already exist in newer tarballs — skip it
sed -i 's|patch.*manfiles\.all\.patch|true  # manfiles patch skipped|' PKGBUILD
