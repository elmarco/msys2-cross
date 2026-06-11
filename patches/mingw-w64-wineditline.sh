# WHY: Source tarball has CRLF line endings; MSYS2's patches expect LF.
# Insert a dos2unix step in prepare() before patches are applied.
sed -i '/cd.*_realname.*_realname/a\  find . -type f \\( -name "*.txt" -o -name "*.c" -o -name "*.h" \\) -exec sed -i "s/\\\\r$//" {} +' PKGBUILD

# Fix case-sensitive include: Windows is case-insensitive, Linux is not
sed -i '/cd.*_realname.*_realname/a\  sed -i "s/Strsafe\\.h/strsafe.h/" src/fn_complete.c' PKGBUILD

# Use cross-compilation cmake wrapper and allow old cmake_minimum_required
sed -i 's|^  cmake \\$|  /ucrt64/bin/cmake -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \\|' PKGBUILD
