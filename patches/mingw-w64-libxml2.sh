# libxml2 sub-configure doesn't inherit --build from build_alias properly
# Force cross_compiling=yes
sed -i '/^build()/a\
  export cross_compiling=yes' PKGBUILD
