# msys2-cross

Cross-compile Windows (PE) binaries on Linux using unmodified [MSYS2 MINGW-packages](https://github.com/msys2/MINGW-packages) PKGBUILDs.

Instead of maintaining a separate set of cross-compilation recipes, this project builds a container with a cross-compiler (GCC or Clang/LLVM) and an adapted `makepkg-mingw` that automatically adjusts MSYS2 PKGBUILDs for Linux cross-compilation. The result is a `.pkg.tar.zst` package identical in layout to what MSYS2 would produce — just built on Linux.

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

### Multi-environment support

```sh
# Default: UCRT64 (GCC, x86_64)
./msys2-cross setup
./msys2-cross build libpng

# CLANG64 (Clang/LLVM, x86_64)
./msys2-cross --msystem=CLANG64 setup
./msys2-cross --msystem=CLANG64 build libpng

# CLANGARM64 (Clang/LLVM, aarch64)
./msys2-cross --msystem=CLANGARM64 setup
./msys2-cross --msystem=CLANGARM64 build libpng
```

Each environment uses a separate container image (`msys2-cross-ucrt64`, `msys2-cross-clang64`, etc.) and can coexist.

### Shell completion

```sh
# Load Zsh completions (add to .zshrc for persistence)
eval "$(./msys2-cross complete zsh)"
```

## Commands

| Command | Description |
|---|---|
| `setup [--force]` | First-time setup: download sources, build container, clone MINGW-packages. `--force` rebuilds the bootstrap image |
| `download <pkg> [...]` | Download sources for packages (runs on host with network) |
| `build <pkg> [...] [-k] [makepkg flags]` | Build packages with automatic dependency resolution |
| `install <pkg> [...]` | Install built packages into the sysroot |
| `deps <pkg>` | Show missing dependencies in build order |
| `describe <pkg>` | Show package info: version, deps, license, build/install status |
| `shell [--network]` | Interactive shell (`--network` enables network access) |
| `run [--network] <cmd...>` | Run a command in the container |
| `list` | List installed packages |
| `list -u` | List built but not installed packages |
| `list -a` | List all packages known to MINGW-packages (marks patched ones) |
| `du` | Show container image sizes across all environments |
| `diff` | Show package changes in working image vs bootstrap |
| `reset` | Remove working image (reset to bootstrap baseline) |
| `destroy` | Remove all images and built packages |
| `rebuild` | Rebuild the bootstrap image |
| `srpm <pkg> [outdir]` | Generate an SRPM for a MINGW package |
| `mock-build [mock flags]` | Build the msys2-cross RPM via mock |
| `upstream install <pkg>` | Install pre-built packages from upstream MSYS2 repos (requires network) |
| `upstream install-dep <pkg>` | Install all build dependencies for a package from upstream MSYS2 repos |
| `upstream search <pattern>` | Search upstream MSYS2 repos for packages |
| `check-update` | Check for version drift against upstream MSYS2 |
| `complete zsh` | Output shell code to load Zsh completions |

Package names can omit the `mingw-w64-` prefix: `build libpng` works like `build mingw-w64-libpng`.

### Build flags

The `build` command passes any flag starting with `-` through to `makepkg-mingw`. By default it always adds `--skipchecksums --nodeps -f`. Useful extra flags:

```sh
./msys2-cross build libpng --nocheck      # skip test suites
./msys2-cross build libpng --noextract    # reuse previously extracted sources
./msys2-cross build libpng -k             # keep going after failures (multi-pkg)
```

### Manual usage (without the script)

If you prefer direct `podman` commands:

```sh
# Build the container
./scripts/download-sources.sh
podman build --build-arg MSYSTEM=UCRT64 -t msys2-cross-ucrt64 .

# Clone MINGW-packages
git clone --filter=blob:none --sparse \
    https://github.com/msys2/MINGW-packages.git MINGW-packages
cd MINGW-packages && git sparse-checkout add mingw-w64-libpng

# Build a package
podman run --rm -v $PWD/MINGW-packages:/src msys2-cross \
    bash -c "cd /src/mingw-w64-libpng && makepkg-mingw -sf --skipchecksums --skippgpcheck --nocheck"
```

## What's in the container

| Component | Version | Environment | What it does |
|---|---|---|---|
| GCC | 16.1.0 | UCRT64 | Cross-compiler (`x86_64-w64-mingw32-gcc`) |
| LLVM/Clang/LLD | 22.1.7 | CLANG64, CLANGARM64 | Cross-compiler + linker |
| binutils | 2.46.1 | UCRT64 | Cross-linker, assembler, etc. |
| mingw-w64 | 14.0.0 | all | Windows headers and CRT |
| Rust | 1.96.0 | all | Cross-compiled `std` for Windows target |
| makepkg-mingw | — | all | Adapted MSYS2 build driver |
| pacman | 7.x | all | Package manager for the MINGW sysroot |

Base libraries (libiconv, gettext, zlib, bzip2, xz, zstd, libffi, pcre2, expat) are pre-built during the container build so MSYS2 packages that implicitly depend on them work out of the box.

Versions are pinned in `scripts/common.sh`. Run `./msys2-cross check-update` to compare against upstream MSYS2.

## How it works

MSYS2's build model is already quasi-cross-compilation: a POSIX shell drives compilers targeting native Windows. This project swaps the POSIX host from MSYS2 (Windows + Cygwin layer) to Linux:

```
MSYS2:   bash (msys-2.0.dll) → gcc.exe (Windows) → .dll/.exe
Linux:   bash (native)       → cross-compiler (GCC or Clang) → .dll/.exe
```

`makepkg-mingw` automatically rewrites PKGBUILDs for cross-compilation:

1. Injects `--host` and `--build` into autotools `configure` calls
2. Rewrites `--build=${MINGW_CHOST}` to the Linux build triple
3. Replaces `meson.exe` / `cmake.exe` / `python3.exe` references with cross-aware wrappers
4. Strips Windows-specific `MSYS2_ARG_CONV_EXCL` settings
5. Applies per-package patches from `patches/` for cases the auto-rewrite can't handle

### Offline builds

All builds run in an offline container (no network access). Sources are downloaded on the host before the build:

- Toolchain tarballs: `scripts/download-sources.sh` (run once)
- Package sources: `msys2-cross download <pkg>` (runs `makepkg --verifysource`)
- Rust crates: auto-fetched into `~/.cargo/registry/` during `download`, then bind-mounted into the container read-only

### Dependency resolution

The `build` command automatically resolves transitive dependencies, detects
circular dependencies (e.g., libwebp ↔ libtiff), and handles them by building
in the right order and then rebuilding the cycle ancestor with full features:

```sh
# Resolves all deps, builds in order, handles cycles
./msys2-cross build gtk4
```

### Split packages

Some MSYS2 PKGBUILDs produce multiple packages from a single source (e.g.,
`mingw-w64-gettext` produces `-runtime`, `-tools`, etc.). `msys2-cross`
handles this transparently — building the source package produces all splits,
and `install` installs all of them.

### Dummy packages

Build tools that are provided by Fedora (autotools, meson, cmake, python, etc.)
are registered as dummy pacman packages so makepkg's dependency checker is
satisfied without cross-compiling them. The list is in
`config/dummy-packages.list` (~120 entries).

If a host tool like `gperf`, `ragel`, or `nasm` is missing from the dummy list, the build will try to cross-compile it. Add it to `dummy-packages.list` instead.

## Writing a per-package patch

Some packages need manual fixes for cross-compilation. Create `patches/<pkgbase>.sh`:

```sh
# patches/mingw-w64-foo.sh

# Disable a feature that requires running .exe at build time
sed -i 's/--enable-tests/--disable-tests/' PKGBUILD

# Replace Windows-only tool with host equivalent
sed -i 's|${MINGW_PREFIX}/bin/tool.exe|/usr/bin/tool|g' PKGBUILD

# Replace a dep — don't delete it (preserves array structure)
sed -i 's|"${MINGW_PACKAGE_PREFIX}-windows-only-dep"|"${MINGW_PACKAGE_PREFIX}-cc"|' PKGBUILD
```

Rules:
- Use `sed` replacements, not line deletions — deleting lines from bash arrays breaks syntax
- Patches run on a copy; the original PKGBUILD is always restored
- Patches run before the generic auto-rewrites
- PKGBUILD variables (`_realname`, `pkgver`) are **not** available when the patch runs — use literal strings in sed patterns

### Common cross-compilation issues and fixes

| Problem | Symptom | Patch fix |
|---|---|---|
| Build runs `.exe` at build time | `cannot execute binary file` | Disable the feature or skip with `sed` |
| GObject introspection | `g-ir-scanner` / `sanity_check.exe` failure | Disable introspection (see below) |
| `cargo fetch` in prepare() | DNS resolution failure | `sed -i '/cargo update/d; /cargo fetch/d'` |
| Calls `${MINGW_PREFIX}/bin/python3` | `No such file or directory` | Replace with `/usr/bin/python3` |
| GMP-style configure | `long long reliability test` | `--disable-assembly` (or install Wine) |

### Disabling GObject introspection

The most common patch. `g-ir-scanner` tries to execute compiled `.exe` files, which fails without Wine:

```sh
# Meson feature options (take enabled/disabled/auto)
sed -i 's/--auto-features=enabled/--auto-features=enabled -Dintrospection=disabled/' PKGBUILD

# Meson boolean options (take true/false — NOT enabled/disabled)
sed -i 's|--prefix="${MINGW_PREFIX}"|--prefix="${MINGW_PREFIX}" -Dintrospection=false|' PKGBUILD

# Autotools
sed -i 's/--enable-introspection/--disable-introspection/' PKGBUILD

# Also disable vapi when present (depends on GIR files)
```

## RPM packaging

### Toolchain RPM

An RPM spec file builds the cross-toolchain as Fedora packages (`msys2-cross`,
`msys2-cross-rust`, `msys2-cross-extra-deps`):

```sh
# Build via mock (recommended)
./msys2-cross mock-build

# Or manually
./scripts/download-sources.sh
./scripts/make-srpm-sources.sh
rpmbuild -bs msys2-cross.spec --define "_sourcedir rpmbuild-sources"
```

### MINGW package SRPMs

Individual MINGW packages can be built as RPMs. The `srpm` command parses a
PKGBUILD, downloads sources, and generates an RPM spec that drives
`makepkg-mingw` inside the `%build` section:

```sh
# Generate an SRPM for a single package
./msys2-cross srpm libpng

# Build in Copr
copr-cli build msys2-cross rpmbuild-mingw/mingw-w64-libpng/*.src.rpm
```

The generated specs handle split packages, git-based sources, license mapping, cross-compilation patches, and dependency mapping from MINGW to RPM names.

### Copr workflow

Build MINGW packages in dependency order. Each wave's packages can be submitted in parallel:

```sh
# 1. Build and publish toolchain
./msys2-cross mock-build
copr-cli build msys2-cross rpmbuild/msys2-cross-*.src.rpm

# 2. Build MINGW packages in dependency waves
./msys2-cross srpm libiconv
copr-cli build msys2-cross rpmbuild-mingw/mingw-w64-libiconv/*.src.rpm
# ... wait for completion, then packages that depend on it
```

See `.copr/Makefile` for automated Copr integration.

## Cross-compiling upstream projects

The sysroot can also be used to cross-compile projects directly (not via MSYS2 PKGBUILDs). Use `upstream install-dep` to pull pre-built build dependencies from MSYS2 repos, then run the project's own build system inside the container.

Example — cross-compiling QEMU for Windows on ARM:

```sh
# Install QEMU's MINGW build dependencies from upstream MSYS2
msys2-cross --msystem=CLANGARM64 upstream install-dep qemu

# Enter an interactive shell (with network for git clone, etc.)
cd /path/to/qemu
msys2-cross --msystem=CLANGARM64 shell --network

# Inside the container: configure and build
mkdir build && cd build
../configure --cross-prefix=aarch64-w64-mingw32- && ninja
```

This works for any project whose build system supports cross-compilation via a `--cross-prefix`, `--host`, toolchain file, or cross file.

## Limitations

- **No `.exe` execution** without Wine. ~5-10% of packages run compiled binaries during the build (code generators, test suites). Install Wine and register `binfmt_misc` to handle these.
- **Three environments**: UCRT64, CLANG64, and CLANGARM64. No support for MSYS or MINGW32 (32-bit).
- **GObject introspection** requires running `g-ir-scanner` which executes Windows binaries. Disabled by default via patches.

## Testing

Run smoke tests inside the container:
```sh
./msys2-cross run bash /opt/msys2-cross/tests/test-gcc.sh
./msys2-cross run bash /opt/msys2-cross/tests/test-cmake-project.sh
./msys2-cross run bash /opt/msys2-cross/tests/test-meson-project.sh
./msys2-cross run bash /opt/msys2-cross/tests/test-autotools.sh
./msys2-cross run bash /opt/msys2-cross/tests/test-rust.sh
```

## Updating toolchain versions

1. Update version vars in `scripts/common.sh`
2. Check MSYS2's PKGBUILDs for new configure flags
3. Update `pkgver` in `packages/*/PKGBUILD`
4. Re-run `scripts/download-sources.sh`
5. Rebuild: `./msys2-cross rebuild` (or `podman build --no-cache -t msys2-cross .`)

Run `./msys2-cross check-update` to see what's drifted.

## FAQ

**How do I query the pacman database inside the container?**

Use `pacman-mingw` instead of plain `pacman`. It points to the MINGW-specific database (`/var/lib/pacman/mingw/`), which is separate from Fedora's system packages:

```sh
pacman-mingw -Q                # list installed packages
pacman-mingw -Qs glib          # search installed packages
pacman-mingw -Qi mingw-w64-ucrt-x86_64-glib2   # package info
pacman-mingw -Qo /ucrt64/lib/libglib-2.0.dll.a  # find owning package
```

**Why are some wrappers prefixed (`mingw-meson`) and others suffixed (`pacman-mingw`)?**

The `mingw-` prefixed wrappers (`mingw-meson`, `mingw-cmake`, `mingw-pkg-config`) follow MSYS2's own naming convention — they wrap a build tool with cross-compilation flags. `pacman-mingw` is unique to this project (MSYS2 doesn't need a pacman wrapper) and reads as "pacman, configured for the mingw database." Different intent, inconsistent naming.

**Do I need to source anything after `./msys2-cross shell`?**

No. The container's environment already has `/opt/msys2-cross/wrappers` and `/opt/msys2-cross/config` in PATH, so all wrappers are available immediately. If you're debugging outside the normal shell entry point, you can `source /opt/msys2-cross/config/mingw-env.sh`.

**A package fails with `cannot execute binary file` — what do I do?**

The package is trying to run a compiled `.exe` during the build (code generator, test suite, etc.). Write a patch in `patches/<pkgbase>.sh` to disable that feature, or install Wine and register `binfmt_misc` to run PE binaries transparently.

**How do I add a new host tool as a dummy package?**

If a MINGW dependency is actually a build tool provided by Fedora (e.g., `gperf`, `nasm`), add it to `config/dummy-packages.list` instead of cross-compiling it. The dependency resolver will then skip it.

## Project structure

```
msys2-cross                      CLI: setup, build, install, deps, shell, ...
msys2-cross.spec                 RPM spec file for non-container builds
Containerfile                    Multi-stage container build
scripts/
  download-sources.sh            Pre-download toolchain tarballs
  common.sh                      Version pins and shared variables
  env-config.sh                 Central MSYSTEM → variable mapping
  00-install-host-deps.sh        Fedora packages (gcc, cmake, meson, ...)
  00-install-extra-deps.sh       Additional host dependencies
  01-build-binutils.sh           Cross-binutils
  02-build-headers.sh            MinGW-w64 headers (Windows API + CRT)
  03-build-gcc-bootstrap.sh      Bootstrap GCC (C only, no CRT)
  04-build-crt.sh                MinGW-w64 CRT (UCRT)
  05-build-winpthreads.sh        POSIX threads for Windows
  06-build-gcc-final.sh          Final GCC (C, C++, LTO)
  03-build-llvm.sh              LLVM/Clang/LLD (CLANG64/CLANGARM64 only)
  03-build-llvm-runtimes.sh     compiler-rt, libunwind, libc++ (CLANG64/CLANGARM64 only)
  07-build-rust-cross.sh         Rust cross-compilation toolchain
  08-setup-pacman.sh             Package toolchain as pacman packages
  09-build-base-libs.sh          Base libraries (libiconv, gettext, ...)
  lib-mingw-pkg.sh               Shared helpers (normalize_pkg, checkout_pkg, ...)
  resolve-deps.sh                Dependency resolver (runs inside container)
  make-srpm-sources.sh           RPM source tarball helper
  make-mingw-srpm.sh             SRPM generator for MINGW packages
config/
  makepkg-mingw                  Build driver (auto-rewrites + patches)
  makepkg_mingw.conf             makepkg config (cross-strip, compression)
  makepkg-download.conf          makepkg config for host-side source downloads
  pacman-mingw.conf              pacman config (separate DB at /var/lib/pacman/mingw/)
  pacman-mingw-upstream.conf.in  pacman config template with upstream MSYS2 repos
  dummy-packages.list            Host-provided tools registered as dummy pacman pkgs
  cross-file.meson.in            Meson cross-compilation template
  native-file.meson              Meson native file for build-machine tools
  toolchain.cmake.in             CMake toolchain template
  cargo-cross.toml.in            Cargo config template (cross-linker + offline mode)
  mingw-env.sh                   Environment variables (MINGW_PREFIX, etc.)
wrappers/
  mingw-cmake                    cmake wrapper (cross-flags, toolchain file)
  mingw-meson                    meson wrapper (cross file, implicit setup detection)
  mingw-pkg-config               pkg-config for cross-compiled libraries
  native-pkg-config              pkg-config for host/native build-time deps
  cygpath                        No-op shim (MSYS2 path conversion)
  pacman-mingw                   pacman wrapper for the mingw DB
completions/
  zsh/_msys2-cross               Zsh completion function
packages/                        Pacman PKGBUILDs for toolchain components
patches/                         Per-package cross-compilation fixes (~41 packages)
sources/                         Pre-downloaded tarballs (gitignored)
tests/                           Smoke tests (gcc, cmake, meson, autotools, rust, zlib)
logs/                            Build logs (auto-created, gitignored)
rpmbuild-mingw/                  Generated MINGW SRPMs (gitignored)
rpmbuild-sources/                Generated toolchain SRPM sources (gitignored)
.copr/
  Makefile                       Copr integration (builds toolchain SRPM)
```
