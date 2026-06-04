# msys2-cross

Cross-compile Windows (PE) binaries on Linux using unmodified [MSYS2 MINGW-packages](https://github.com/msys2/MINGW-packages) PKGBUILDs.

Instead of maintaining a separate set of cross-compilation recipes, this project builds a container with a GCC cross-compiler and an adapted `makepkg-mingw` that automatically adjusts MSYS2 PKGBUILDs for Linux cross-compilation. The result is a `.pkg.tar.zst` package identical in layout to what MSYS2 would produce — just built on Linux.

## Quick start

```sh
# One-time setup: downloads sources, builds container, clones MINGW-packages
./msys2-cross setup

# Build a package
./msys2-cross build libpng

# Install it into the sysroot (so other packages can depend on it)
./msys2-cross install libpng

# Build something that depends on it
./msys2-cross build libwebp

# Interactive shell
./msys2-cross shell
```

The `msys2-cross` script manages a persistent container — installed packages
survive across builds, so you can build dependency chains incrementally.

### Available commands

| Command | Description |
|---|---|
| `setup` | First-time setup: download sources, build container, clone MINGW-packages |
| `build <pkg> [...]` | Build one or more packages |
| `install <pkg> [...]` | Install built packages into the sysroot |
| `shell` | Interactive shell in the build container |
| `run <cmd...>` | Run an arbitrary command in the container |
| `list` | List installed packages |
| `rebuild` | Rebuild the container image |

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

The container ships a complete cross-compilation toolchain:

| Component | Version | What it does |
|---|---|---|
| GCC | 16.1.0 | Cross-compiler (`x86_64-w64-mingw32-gcc`) |
| binutils | 2.46 | Cross-linker, assembler, etc. |
| mingw-w64 | 14.0.0 | Windows headers and CRT (UCRT) |
| makepkg-mingw | — | Adapted MSYS2 build driver |
| pacman | 7.x | Package manager for the MINGW sysroot |

Pre-built core libraries in `/ucrt64/`:
bzip2, zlib, xz, zstd, libiconv, gettext (libintl), libffi, pcre2, expat

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
| Build runs `.exe` at build time | `cannot execute binary file` or `Permission denied` | Disable the feature (`--disable-X`) or skip with `sed` |
| Calls `${MINGW_PREFIX}/bin/meson.exe` | `No such file or directory` | Replace with `/opt/msys2-cross/wrappers/mingw-meson` |
| Calls `${MINGW_PREFIX}/bin/python3` | `No such file or directory` | Replace with `/usr/bin/python3` |
| `MSYS2_ARG_CONV_EXCL` | Harmless but noisy | `sed -i '/MSYS2_ARG_CONV_EXCL/d'` |
| GObject introspection | `g-ir-scanner not found` | `sed -i 's/_enable_gir=yes/_enable_gir=no/'` |
| `noextract` with manual `tar` | `Cannot open .tar.xz` | Remove `noextract` line and `tar` command |
| GMP-style configure | `long long reliability test` | `--disable-assembly` (or install Wine) |
| `pyscript2exe.py` | `No module named 'setuptools'` | Disable the for loop: `sed -i 's/for name in .../for name in; do/'` |

## Building dependency chains

The `msys2-cross` script uses a persistent container, so installed packages
survive across builds:

```sh
# Build and install dependencies first
./msys2-cross build zlib
./msys2-cross install zlib

./msys2-cross build libpng
./msys2-cross install libpng

# Now build something that needs both
./msys2-cross build libwebp
```

To start fresh, remove the container:

```sh
podman rm -f msys2-cross-dev
```

## Limitations

- **No `.exe` execution** without Wine. ~5-10% of packages run compiled binaries during the build (code generators, test suites). Install Wine and register `binfmt_misc` to handle these.
- **GMP/MPFR/MPC** don't build — GMP's configure scans compiled objects assuming ELF format, but the cross-compiler produces PE/COFF.
- **GObject introspection** requires running `g-ir-scanner` which is a Windows binary. Disabled by default in the glib2 patch.
- **Some packages need `gettext-tools`** for building translations. The gettext build disables `libasprintf` due to a UCRT compatibility bug; the rest (libintl, tools) works.

## Project structure

```
Containerfile                    Multi-stage container build
scripts/
  download-sources.sh            Pre-download toolchain tarballs
  common.sh                      Version pins and shared variables
  00-install-host-deps.sh        Fedora packages (gcc, cmake, meson, ...)
  01-build-binutils.sh           Cross-binutils
  02-build-headers.sh            MinGW-w64 headers (Windows API + CRT)
  03-build-gcc-bootstrap.sh      Bootstrap GCC (C only, no CRT)
  04-build-crt.sh                MinGW-w64 CRT (UCRT)
  05-build-winpthreads.sh        POSIX threads for Windows
  06-build-gcc-final.sh          Final GCC (C, C++, LTO)
  07-setup-pacman.sh             Package toolchain as pacman packages
  08-build-core-libs.sh          Build core MINGW libraries
config/
  makepkg-mingw                  Build driver (auto-rewrites + patches)
  makepkg_mingw.conf             makepkg config (cross-strip, compression)
  pacman-mingw.conf              pacman config (separate DB)
  cross-file.meson               Meson cross-compilation file
  toolchain.cmake                CMake toolchain file
  mingw-env.sh                   Environment variables (MINGW_PREFIX, etc.)
wrappers/
  mingw-cmake                    cmake wrapper (sets cross-compiler flags)
  mingw-meson                    meson wrapper (uses cross file)
  mingw-pkg-config               pkg-config wrapper (sysroot paths)
  cygpath                        No-op shim (MSYS2 path conversion)
packages/                        Pacman PKGBUILDs for toolchain components
patches/                         Per-package cross-compilation fixes
sources/                         Pre-downloaded tarballs (gitignored)
```
