# ICU cross-compilation is complex — disable for now
# Replace with a dummy to satisfy deps
sed -i 's|make |true #make |' PKGBUILD
