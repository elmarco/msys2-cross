# msys2-cross

Cross-compile Windows (PE) binaries on Linux using unmodified [MSYS2 MINGW-packages](https://github.com/msys2/MINGW-packages) PKGBUILDs.

Instead of maintaining a separate set of cross-compilation recipes, this project builds a container with a GCC cross-compiler and an adapted `makepkg-mingw` that automatically adjusts MSYS2 PKGBUILDs for Linux cross-compilation. The result is a `.pkg.tar.zst` package identical in layout to what MSYS2 would produce — just built on Linux.

## Quick start

```sh
# One-time setup: downloads sources, builds container, clones MINGW-packages
./msys2-cross setup

# Build a package (auto-builds missing dependencies)
./msys2-cross build libpng

# Build something with a deep dependency tree
./msys2-cross build gtk4

# Interactive shell
./msys2-cross shell
```

The `msys2-cross` script manages a bootstrap image and a working image.
Installed packages are committed to the working image, so dependency chains
survive across builds.

### Available commands

| Command | Description |
|---|---|
| `setup [--force]` | First-time setup: download sources, build container, clone MINGW-packages |
| `download <pkg> [...]` | Download sources for packages (runs on host with network) |
| `build <pkg> [...] [-k]` | Build packages with automatic dependency resolution. `-k` keeps going after failures |
| `install <pkg> [...]` | Install built packages into the sysroot |
| `deps <pkg>` | Show missing dependencies in build order |
| `shell [--network]` | Interactive shell (`--network` enables network access) |
| `run [--network] <cmd...>` | Run an arbitrary command in the container |
| `list` | List installed packages |
| `list -u` | List built but not installed packages |
| `list -a` | List all packages known to cross-compile |
| `diff` | Show package changes in working image vs bootstrap |
| `reset` | Remove working image (reset to bootstrap baseline) |
| `destroy` | Remove all images and built packages |
| `rebuild` | Rebuild the bootstrap image |
| `check-update` | Check for version drift against upstream MSYS2 |

Package names can omit the `mingw-w64-` prefix: `build libpng` works like `build mingw-w64-libpng`.

### Manual usage (without the script)

If you prefer direct `podman` commands:

```sh
# Build the container
./scripts/download-sources.sh
podman build -t msys2-cross .

# Clone MINGW-packages
git clone --filter=blob:none --sparse \
    https://github.com/msys2/MINGW-packages.git MINGW-packages
cd MINGW-packages && git sparse-checkout add mingw-w64-libpng

# Build a package
podman run --rm -v $PWD/MINGW-packages:/src msys2-cross \
    bash -c "cd /src/mingw-w64-libpng && makepkg-mingw -sf --skipchecksums --skippgpcheck --nocheck"
```

## What's in the container

| Component | Version | What it does |
|---|---|---|
| GCC | 16.1.0 | Cross-compiler (`x86_64-w64-mingw32-gcc`) |
| binutils | 2.46 | Cross-linker, assembler, etc. |
| mingw-w64 | 14.0.0 | Windows headers and CRT (UCRT) |
| Rust | 1.96.0 | Cross-compiled `std` for `x86_64-pc-windows-gnu` |
| makepkg-mingw | — | Adapted MSYS2 build driver |
| pacman | 7.x | Package manager for the MINGW sysroot |

Base libraries (libiconv, gettext, zlib, bzip2, xz, zstd, libffi, pcre2, expat) are pre-built during the container build so MSYS2 packages that implicitly depend on them work out of the box.

## How it works

MSYS2's build model is already quasi-cross-compilation: a POSIX shell drives compilers targeting native Windows. This project swaps the POSIX host from MSYS2 (Windows + Cygwin layer) to Linux:

```
MSYS2:   bash (msys-2.0.dll) → gcc.exe (Windows) → .dll/.exe
Linux:   bash (native)       → x86_64-w64-mingw32-gcc (Linux) → .dll/.exe
```

`makepkg-mingw` automatically rewrites PKGBUILDs for cross-compilation:

1. **Injects `--host` and `--build`** into autotools `configure` calls (MSYS2 PKGBUILDs omit these since build == host on Windows)
2. **Rewrites `--build=${MINGW_CHOST}`** to the Linux build triple
3. **Applies per-package patches** from `patches/` for cases the auto-rewrite can't handle

### Offline builds

All builds run in an offline container (no network access). Sources are
downloaded on the host before the build:

- Toolchain tarballs: `scripts/download-sources.sh` (run once)
- Package sources: `msys2-cross download <pkg>` (runs `makepkg --verifysource`)
- Rust crates: auto-fetched into `~/.cargo/registry/` during `download`, then bind-mounted into the container read-only

### Dependency resolution

The `build` command automatically resolves transitive dependencies, detects
circular dependencies (e.g., libwebp ↔ libtiff, libxml2 ↔ libxslt), and
handles them by building in the right order and then rebuilding the cycle
ancestor with full features:

```sh
# Resolves all deps, builds in order, handles cycles
./msys2-cross build gtk4
```

### Dummy packages

Build tools that are provided by Fedora (autotools, meson, cmake, python, etc.)
are registered as dummy pacman packages so makepkg's dependency checker is
satisfied without cross-compiling them. The list is in
`config/dummy-packages.list` (~120 entries).

## Writing a per-package patch

Some packages need manual fixes. Create `patches/<pkgbase>.sh`:

```sh
# patches/mingw-w64-foo.sh

# Example: disable a feature that requires running .exe at build time
sed -i 's/--enable-tests/--disable-tests/' PKGBUILD

# Example: replace Windows-only tool with host equivalent
sed -i 's|${MINGW_PREFIX}/bin/tool.exe|/usr/bin/tool|g' PKGBUILD

# Example: replace a dep, don't delete it (preserves array structure)
sed -i 's|"${MINGW_PACKAGE_PREFIX}-windows-only-dep"|"${MINGW_PACKAGE_PREFIX}-cc"|' PKGBUILD
```

Rules:
- Use `sed` replacements, not line deletions — deleting lines from bash arrays breaks syntax
- Patches run on a copy; the original PKGBUILD is always restored
- Patches apply before the generic auto-rewrites

### Common cross-compilation issues and fixes

| Problem | Symptom | Patch fix |
|---|---|---|
| Build runs `.exe` at build time | `cannot execute binary file` | Disable the feature or skip with `sed` |
| Calls `${MINGW_PREFIX}/bin/meson.exe` | `No such file or directory` | Replace with `/opt/msys2-cross/wrappers/mingw-meson` |
| Calls `${MINGW_PREFIX}/bin/python3` | `No such file or directory` | Replace with `/usr/bin/python3` |
| GObject introspection | `g-ir-scanner not found` | `sed -i 's/_enable_gir=yes/_enable_gir=no/'` |
| `cargo fetch` in prepare() | DNS resolution failure | `sed -i '/cargo update/d; /cargo fetch/d'` (crates from host registry) |
| GMP-style configure | `long long reliability test` | `--disable-assembly` (or install Wine) |

## RPM packaging

An RPM spec file is provided for building the toolchain as a Fedora package
(without a container). See `msys2-cross.spec` and `.copr/Makefile` for
COPR integration.

```sh
./scripts/download-sources.sh
./scripts/make-srpm-sources.sh
rpmbuild -bs msys2-cross.spec --define "_sourcedir rpmbuild-sources"
```

## Limitations

- **No `.exe` execution** without Wine. ~5-10% of packages run compiled binaries during the build (code generators, test suites). Install Wine and register `binfmt_misc` to handle these.
- **GObject introspection** requires running `g-ir-scanner` which is a Windows binary. Disabled by default in the glib2 patch.

## Project structure

```
msys2-cross                      CLI: setup, build, install, deps, shell, ...
msys2-cross.spec                 RPM spec file for non-container builds
Containerfile                    Multi-stage container build
scripts/
  download-sources.sh            Pre-download toolchain tarballs
  common.sh                      Version pins and shared variables
  00-install-host-deps.sh        Fedora packages (gcc, cmake, meson, ...)
  00-install-extra-deps.sh       Additional host dependencies
  01-build-binutils.sh           Cross-binutils
  02-build-headers.sh            MinGW-w64 headers (Windows API + CRT)
  03-build-gcc-bootstrap.sh      Bootstrap GCC (C only, no CRT)
  04-build-crt.sh                MinGW-w64 CRT (UCRT)
  05-build-winpthreads.sh        POSIX threads for Windows
  06-build-gcc-final.sh          Final GCC (C, C++, LTO)
  07-build-rust-cross.sh         Rust cross-compilation toolchain
  08-setup-pacman.sh             Package toolchain as pacman packages
  09-build-base-libs.sh          Base libraries (libiconv, gettext, ...)
  resolve-deps.sh                Dependency resolver (runs inside container)
  make-srpm-sources.sh           RPM source tarball helper
config/
  makepkg-mingw                  Build driver (auto-rewrites + patches)
  makepkg_mingw.conf             makepkg config (cross-strip, compression)
  makepkg-download.conf          makepkg config for host-side source downloads
  pacman-mingw.conf              pacman config (separate DB at /var/lib/pacman/mingw/)
  dummy-packages.list            Host-provided tools registered as dummy pacman pkgs
  cross-file.meson               Meson cross-compilation file
  native-file.meson              Meson native file
  toolchain.cmake                CMake toolchain file
  cargo-cross.toml               Cargo config (cross-linker + offline mode)
  mingw-env.sh                   Environment variables (MINGW_PREFIX, etc.)
wrappers/
  mingw-cmake                    cmake wrapper (sets cross-compiler flags)
  mingw-meson                    meson wrapper (uses cross file)
  mingw-pkg-config               pkg-config wrapper (sysroot paths)
  native-pkg-config              pkg-config wrapper for native builds
  cygpath                        No-op shim (MSYS2 path conversion)
  pacman-mingw                   pacman wrapper for the mingw DB
packages/                        Pacman PKGBUILDs for toolchain components
patches/                         Per-package cross-compilation fixes (~37 packages)
sources/                         Pre-downloaded tarballs (gitignored)
tests/                           Smoke tests (gcc, cmake, meson, autotools, rust, zlib)
logs/                            Build logs (auto-created, gitignored)
```
