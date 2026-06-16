# WHY: Plain Makefile uses uname for platform detection; cross-build needs explicit CC and UNAME override
# Cross-compilation: the Makefile uses UNAME=$(shell uname) to detect the
# platform. Override to MINGW so the MinGW-specific DLL rules activate.
sed -i 's|^\(\s*\)make\b|\1make CC='"${CROSS_CC}"' OFLAGS="-O2" UNAME=MINGW |' PKGBUILD
# Cross-compiled tools get .exe extension from MinGW linker but the
# Makefile install-bin target expects them without — strip .exe suffix
sed -i 's|make.*DESTDIR.*install|for f in *.exe; do [ -f "$f" ] \&\& mv "$f" "${f%.exe}"; done\n  &|' PKGBUILD
