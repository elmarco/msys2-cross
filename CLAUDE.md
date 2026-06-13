# MSYS2 Linux Cross-Compilation Toolchain

## Goal

Build Windows (PE) binaries from Linux/Fedora by reusing the MSYS2 MINGW-packages ecosystem. Instead of maintaining a separate set of cross-compilation recipes, this project lets you take unmodified MSYS2 PKGBUILDs and build them on a Linux host — producing the same Windows DLLs, libraries, and executables that MSYS2 would, but without needing a Windows or MSYS2 environment.

## Design principles

- **Offline builds**: The container runs with `--network=none`. All sources are pre-downloaded on the host: toolchain tarballs via `scripts/download-sources.sh`, package sources via `msys2-cross download`, and Rust crates auto-fetched into `~/.cargo/registry/` (bind-mounted read-only into the container).
- **No PKGBUILD modifications on disk**: `makepkg-mingw` works on a copy of PKGBUILD (`cp PKGBUILD PKGBUILD.orig`, restore after build). Patches must not corrupt the original. Use `sed` replacements that preserve array structure — never delete lines from the middle of bash arrays.
- **Bind-mount workflow**: Users clone MINGW-packages on the host and mount into the container. The container should never clone repos itself.

## How it works

A GCC cross-compiler targeting `x86_64-w64-mingw32` (UCRT64) is built from source on Fedora Linux, along with a Rust cross-compilation toolchain (std library compiled from source for `x86_64-pc-windows-gnu`). Base libraries (libiconv, gettext, zlib, etc.) are pre-built during the container build. Then `makepkg-mingw` is provided so MSYS2 MINGW-packages PKGBUILDs can be built on Linux without modification.

The `msys2-cross` CLI manages two container images:
- **Bootstrap image**: the toolchain + base libraries (built once, ~30-60 min)
- **Working image**: bootstrap + user-installed packages (committed after each `install`)

## Project layout

```
msys2-cross                  CLI tool: setup, build, install, deps, shell, ...
msys2-cross.spec             RPM spec file (non-container builds)
Containerfile                Multi-stage: toolchain-builder → msys2-cross
scripts/
  download-sources.sh        Pre-download all toolchain tarballs
  common.sh                  Version pins and shared variables
  00-install-host-deps.sh    Fedora packages (gcc, cmake, meson, ...)
  00-install-extra-deps.sh   Additional host dependencies
  01–06-build-*.sh           Cross-toolchain build stages (binutils → GCC)
  07-build-rust-cross.sh     Rust std for x86_64-pc-windows-gnu
  08-setup-pacman.sh         Package toolchain as pacman packages + dummy packages
  09-build-base-libs.sh      Base libraries (libiconv, gettext, zlib, ...)
  resolve-deps.sh            Dependency resolver with cycle detection (runs in container)
  make-srpm-sources.sh       RPM source tarball helper
config/
  makepkg-mingw              Build driver (auto-rewrites PKGBUILDs for cross-compilation)
  makepkg_mingw.conf         makepkg config (cross-strip, compression, PACMAN wrapper)
  makepkg-download.conf      makepkg config for host-side source downloads
  pacman-mingw.conf          pacman config (separate DB at /var/lib/pacman/mingw/)
  dummy-packages.list        ~120 host tools registered as dummy pacman packages
  cross-file.meson           Meson cross-compilation file
  native-file.meson          Meson native file
  toolchain.cmake            CMake toolchain file
  cargo-cross.toml           Cargo config (cross-linker + offline mode)
  mingw-env.sh               Environment variables (MINGW_PREFIX, MINGW_CHOST, etc.)
wrappers/                    mingw-cmake, mingw-meson, mingw-pkg-config, cygpath shim
packages/                    Pacman PKGBUILDs wrapping bootstrap artifacts
patches/                     Per-package .sh scripts for cross-compilation fixes (~37 files)
sources/                     Pre-downloaded tarballs (gitignored)
tests/                       Smoke tests (gcc, cmake, meson, autotools, rust, zlib)
logs/                        Build logs (auto-created, gitignored)
```

## Key design decisions

- **Target**: UCRT64 only (x86_64-w64-mingw32, UCRT C runtime)
- **Sysroot at /ucrt64**: Matches MSYS2's `MINGW_PREFIX` so PKGBUILDs work unmodified
- **Cross-compiler in /usr/bin/**: Standard `x86_64-w64-mingw32-gcc` naming
- **Symlinks /usr/x86_64-w64-mingw32/{include,lib} → /ucrt64/{include,lib}**: GCC sysroot discovery (can't replace the dir since binutils creates `/usr/x86_64-w64-mingw32/bin/`)
- **pacman with separate DB** (`/var/lib/pacman/mingw/`): Isolates from Fedora's dnf
- **Dummy packages for host-provided tools**: Build tools (autotools, meson, cmake, python, etc.) are provided by Fedora, not cross-compiled. Dummy pacman packages satisfy these MINGW dependencies. Listed in `config/dummy-packages.list`.
- **Cargo offline mode**: `config/cargo-cross.toml` sets `[net] offline = true`. Host cargo registry is bind-mounted read-only. Crates are auto-fetched during `msys2-cross download`.
- **Circular dependency handling**: `resolve-deps.sh` detects cycles (e.g., libwebp ↔ libtiff), builds in the right order, then rebuilds the cycle ancestor with full features. Uses `--nodeps` in makepkg to bypass dependency checking.
- **Wine is optional**: Only needed for ~5-10% of packages that run .exe at build time

## Version pins

Matched to MSYS2 MINGW-packages as of 2026-06-03 — update in `scripts/common.sh`:
- GCC 16.1.0
- binutils 2.46
- mingw-w64 14.0.0 (commit 93753750c)
- Rust 1.96.0 (std built from source, uses Fedora's rustc as bootstrap)

## Building

```sh
# One-time setup (downloads sources, builds container, clones MINGW-packages)
./msys2-cross setup

# Build a package (auto-resolves dependencies)
./msys2-cross build gtk4

# Or step by step:
./msys2-cross download libpng
./msys2-cross build libpng
./msys2-cross install libpng
```

First build takes 30-60 min (GCC compilation). The multi-stage Containerfile caches the toolchain layer.

## Testing

Run smoke tests inside the container:
```sh
./msys2-cross run bash /opt/msys2-cross/tests/test-gcc.sh
./msys2-cross run bash /opt/msys2-cross/tests/test-cmake-project.sh
./msys2-cross run bash /opt/msys2-cross/tests/test-meson-project.sh
./msys2-cross run bash /opt/msys2-cross/tests/test-autotools.sh
./msys2-cross run bash /opt/msys2-cross/tests/test-rust.sh
```

## Known issues to watch for

- **`--build` flag in PKGBUILDs**: Many MSYS2 PKGBUILDs pass `--build=${MINGW_CHOST}` to configure, which is correct on MSYS2 (where the build machine IS mingw32) but wrong on Linux cross-compilation. makepkg-mingw auto-rewrites this, but some packages (GMP) have custom configure that still fails.
- **CC must NOT be exported globally**: `config/mingw-env.sh` intentionally does NOT export CC/CXX. Autotools finds the cross-compiler via `--host=${MINGW_CHOST}`. Setting CC globally breaks `config.guess` (it uses `$CC -dumpmachine` and misidentifies the build machine).
- **pkg-config/pkgconf recursion**: Do NOT symlink pkg-config or pkgconf into /ucrt64/bin — Fedora's pkgconf finds itself via PATH and hangs in infinite recursion. Use the meson cross file's `pkgconfig =` entry instead.
- **Container UID mapping**: Running with `-v host:container:rw` may create files owned by container UIDs (100999). Use `podman unshare chown` to fix, or mount `:ro` when possible.
- **Strip tool**: `makepkg_mingw.conf` sets `STRIP=/usr/bin/x86_64-w64-mingw32-strip`. If PE binaries come out corrupted, verify this is being picked up by makepkg.
- **Fedora uses lib64**: GCC installs to `/usr/lib64/gcc/` not `/usr/lib/gcc/`. The Containerfile accounts for this.
- **Rust packages need crates**: Packages with `Cargo.lock` (e.g., librsvg) need their crates pre-fetched. `msys2-cross download` does this automatically. If building manually, run `cargo fetch` on the host first.

## Writing patches (patches/*.sh)

Per-package shell scripts that modify PKGBUILD via sed before building. Rules:
- **Never delete lines** from bash arrays — use `sed 's/pattern/replacement/'` instead
- Patches run BEFORE the generic auto-rewrites in makepkg-mingw
- Name: `<pkgbase>.sh` (e.g., `mingw-w64-glib2.sh`)
- The PKGBUILD is a temporary copy; original is always restored after build
- For Rust packages: `sed -i '/cargo update/d; /cargo fetch/d'` to skip network-dependent commands

## Adding new toolchain versions

1. Update version vars in `scripts/common.sh`
2. Check MSYS2's PKGBUILDs for new configure flags: https://github.com/msys2/MINGW-packages
3. Update `pkgver` in `packages/*/PKGBUILD`
4. Re-run `scripts/download-sources.sh`
5. Rebuild: `podman build --no-cache -t msys2-cross .`
