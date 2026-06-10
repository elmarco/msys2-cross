# WHY: gtk-encode-symbolic-svg is a Windows .exe that cannot run on Linux
# Disable auto-features that might require gtk-encode-symbolic-svg
sed -i 's|--auto-features=enabled|--auto-features=auto|' PKGBUILD
# Drop gtk3 makedepend — only needed for gtk-encode-symbolic-svg which we skip
sed -i 's/"${MINGW_PACKAGE_PREFIX}-gtk3"//' PKGBUILD
