# libiconv's sub-configures (libcharset) don't inherit --host.
# Set host_alias in the environment — autoconf respects it as a
# fallback when --host isn't passed explicitly.
sed -i '/^build()/a\
  export host_alias=x86_64-w64-mingw32' PKGBUILD
