# Disable Python bindings — FindPython3 can't find cross-compiled python
sed -i 's|-DPYTHON=ON|-DPYTHON=OFF|g' PKGBUILD
grep -q 'DPYTHON' PKGBUILD || sed -i 's|-DCMAKE_INSTALL_PREFIX=|-DPYTHON=OFF -DCMAKE_INSTALL_PREFIX=|' PKGBUILD
# package() tries to sed PyImath.pc which doesn't exist without Python
sed -i '/PyImath\.pc/d' PKGBUILD
