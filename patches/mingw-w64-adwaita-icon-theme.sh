# Disable auto-features that might require gtk-encode-symbolic-svg
sed -i 's|--auto-features=enabled|--auto-features=auto|' PKGBUILD
