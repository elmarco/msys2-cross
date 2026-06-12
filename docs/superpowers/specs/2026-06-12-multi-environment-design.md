# Multi-Environment Support (UCRT64 / CLANG64 / CLANGARM64)

## Problem

msys2-cross only supports the UCRT64 environment (x86_64, GCC). MSYS2 defines several environments that differ in compiler (GCC vs LLVM/Clang) and target architecture (x86_64 vs aarch64). Users need CLANG64 and CLANGARM64 to target those configurations from Linux.

## Decision summary

| Decision | Choice |
|----------|--------|
| Parameterization | Central `env-config.sh` maps MSYSTEM to all derived variables |
| Container strategy | One image per environment (msys2-cross-ucrt64, msys2-cross-clang64, ...) |
| LLVM toolchain | Built from source inside the container |
| CLI UX | `MSYSTEM` env var + `--msystem` flag (flag overrides, defaults to UCRT64) |
| Config files | Shared base + per-env overrides. Non-shell configs generated at build time |

## MSYS2 environments

| MSYSTEM | TARGET triple | MINGW_PREFIX | CC_FAMILY | MINGW_PACKAGE_PREFIX | RUST_TARGET |
|---------|--------------|-------------|-----------|---------------------|-------------|
| UCRT64 | x86_64-w64-mingw32 | /ucrt64 | gcc | mingw-w64-ucrt-x86_64 | x86_64-pc-windows-gnu |
| CLANG64 | x86_64-w64-mingw32 | /clang64 | clang | mingw-w64-clang-x86_64 | x86_64-pc-windows-gnu |
| CLANGARM64 | aarch64-w64-mingw32 | /clangarm64 | clang | mingw-w64-clang-aarch64 | aarch64-pc-windows-gnu |

CLANG64 shares the x86_64 target triple with UCRT64 but uses LLVM/Clang. CLANGARM64 changes both the compiler and the architecture.

## Architecture

### 1. Environment configuration module

New file `scripts/env-config.sh`. Sources `common.sh` for version pins, then derives all environment-specific variables from `MSYSTEM`:

```sh
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

: "${MSYSTEM:=UCRT64}"

case "${MSYSTEM}" in
    UCRT64)
        TARGET=x86_64-w64-mingw32
        MINGW_PREFIX=/ucrt64
        CC_FAMILY=gcc
        MINGW_PACKAGE_PREFIX=mingw-w64-ucrt-x86_64
        RUST_TARGET=x86_64-pc-windows-gnu
        CMAKE_SYSTEM_PROCESSOR=x86_64
        MESON_CPU_FAMILY=x86_64
        ;;
    CLANG64)
        TARGET=x86_64-w64-mingw32
        MINGW_PREFIX=/clang64
        CC_FAMILY=clang
        MINGW_PACKAGE_PREFIX=mingw-w64-clang-x86_64
        RUST_TARGET=x86_64-pc-windows-gnu
        CMAKE_SYSTEM_PROCESSOR=x86_64
        MESON_CPU_FAMILY=x86_64
        ;;
    CLANGARM64)
        TARGET=aarch64-w64-mingw32
        MINGW_PREFIX=/clangarm64
        CC_FAMILY=clang
        MINGW_PACKAGE_PREFIX=mingw-w64-clang-aarch64
        RUST_TARGET=aarch64-pc-windows-gnu
        CMAKE_SYSTEM_PROCESSOR=aarch64
        MESON_CPU_FAMILY=aarch64
        ;;
    *) echo "Unknown MSYSTEM: ${MSYSTEM}" >&2; exit 1 ;;
esac

MINGW_CHOST="${TARGET}"
MSYSTEM_LOWER="${MSYSTEM,,}"

# Compiler and binutils tool names differ between GCC and LLVM
if [ "$CC_FAMILY" = "gcc" ]; then
    CROSS_CC="${TARGET}-gcc"
    CROSS_CXX="${TARGET}-g++"
    CROSS_AR="${TARGET}-ar"
    CROSS_STRIP="${TARGET}-strip"
    CROSS_OBJCOPY="${TARGET}-objcopy"
    CROSS_RANLIB="${TARGET}-ranlib"
    CROSS_WINDRES="${TARGET}-windres"
    CROSS_DLLTOOL="${TARGET}-dlltool"
else
    CROSS_CC="${TARGET}-clang"
    CROSS_CXX="${TARGET}-clang++"
    CROSS_AR="llvm-ar"
    CROSS_STRIP="llvm-strip"
    CROSS_OBJCOPY="llvm-objcopy"
    CROSS_RANLIB="llvm-ranlib"
    CROSS_WINDRES="llvm-windres"
    CROSS_DLLTOOL="llvm-dlltool"
fi

# Compiler flags differ by architecture and compiler family
case "${CC_FAMILY}:${CMAKE_SYSTEM_PROCESSOR}" in
    gcc:x86_64)
        CROSS_CFLAGS="-march=nocona -msahf -mtune=generic -O2 -pipe"
        ;;
    clang:x86_64)
        CROSS_CFLAGS="-O2 -pipe"
        ;;
    clang:aarch64)
        CROSS_CFLAGS="-O2 -pipe"
        ;;
esac
CROSS_CXXFLAGS="${CROSS_CFLAGS}"
```

`config/mingw-env.sh` becomes a thin re-export of env-config.sh for use inside the container (where scripts live at `/opt/msys2-cross/`).

`scripts/common.sh` keeps only version pins and download URLs (environment-independent). Gains `LLVM_VERSION` alongside existing `GCC_VERSION`.

### 2. Build scripts

Build scripts source `env-config.sh` and use `${TARGET}`, `${CROSS_CC}`, `${MINGW_PREFIX}`, etc. instead of hardcoded values.

**GCC path (CC_FAMILY=gcc) — build order:**
1. `01-build-binutils.sh` — GNU binutils + ld
2. `02-build-headers.sh` — mingw-w64 headers
3. `03-build-gcc-bootstrap.sh` — bootstrap GCC (C only, no CRT)
4. `04-build-crt.sh` — mingw-w64 CRT (uses bootstrap GCC)
5. `05-build-winpthreads.sh` — POSIX threads (uses bootstrap GCC)
6. `06-build-gcc-final.sh` — final GCC (C, C++, LTO, links against CRT)

**Clang path (CC_FAMILY=clang) — build order:**
1. `03-build-llvm.sh` — LLVM, Clang, LLD (self-contained, no CRT needed)
2. `02-build-headers.sh` — mingw-w64 headers
3. `04-build-crt.sh` — mingw-w64 CRT (uses freshly-built clang)
4. `05-build-winpthreads.sh` — POSIX threads (uses clang)
5. `03-build-llvm-runtimes.sh` — compiler-rt, libunwind, libc++, libc++abi (need CRT)

Note: the Clang path requires **two LLVM build steps**. The first builds the compiler itself. The second builds the runtime libraries (compiler-rt builtins, libunwind, libc++, libc++abi) which depend on CRT and headers being available. This mirrors the [mstorsjo/llvm-mingw](https://github.com/mstorsjo/llvm-mingw) build process.

**Shared (both paths, run after the compiler-specific steps):**
- `07-build-rust-cross.sh` — Rust std for `${RUST_TARGET}`
- `08-setup-pacman.sh` — pacman DB + dummy packages + config generation
- `09-build-base-libs.sh` — base libraries

### 3. Config files

**Shell-based (use variables directly, no generation needed):**
- `config/mingw-env.sh` — sources env-config.sh, exports MSYSTEM/MINGW_PREFIX/etc.
- `config/makepkg_mingw.conf` — `CHOST`, `STRIP`, `OBJCOPY`, `CFLAGS` come from env vars. Architecture-specific flags (`-march=nocona` etc.) are set by env-config.sh's `CROSS_CFLAGS`.

**Dummy packages (`config/dummy-packages.list`):**

The list stores base names only (e.g., `cmake`, `python`). The prefix `${MINGW_PACKAGE_PREFIX}-` is prepended by `08-setup-pacman.sh` at package creation time.

However, some packages are environment-specific:
- GCC-only: `gcc-libgfortran`, `gcc-libs`
- Clang-only: `clang`, `clang-libs`, `lld`, `llvm`, `compiler-rt`
- Shared: `cmake`, `meson`, `python`, `autotools`, etc.

The list uses section markers to handle this:

```
# [shared]
cmake
meson
python
...
# [gcc]
gcc-libgfortran
gcc-libs
# [clang]
clang
clang-libs
lld
compiler-rt
```

`08-setup-pacman.sh` reads the file and includes `[shared]` + the section matching `${CC_FAMILY}`.

**Generated at container build time (non-shell formats):**

Templates in `config/` with `@VARIABLE@` placeholders. A generation step in `08-setup-pacman.sh` uses `sed` to expand them.

- `config/cross-file.meson.in` → `/opt/msys2-cross/generated/cross-file.meson`
- `config/toolchain.cmake.in` → `/opt/msys2-cross/generated/toolchain.cmake`
- `config/cargo-cross.toml.in` → `/opt/msys2-cross/generated/cargo-cross.toml`

Generated files go to `/opt/msys2-cross/generated/` inside the image, which is NOT bind-mounted from the host. Wrappers read from there.

**Wrappers (shell scripts, parameterized):**
- `mingw-cmake` — reads `${CROSS_CC}`, `${CROSS_CXX}`, `${MINGW_PREFIX}`, `${CMAKE_SYSTEM_PROCESSOR}` from mingw-env.sh. References generated toolchain.cmake.
- `mingw-meson` — references generated cross-file.meson at `/opt/msys2-cross/generated/cross-file.meson`.
- `mingw-pkg-config` — uses `${MINGW_PREFIX}` for sysroot paths.

**Patches:**
The 4 patches that hardcode the cross triple (`mingw-w64-giflib.sh`, `mingw-w64-openssl.sh`, `mingw-w64-jbigkit.sh`, `mingw-w64-wineditline.sh`) change to use `${MINGW_CHOST}` and `${MINGW_PREFIX}`, which are available in the environment when patches run.

### 4. Containerfile

Single Containerfile, parameterized by `ARG MSYSTEM` plus derived ARGs passed by the CLI:

```dockerfile
ARG MSYSTEM=UCRT64
ARG MINGW_PREFIX=/ucrt64
ARG TARGET=x86_64-w64-mingw32

# Stage 1: Build toolchain from source
FROM fedora:latest AS toolchain-builder
ARG MSYSTEM
COPY scripts/ /opt/msys2-cross/scripts/
COPY sources/ /build/sources/
RUN export MSYSTEM=${MSYSTEM} \
    && source /opt/msys2-cross/scripts/env-config.sh \
    && if [ "$CC_FAMILY" = "gcc" ]; then \
           bash /opt/msys2-cross/scripts/01-build-binutils.sh \
        && bash /opt/msys2-cross/scripts/02-build-headers.sh \
        && bash /opt/msys2-cross/scripts/03-build-gcc-bootstrap.sh \
        && bash /opt/msys2-cross/scripts/04-build-crt.sh \
        && bash /opt/msys2-cross/scripts/05-build-winpthreads.sh \
        && bash /opt/msys2-cross/scripts/06-build-gcc-final.sh; \
       else \
           bash /opt/msys2-cross/scripts/03-build-llvm.sh \
        && bash /opt/msys2-cross/scripts/02-build-headers.sh \
        && bash /opt/msys2-cross/scripts/04-build-crt.sh \
        && bash /opt/msys2-cross/scripts/05-build-winpthreads.sh \
        && bash /opt/msys2-cross/scripts/03-build-llvm-runtimes.sh; \
       fi \
    && bash /opt/msys2-cross/scripts/07-build-rust-cross.sh \
    && rm -rf /build

# Stage 2: Final cross-compilation environment
FROM fedora:latest AS msys2-cross
ARG MSYSTEM
ARG MINGW_PREFIX
ARG TARGET

COPY scripts/common.sh scripts/env-config.sh scripts/00-install-host-deps.sh scripts/00-install-extra-deps.sh /opt/msys2-cross/scripts/
RUN bash /opt/msys2-cross/scripts/00-install-host-deps.sh
RUN bash /opt/msys2-cross/scripts/00-install-extra-deps.sh

# Copy sysroot and cross-compiler from builder
# MINGW_PREFIX and TARGET are passed as ARGs so COPY can expand them
COPY --from=toolchain-builder ${MINGW_PREFIX} ${MINGW_PREFIX}
COPY --from=toolchain-builder /usr/bin/${TARGET}-* /usr/bin/
COPY --from=toolchain-builder /usr/${TARGET} /usr/${TARGET}
# ... rest of setup
```

The key insight: Dockerfile `ARG` values ARE expanded in `COPY` paths. The `msys2-cross` CLI computes `MINGW_PREFIX` and `TARGET` from `MSYSTEM` and passes all three as `--build-arg`. This avoids needing shell logic between `ARG` and `COPY`.

For the GCC-specific paths (`/usr/lib64/gcc/${TARGET}`, `/usr/libexec/gcc/${TARGET}`), the Containerfile uses a conditional `RUN` step that only copies them when `CC_FAMILY=gcc`.

Built with:
```sh
podman build \
    --build-arg MSYSTEM=CLANG64 \
    --build-arg MINGW_PREFIX=/clang64 \
    --build-arg TARGET=x86_64-w64-mingw32 \
    -t msys2-cross-clang64 .
```

### 5. CLI (`msys2-cross`)

**Environment selection:**
```sh
MSYSTEM=CLANG64 ./msys2-cross build libpng
./msys2-cross --msystem=CLANG64 build libpng
```

Parse `--msystem` early (before command dispatch). If not provided, use `$MSYSTEM` or default to `UCRT64`. Source `env-config.sh` to populate all derived variables, then use them for image names, build args, etc.

**Image naming:**
```
BOOTSTRAP_IMAGE="msys2-cross-${MSYSTEM_LOWER}"
WORK_IMAGE="msys2-cross-${MSYSTEM_LOWER}-work"
```

**Setup:**
```sh
./msys2-cross --msystem=CLANG64 setup
```

Computes derived args from MSYSTEM via env-config.sh, then calls:
```sh
podman build \
    --build-arg MSYSTEM=CLANG64 \
    --build-arg MINGW_PREFIX=/clang64 \
    --build-arg TARGET=x86_64-w64-mingw32 \
    -t msys2-cross-clang64 .
```

**Source downloads:**
`download-sources.sh` gains LLVM source download (llvm-project tarball) alongside GCC sources. Both are always downloaded (they're shared across environments).

**All other commands** (`build`, `install`, `deps`, `shell`, etc.) work unchanged — they operate on the image identified by `MSYSTEM_LOWER`.

### 6. LLVM build scripts

Building a working llvm-mingw toolchain requires multiple steps, modeled after [mstorsjo/llvm-mingw](https://github.com/mstorsjo/llvm-mingw):

**`scripts/03-build-llvm.sh` — the compiler itself:**
1. Build LLVM + Clang + LLD with `cmake -G Ninja`
   - `-DLLVM_TARGETS_TO_BUILD` set per architecture (X86 or AArch64)
   - `-DLLVM_DEFAULT_TARGET_TRIPLE=${TARGET}`
   - `-DLLVM_INSTALL_TOOLCHAIN_ONLY=ON`
2. Install to `/usr/` — produces `clang`, `lld`, `llvm-ar`, `llvm-strip`, etc.
3. Create target-prefixed symlinks: `${TARGET}-clang` → `clang`, etc.

**`scripts/03-build-llvm-runtimes.sh` — runtime libraries (runs after CRT):**
1. Build compiler-rt builtins for `${TARGET}` (provides `__muldi3`, `__divdi3`, etc.)
2. Build libunwind for `${TARGET}` (C++ exception unwinding)
3. Build libc++ and libc++abi for `${TARGET}` (C++ standard library)
4. Install all to `${MINGW_PREFIX}/lib/`

Each step uses `cmake -G Ninja` with the freshly-built clang as the compiler and the CRT that was built in between.

Pin to a specific LLVM version in `common.sh` (matched to MSYS2's current LLVM version — currently 20.x).

### 7. RPM spec

Deferred — the spec file initially remains UCRT64-only.

## Migration path

### Phase 1 — Parameterize UCRT64 (no functional change)

Split into sub-phases with verification after each to isolate regressions:

**Phase 1a — Baseline capture:**
1. Build UCRT64 image, run all smoke tests, record results
2. Build a known package (zlib), record package contents (`bsdtar -tf *.pkg.tar.zst`)
3. Capture installed file list: `pacman -Ql` inside the container

**Phase 1b — Create env-config.sh, refactor build scripts:**
1. Create `scripts/env-config.sh` with the UCRT64 case
2. Have each build script (01-07) source env-config.sh and replace hardcoded `TARGET`, `MINGW_PREFIX` with variables
3. `common.sh` keeps version pins only, drops `TARGET`/`MINGW_PREFIX`
4. **Verify:** Rebuild UCRT64 image, run smoke tests, compare against Phase 1a baseline

**Phase 1c — Refactor config files and wrappers:**
1. Parameterize `makepkg_mingw.conf` (CHOST, STRIP, OBJCOPY, CFLAGS)
2. Create `.in` templates for meson cross-file, cmake toolchain, cargo config
3. Add config generation step to `08-setup-pacman.sh`
4. Parameterize wrappers (mingw-cmake, mingw-meson, mingw-pkg-config)
5. Update the 4 hardcoded patches
6. Restructure dummy-packages.list with section markers
7. **Verify:** Rebuild, smoke tests, build zlib, compare against baseline

**Phase 1d — Refactor CLI and Containerfile:**
1. Add `--msystem` flag parsing to msys2-cross CLI
2. Rename image variables to include `${MSYSTEM_LOWER}`
3. Add `ARG MSYSTEM`, `ARG MINGW_PREFIX`, `ARG TARGET` to Containerfile
4. Replace hardcoded paths in Containerfile `COPY` commands
5. **Verify:** Rebuild with `--build-arg MSYSTEM=UCRT64`, smoke tests, build zlib, compare against baseline. Must produce byte-identical packages.

### Phase 2 — Add CLANG64

1. Add CLANG64 case to env-config.sh
2. Write `03-build-llvm.sh` and `03-build-llvm-runtimes.sh`
3. Add `LLVM_VERSION` to `common.sh` and LLVM source to `download-sources.sh`
4. **Verify:** Build CLANG64 image, run smoke tests, build zlib + libpng

### Phase 3 — Add CLANGARM64

1. Add CLANGARM64 case to env-config.sh
2. Verify aarch64 cross-compilation works with the same scripts
3. **Verify:** Build CLANGARM64 image, run smoke tests, build zlib
4. May need additional patches for aarch64-specific issues (different alignment, no SSE/AVX intrinsics, etc.)

## Verification strategy

Each sub-phase gate:

| Check | How | Pass criteria |
|-------|-----|---------------|
| Image builds | `podman build` completes | Exit 0 |
| Smoke tests | Run all 6 tests in `tests/` | All pass |
| Known package | Build zlib, inspect output | `bsdtar -tf` matches baseline |
| Installed files | `pacman -Ql` inside container | Matches baseline (Phase 1 only) |
| Cross-compiler works | `${CROSS_CC} -v` | Reports correct target triple |
| Rust cross works | `cargo build --target ${RUST_TARGET}` | Produces PE binary |

## Scope boundaries

**In scope:**
- env-config.sh central module
- Parameterization of all scripts, configs, wrappers
- LLVM build scripts (03-build-llvm.sh, 03-build-llvm-runtimes.sh)
- CLI `--msystem` flag
- Per-environment image naming
- Config file generation (meson, cmake, cargo)
- Dummy packages list restructuring with per-CC_FAMILY sections
- Patch updates for 4 affected patches
- download-sources.sh update for LLVM sources
- Per-sub-phase verification with baseline comparison

**Out of scope (deferred):**
- RPM spec parameterization
- MINGW32/MINGW64 environments (32-bit, legacy)
- Wine integration per environment
- Multi-environment images (one image shipping all environments)
- CI/CD for multiple environments
