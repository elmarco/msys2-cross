# MSYS2 Linux Bootstrap

Cross-compilation bootstrap that builds a GCC toolchain targeting `x86_64-w64-mingw32` (UCRT64) on Fedora Linux, then provides `makepkg-mingw` so unmodified MSYS2 MINGW-packages PKGBUILDs can be built on Linux.

## Project layout

```
scripts/          Bootstrap stages (00-08), run sequentially in the Containerfile
config/           makepkg-mingw, makepkg_mingw.conf, pacman config, cmake/meson toolchain files
wrappers/         mingw-cmake, mingw-meson, mingw-pkg-config, cygpath shim
packages/         Repackaging PKGBUILDs that wrap bootstrap artifacts as pacman packages
tests/            Smoke tests (run inside the container)
Containerfile     Multi-stage: toolchain-builder → msys2-cross
```

## Key design decisions

- **Target**: UCRT64 only (x86_64-w64-mingw32, UCRT C runtime)
- **Sysroot at /ucrt64**: Matches MSYS2's `MINGW_PREFIX` so PKGBUILDs work unmodified
- **Cross-compiler in /usr/bin/**: Standard `x86_64-w64-mingw32-gcc` naming
- **Symlink /usr/x86_64-w64-mingw32 → /ucrt64**: GCC sysroot discovery
- **pacman with separate DB** (`/var/lib/pacman/mingw/`): Isolates from Fedora's dnf
- **--nodeps in makepkg-mingw**: Skips MSYS-layer dependency checks (autoconf, python, etc.) since those are native Fedora packages
- **Wine is optional**: Only needed for ~5-10% of packages that run .exe at build time

## Version pins

Matched to MSYS2 MINGW-packages as of 2026-06-03 — update in `scripts/common.sh`:
- GCC 16.1.0
- binutils 2.46
- mingw-w64 14.0.0 (commit 93753750c)

## Building

```sh
podman build -t msys2-cross .
```

First build takes 30-60 min (GCC compilation). The multi-stage Containerfile caches the toolchain layer.

## Testing

Run smoke tests inside the container:
```sh
podman run msys2-cross bash /opt/msys2-bootstrap/tests/test-zlib.sh
podman run msys2-cross bash /opt/msys2-bootstrap/tests/test-cmake-project.sh
podman run msys2-cross bash /opt/msys2-bootstrap/tests/test-meson-project.sh
```

## Known issues to watch for

- **PKG_CONFIG_SYSROOT_DIR**: Currently set to `/ucrt64` in mingw-pkg-config. If `.pc` files already contain full `/ucrt64/...` paths, this will double-prefix to `/ucrt64/ucrt64/...`. Set it to empty (`""`) if that happens.
- **Strip tool**: `makepkg_mingw.conf` sets `STRIP=/usr/bin/x86_64-w64-mingw32-strip`. If PE binaries come out corrupted, verify this is being picked up by makepkg.
- **MSYS-layer makedepends**: `makepkg-mingw` uses `--nodeps` to skip MSYS deps. If a package needs a tool not in Fedora's base install, add it to `scripts/00-install-host-deps.sh`.

## Adding new toolchain versions

1. Update version vars in `scripts/common.sh`
2. Check MSYS2's PKGBUILDs for new configure flags: https://github.com/msys2/MINGW-packages
3. Update `pkgver` in `packages/*/PKGBUILD`
4. Rebuild: `podman build --no-cache -t msys2-cross .`
