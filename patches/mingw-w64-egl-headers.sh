# WHY: Offline build — container has no network; git source must become a tarball
# Replace git source with tarball (container has no network for git clone)
sed -i 's|"git+https://github.com/KhronosGroup/EGL-Registry.git#commit=$_commit"|"https://github.com/KhronosGroup/EGL-Registry/archive/$_commit.tar.gz"|' PKGBUILD
# Remove pkgver() since we're using a tarball, not a git checkout
sed -i '/^pkgver()/,/^}/d' PKGBUILD
# Fix source directory name (tarball extracts to EGL-Registry-<commit>/)
sed -i 's|cd ${_realname}|cd EGL-Registry-${_commit}|' PKGBUILD
sed -i 's|"${srcdir}"/${_realname}/api|"${srcdir}"/EGL-Registry-${_commit}/api|' PKGBUILD
# Replace git makedepend with nothing
sed -i 's|makedepends=("git")|makedepends=()|' PKGBUILD
