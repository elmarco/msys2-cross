# WHY: Plain Makefile — CC not exported globally (by design); needs explicit cross-compiler and .exe handling
# Replace CC=${CC} (empty since CC is not exported in our env)
sed -i 's|CC=${CC}|CC='"${CROSS_CC}"'|g' PKGBUILD
# Add CC to package() make call (install target triggers sub-makes)
sed -i '/DESTDIR/s|make |make CC='"${CROSS_CC}"' |' PKGBUILD
# Cross-compiled tools get .exe extension, install expects without
sed -i '/DESTDIR/i\  for f in pbmtools/*.exe; do [ -f "$f" ] \&\& mv "$f" "${f%.exe}"; done' PKGBUILD
# libtool puts DLL in current dir during cross-compilation, install expects .libs/
sed -i '/make CC='"${CROSS_CC}"' prefix/a\  cp libjbig/libjbig-0.dll libjbig/.libs/' PKGBUILD
# manfiles patch creates files that already exist in newer tarballs — skip it
sed -i 's|patch.*manfiles\.all\.patch|true  # manfiles patch skipped|' PKGBUILD
