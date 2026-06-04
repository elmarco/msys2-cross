# MSYS2 Linux Bootstrap

## Goal

Build Windows (PE) binaries from Linux/Fedora by reusing the MSYS2 MINGW-packages ecosystem. Instead of maintaining a separate set of cross-compilation recipes, this project lets you take unmodified MSYS2 PKGBUILDs and build them on a Linux host — producing the same Windows DLLs, libraries, and executables that MSYS2 would, but without needing a Windows or MSYS2 environment.

## Design principles

- **Offline builds**: The container must not require network access at runtime. All sources (toolchain tarballs, MINGW-packages) are pre-downloaded on the host and bind-mounted or copied in. Run `scripts/download-sources.sh` before `podman build`.
- **No PKGBUILD modifications on disk**: `makepkg-mingw` works on a copy of PKGBUILD (`cp PKGBUILD PKGBUILD.orig`, restore after build). Patches must not corrupt the original. Use `sed` replacements that preserve array structure — never delete lines from the middle of bash arrays.
- **Bind-mount workflow**: Users clone MINGW-packages on the host and mount into the container. The container should never clone repos itself.

## How it works

A GCC cross-compiler targeting `x86_64-w64-mingw32` (UCRT64) is built from source on Fedora Linux, then `makepkg-mingw` is provided so MSYS2 MINGW-packages PKGBUILDs can be built on Linux without modification.

## Project layout

```
scripts/          Bootstrap stages (00-08), run sequentially in the Containerfile
scripts/download-sources.sh  Pre-download all sources before container build
config/           makepkg-mingw, makepkg_mingw.conf, pacman config, cmake/meson toolchain files
wrappers/         mingw-cmake, mingw-meson, mingw-pkg-config, cygpath shim
packages/         Repackaging PKGBUILDs that wrap bootstrap artifacts as pacman packages
patches/          Per-package .sh scripts for cross-compilation fixes
sources/          Pre-downloaded tarballs (gitignored, populated by download-sources.sh)
tests/            Smoke tests (run inside the container)
Containerfile     Multi-stage: toolchain-builder → msys2-cross
```

## Key design decisions

- **Target**: UCRT64 only (x86_64-w64-mingw32, UCRT C runtime)
- **Sysroot at /ucrt64**: Matches MSYS2's `MINGW_PREFIX` so PKGBUILDs work unmodified
- **Cross-compiler in /usr/bin/**: Standard `x86_64-w64-mingw32-gcc` naming
- **Symlinks /usr/x86_64-w64-mingw32/{include,lib} → /ucrt64/{include,lib}**: GCC sysroot discovery (can't replace the dir since binutils creates `/usr/x86_64-w64-mingw32/bin/`)
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
# 1. Pre-download sources (run once)
./scripts/download-sources.sh

# 2. Build the container
podman build -t msys2-cross .

# 3. Clone MINGW-packages on host (run once)
git clone --filter=blob:none --sparse https://github.com/msys2/MINGW-packages.git ~/src/MINGW-packages
cd ~/src/MINGW-packages && git sparse-checkout add mingw-w64-glib2

# 4. Build a package (offline, bind-mounted)
podman run --rm -v ~/src/MINGW-packages:/src msys2-cross \
    bash -c "cd /src/mingw-w64-glib2 && makepkg-mingw --skipchecksums --skippgpcheck --nocheck -f"
```

First build takes 30-60 min (GCC compilation). The multi-stage Containerfile caches the toolchain layer.

## Testing

Run smoke tests inside the container:
```sh
podman run msys2-cross bash /opt/msys2-cross/tests/test-zlib.sh
podman run msys2-cross bash /opt/msys2-cross/tests/test-cmake-project.sh
podman run msys2-cross bash /opt/msys2-cross/tests/test-meson-project.sh
```

## Known issues to watch for

- **`--build` flag in PKGBUILDs**: Many MSYS2 PKGBUILDs pass `--build=${MINGW_CHOST}` to configure, which is correct on MSYS2 (where the build machine IS mingw32) but wrong on Linux cross-compilation. makepkg-mingw auto-rewrites this, but some packages (GMP) have custom configure that still fails.
- **CC must NOT be exported globally**: `config/mingw-env.sh` intentionally does NOT export CC/CXX. Autotools finds the cross-compiler via `--host=${MINGW_CHOST}`. Setting CC globally breaks `config.guess` (it uses `$CC -dumpmachine` and misidentifies the build machine).
- **pkg-config/pkgconf recursion**: Do NOT symlink pkg-config or pkgconf into /ucrt64/bin — Fedora's pkgconf finds itself via PATH and hangs in infinite recursion. Use the meson cross file's `pkgconfig =` entry instead.
- **Container UID mapping**: Running with `-v host:container:rw` may create files owned by container UIDs (100999). Use `podman unshare chown` to fix, or mount `:ro` when possible.
- **Strip tool**: `makepkg_mingw.conf` sets `STRIP=/usr/bin/x86_64-w64-mingw32-strip`. If PE binaries come out corrupted, verify this is being picked up by makepkg.
- **Fedora uses lib64**: GCC installs to `/usr/lib64/gcc/` not `/usr/lib/gcc/`. The Containerfile accounts for this.

## Writing patches (patches/*.sh)

Per-package shell scripts that modify PKGBUILD via sed before building. Rules:
- **Never delete lines** from bash arrays — use `sed 's/pattern/replacement/'` instead
- Patches run BEFORE the generic auto-rewrites in makepkg-mingw
- Name: `<pkgbase>.sh` (e.g., `mingw-w64-glib2.sh`)
- The PKGBUILD is a temporary copy; original is always restored after build

## Adding new toolchain versions

1. Update version vars in `scripts/common.sh`
2. Check MSYS2's PKGBUILDs for new configure flags: https://github.com/msys2/MINGW-packages
3. Update `pkgver` in `packages/*/PKGBUILD`
4. Re-run `scripts/download-sources.sh`
5. Rebuild: `podman build --no-cache -t msys2-cross .`
