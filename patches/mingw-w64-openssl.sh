# WHY: OpenSSL uses its own Configure (not autotools); CC must be explicitly set for cross-compilation
# OpenSSL's Configure doesn't use autotools. It uses CC from env.
# The PKGBUILD sets CC via the build system, but we need to ensure
# the cross-compiler is used.
sed -i '/^build()/a\
  export CC=x86_64-w64-mingw32-gcc\
  export CXX=x86_64-w64-mingw32-g++' PKGBUILD
