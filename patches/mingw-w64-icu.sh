# ICU cross-compilation requires a native build first for data-processing tools.
# Insert a native build before the cross-build, and add --with-cross-build.

# Add native build step at the start of build()
sed -i '/^build()/a\
  # Phase 1: Build native ICU tools\
  mkdir -p "${srcdir}/build-native" \&\& cd "${srcdir}/build-native"\
  CC=gcc CXX=g++ ../icu/source/configure --disable-shared --enable-static --disable-tests --disable-samples\
  make -j$(nproc)' PKGBUILD

# Add --with-cross-build to the cross configure call
sed -i '/--disable-samples/a\
    --with-cross-build="${srcdir}/build-native"' PKGBUILD
