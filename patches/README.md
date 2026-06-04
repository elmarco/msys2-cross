# Cross-compilation patches for MINGW-packages

Per-package shell scripts applied automatically by `makepkg-mingw` before building.

Naming convention: `<pkgbase>.sh` (e.g., `mingw-w64-zlib.sh`).

These run BEFORE the automatic sed rewrites in makepkg-mingw and operate
on the PKGBUILD via sed. They match the original upstream PKGBUILD text.
