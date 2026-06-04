# msys2-cross

Cross-compile Windows (PE) binaries on Linux using unmodified [MSYS2 MINGW-packages](https://github.com/msys2/MINGW-packages) PKGBUILDs.

Instead of maintaining a separate set of cross-compilation recipes, this project builds a container with a GCC cross-compiler and an adapted `makepkg-mingw` that automatically adjusts MSYS2 PKGBUILDs for Linux cross-compilation. The result is a `.pkg.tar.zst` package identical in layout to what MSYS2 would produce — just built on Linux.

## Quick start

### 1. Build the container (one-time, ~30-60 min)

```sh
# Download toolchain sources
./scripts/download-sources.sh

# Build the cross-compilation container
podman build -t msys2-cross .
```

### 2. Clone MINGW-packages (one-time)

```sh
git clone --filter=blob:none --sparse \
    https://github.com/msys2/MINGW-packages.git ~/src/MINGW-packages
```

### 3. Build a package

```sh
# Checkout the package you want
cd ~/src/MINGW-packages
git sparse-checkout add mingw-w64-libpng

# Build it
podman run --rm \
    -v ~/src/MINGW-packages:/src \
    msys2-cross \
    bash -c "cd /src/mingw-w64-libpng && makepkg-mingw -sf --skipchecksums --skippgpcheck --nocheck"
```

The built `.pkg.tar.zst` package will be in the PKGBUILD directory.

### 4. Install the result into the container's sysroot

If you need the package installed for building other packages that depend on it:

```sh
podman run --rm \
    -v ~/src/MINGW-packages:/src \
    msys2-cross \
    bash -c "
        pacman --config /opt/msys2-cross/config/pacman-mingw.conf \
            -Udd --noconfirm --overwrite='*' \
            /src/mingw-w64-libpng/*.pkg.tar.zst
    "
```

For persistent state across builds, use a named container or volume instead of `--rm`.

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

## Working with persistent state

For building dependency chains (A depends on B), use a persistent container:

```sh
# Create a persistent container
podman create --name msys2-dev \
    -v ~/src/MINGW-packages:/src \
    msys2-cross sleep infinity
podman start msys2-dev

# Build and install a dependency
podman exec msys2-dev bash -c "
    cd /src/mingw-w64-libpng && makepkg-mingw -sf --skipchecksums --skippgpcheck --nocheck
    pacman --config /opt/msys2-cross/config/pacman-mingw.conf \
        -Udd --noconfirm --overwrite='*' *.pkg.tar.zst
"

# Build the package that depends on it
podman exec msys2-dev bash -c "
    cd /src/mingw-w64-something-using-libpng && makepkg-mingw -sf --skipchecksums --skippgpcheck --nocheck
"

# Clean up
podman rm -f msys2-dev
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
