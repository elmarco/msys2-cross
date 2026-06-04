# MSYS2 Linux Bootstrap — Design Spec

## Goal

Build a Linux container that cross-compiles the MSYS2 UCRT64 toolchain and provides all the tools needed to build any package from the MSYS2 MINGW-packages repository. Reuse MSYS2's build infrastructure (PKGBUILDs, makepkg-mingw, pacman) with minimal adaptation.

## Constraints

- **Target environment**: UCRT64 only (GCC, x86_64-w64-mingw32, UCRT C runtime)
- **Base distro**: Fedora (latest)
- **Bootstrap strategy**: Build everything from source (no prebuilt MSYS2 binaries)
- **Build tools**: Upstream pacman + Linux-adapted makepkg-mingw
- **Deliverable**: Tooling container with cross-toolchain, makepkg-mingw, pacman with local repo, and a minimal set of pre-built core libraries
- **Wine**: Optional (for packages that execute .exe at build time)

## Architecture Overview

The system has three layers:

1. **Fedora host layer** — native Linux build tools from Fedora repos
2. **Cross-toolchain layer** — custom-built GCC cross-compiler targeting x86_64-w64-mingw32 with UCRT, installed into the container
3. **MSYS2 compatibility layer** — adapted makepkg-mingw, pacman config, build system wrappers (cmake/meson/pkg-config), and environment variable conventions that let MSYS2 MINGW-packages PKGBUILDs run unmodified

## Filesystem Layout

```
/ucrt64/                          # MINGW_PREFIX — cross-compiled Windows sysroot
  bin/                            # Windows binaries (.exe, .dll)
  lib/                            # Import libs, static libs (.a, .dll.a)
  include/                        # Windows API + library headers
  share/                          # pkgconfig, cmake modules, data files

/opt/msys2-cross/             # Our infrastructure
  scripts/                        # Bootstrap build scripts (stages 0-6)
  config/                         # makepkg-mingw config, pacman config
  wrappers/                       # cmake/meson/pkg-config wrappers, cygpath shim
  repo/                           # Local pacman repo for built packages

/usr/x86_64-w64-mingw32 -> /ucrt64  # Symlink so GCC finds sysroot headers/libs

/usr/bin/                         # Native Linux tools (from Fedora)
  x86_64-w64-mingw32-gcc          # Cross-compiler
  x86_64-w64-mingw32-g++
  x86_64-w64-mingw32-ld
  x86_64-w64-mingw32-strip
  ...

/var/lib/pacman/mingw/            # Pacman DB (isolated from Fedora's dnf)
/var/cache/pacman/mingw/pkg/      # Package cache
```

## Environment Variables

Set by makepkg-mingw before invoking makepkg:

| Variable | Value |
|---|---|
| `MSYSTEM` | `UCRT64` |
| `MINGW_PREFIX` | `/ucrt64` |
| `MINGW_CHOST` | `x86_64-w64-mingw32` |
| `MINGW_PACKAGE_PREFIX` | `mingw-w64-ucrt-x86_64` |
| `CC` | `x86_64-w64-mingw32-gcc` |
| `CXX` | `x86_64-w64-mingw32-g++` |

## Bootstrap Chain

Six stages build the cross-toolchain from source. Each stage produces a pacman package (`.pkg.tar.zst`) added to the local repo.

### Stage 0 — Host Dependencies

Fedora packages: `gcc gcc-c++ make cmake ninja-build meson python3 autoconf automake libtool texinfo bison flex gperf patch git pacman gmp-devel mpfr-devel libmpc-devel isl-devel zlib-devel`

Optional: `wine wine-mono` (for binfmt_misc .exe execution)

### Stage 1 — Cross-Binutils

- Source: GNU binutils (version matched to MSYS2's `mingw-w64-binutils` PKGBUILD)
- Configure: `--target=x86_64-w64-mingw32 --prefix=/usr --with-sysroot=/ucrt64`
- Produces: `x86_64-w64-mingw32-{as,ld,ar,ranlib,strip,objdump,...}` in `/usr/bin/`

### Stage 2 — MinGW-w64 Headers

- Source: mingw-w64 (version matched to MSYS2's `mingw-w64-headers-git`)
- Configure: `--host=x86_64-w64-mingw32 --prefix=/ucrt64 --with-default-msvcrt=ucrt`
- Installs Windows API headers and CRT headers to `/ucrt64/include/`
- Creates symlink: `/usr/x86_64-w64-mingw32` -> `/ucrt64`

### Stage 3 — Bootstrap GCC (C only)

- Source: GCC (version matched to MSYS2's `mingw-w64-gcc`)
- Configure: `--target=x86_64-w64-mingw32 --prefix=/usr --with-sysroot=/ucrt64 --enable-languages=c --disable-threads --disable-shared`
- Minimal compiler, just enough to build the CRT

### Stage 4 — MinGW-w64 CRT

- Source: mingw-w64 (same version as Stage 2)
- Configure: `--host=x86_64-w64-mingw32 --prefix=/ucrt64 --with-default-msvcrt=ucrt`
- Built with bootstrap GCC from Stage 3
- Installs: `crt2.o`, `libmsvcrt.a`, `libucrt.a`, `libkernel32.a`, etc.

### Stage 5 — winpthreads

- Source: mingw-w64's `mingw-w64-libraries/winpthreads`
- Configure: `--host=x86_64-w64-mingw32 --prefix=/ucrt64`
- Provides POSIX threading for final GCC's libstdc++

### Stage 6 — Final GCC (C, C++, Fortran)

- Full rebuild with CRT and winpthreads available
- Configure: `--target=x86_64-w64-mingw32 --prefix=/usr --with-sysroot=/ucrt64 --enable-languages=c,c++,lto,fortran --enable-threads=posix --enable-shared`
- Produces complete cross-compiler with libgcc and libstdc++

## makepkg-mingw Adaptation

The Linux-adapted makepkg-mingw is a modified version of MSYS2's ~120-line script. Changes:

| MSYS2 behavior | Linux adaptation |
|---|---|
| Spawns MSYS2 login shell for MSYSTEM env | Directly exports env vars |
| Sources `/etc/makepkg_mingw.d/${arch}.conf` | Sources `/opt/msys2-cross/config/` |
| Relies on MSYS2's PATH mutation per MSYSTEM | Explicitly sets PATH to include cross-tools |

### makepkg_mingw.conf changes

- `CHOST=x86_64-w64-mingw32` (hardcoded for UCRT64)
- Strip commands use `x86_64-w64-mingw32-strip`
- Other strip/tidy/compression settings remain identical to MSYS2

### Build system wrappers

Installed to `/opt/msys2-cross/wrappers/` and added to PATH:

- **`mingw-cmake`**: Sets `CMAKE_SYSTEM_NAME=Windows`, cross-compiler paths, `CMAKE_FIND_ROOT_PATH=/ucrt64`
- **`mingw-meson`**: Provides a cross file with cross-tool binaries and `[host_machine] system = 'windows'`
- **`mingw-pkg-config`**: Sets `PKG_CONFIG_PATH=/ucrt64/lib/pkgconfig`, `PKG_CONFIG_SYSROOT_DIR=/ucrt64`
- **`cygpath`**: No-op shim returning input unchanged (for rare PKGBUILDs that call it)

## pacman Configuration

```ini
# /opt/msys2-cross/config/pacman-mingw.conf
[options]
RootDir     = /
DBPath      = /var/lib/pacman/mingw/
CacheDir    = /var/cache/pacman/mingw/pkg/
Architecture = any

[local]
Server = file:///opt/msys2-cross/repo
```

`RootDir=/` so packages install to their expected `/ucrt64/` paths. Separate `DBPath` isolates from any system pacman.

## Virtual Packages / Dependency Mapping

Toolchain packages provide the names that MINGW PKGBUILDs depend on:

| Package name | Provides |
|---|---|
| `mingw-w64-ucrt-x86_64-cross-gcc` | `mingw-w64-ucrt-x86_64-gcc`, `mingw-w64-ucrt-x86_64-cc` |
| `mingw-w64-ucrt-x86_64-cross-binutils` | `mingw-w64-ucrt-x86_64-binutils` |
| `mingw-w64-ucrt-x86_64-cross-crt` | `mingw-w64-ucrt-x86_64-crt-git`, `mingw-w64-ucrt-x86_64-headers-git` |
| `mingw-w64-ucrt-x86_64-cross-winpthreads` | `mingw-w64-ucrt-x86_64-winpthreads-git` |
| `mingw-w64-ucrt-x86_64-cmake` | (our wrapper, same name as MSYS2's) |
| `mingw-w64-ucrt-x86_64-meson` | (our wrapper, same name as MSYS2's) |
| `mingw-w64-ucrt-x86_64-pkgconf` | `mingw-w64-ucrt-x86_64-pkg-config` |

MSYS-layer makedepends (like `autoconf`, `python`, `perl`) are satisfied by Fedora native packages. The adapted makepkg-mingw handles this by passing `--nodeps` to makepkg for dependency resolution (since MSYS-layer packages don't exist in our pacman DB) and relying on the Fedora base image having the necessary native tools installed. A `host-deps.conf` file lists required Fedora packages so the container image includes them.

## PKGBUILD Compatibility

### Works unmodified

- **Autotools packages** (~60%): `./configure --host=${MINGW_CHOST} --prefix=${MINGW_PREFIX}` works directly
- **CMake packages** (~25%): Via our `mingw-cmake` wrapper
- **Meson packages** (~10%): Via our `mingw-meson` wrapper

### Known friction points

| Issue | Mitigation |
|---|---|
| `cygpath` calls | No-op shim provided |
| .exe execution at build time | Wine via binfmt_misc (optional) |
| MSYS-layer makedepends | Mapped to Fedora native packages |
| makepkg strip function for PE | Override strip commands in config |

## Wine / binfmt_misc

Optional. When enabled:

```bash
echo ':DOSWin:M::MZ::/usr/bin/wine:' > /proc/sys/fs/binfmt_misc/register
```

Makes `./foo.exe` transparently invoke `wine foo.exe`. Required for ~5-10% of packages that run executables during build.

## Project Repository Structure

```
msys2-cross/
  Containerfile
  scripts/
    common.sh                          # Shared variables (versions, configure flags)
    00-install-host-deps.sh
    01-build-binutils.sh
    02-build-headers.sh
    03-build-gcc-bootstrap.sh
    04-build-crt.sh
    05-build-winpthreads.sh
    06-build-gcc-final.sh
    07-setup-pacman.sh
    08-build-core-libs.sh
  config/
    makepkg-mingw                      # Linux-adapted orchestrator script
    makepkg_mingw.conf                 # makepkg config for cross-compilation
    pacman-mingw.conf                  # pacman config for MINGW sysroot
    toolchain.cmake                    # CMake toolchain file
    cross-file.meson                   # Meson cross file
    mingw-env.sh                       # Environment variable definitions
  wrappers/
    mingw-cmake
    mingw-meson
    mingw-pkg-config
    cygpath
  packages/
    mingw-w64-ucrt-x86_64-cross-binutils/PKGBUILD
    mingw-w64-ucrt-x86_64-cross-gcc/PKGBUILD
    mingw-w64-ucrt-x86_64-cross-crt/PKGBUILD
    mingw-w64-ucrt-x86_64-cross-headers/PKGBUILD
    mingw-w64-ucrt-x86_64-cross-winpthreads/PKGBUILD
    mingw-w64-ucrt-x86_64-cmake/PKGBUILD
    mingw-w64-ucrt-x86_64-meson/PKGBUILD
  tests/
    test-zlib.sh
    test-cmake-project.sh
    test-meson-project.sh
```

## Containerfile (Multi-Stage)

- **Stage 1 (`toolchain-builder`)**: Fedora base + all bootstrap stages (0-6). Builds cross-compiler. This stage is slow but cached.
- **Stage 2 (`msys2-cross`)**: Fresh Fedora base + host deps. Copies cross-toolchain artifacts from Stage 1. Installs makepkg-mingw, pacman config, wrappers. Builds core libraries. Sets environment variables.

## Usage

```bash
# Build the container
podman build -t msys2-cross .

# Build a MINGW package
podman run -v ./MINGW-packages:/src msys2-cross \
  bash -c "cd mingw-w64-zlib && makepkg-mingw -sLf"

# Interactive development
podman run -it -v ./MINGW-packages:/src msys2-cross
```

## Core Libraries (Stage 08)

Minimal set built during container creation to seed the local repo and enable building packages with common dependencies:

- `zlib` — ubiquitous compression dependency
- `bzip2` — compression
- `xz` — compression (LZMA)
- `zstd` — compression (used by pacman itself)
- `libiconv` — character encoding conversion
- `gettext` — internationalization
- `gmp`, `mpfr`, `mpc` — multi-precision math (needed if rebuilding GCC as MINGW package)
- `libffi` — foreign function interface
- `pcre2` — regular expressions
- `expat` — XML parser

## Success Criteria

1. `podman build` completes successfully
2. `x86_64-w64-mingw32-gcc` inside the container compiles a "Hello World" C program
3. `makepkg-mingw -sLf` in a `mingw-w64-zlib` directory produces a valid `.pkg.tar.zst`
4. The built zlib package installs via `pacman -U` into `/ucrt64/`
5. A cmake-based package (e.g., `mingw-w64-libpng`) builds successfully using our cmake wrapper
6. A meson-based package builds successfully using our meson wrapper
