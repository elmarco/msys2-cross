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

# Compiler tool names
if [ "$CC_FAMILY" = "gcc" ]; then
    CROSS_CC="${TARGET}-gcc"
    CROSS_CXX="${TARGET}-g++"
else
    CROSS_CC="${TARGET}-clang"
    CROSS_CXX="${TARGET}-clang++"
fi
CROSS_AR="${TARGET}-ar"
CROSS_STRIP="${TARGET}-strip"
CROSS_OBJCOPY="${TARGET}-objcopy"
CROSS_RANLIB="${TARGET}-ranlib"
CROSS_WINDRES="${TARGET}-windres"
```

`config/mingw-env.sh` becomes a thin re-export of env-config.sh for use inside the container (where scripts live at `/opt/msys2-cross/`).

`scripts/common.sh` keeps only version pins and download URLs (environment-independent).

### 2. Build scripts

Build scripts source `env-config.sh` and use `${TARGET}`, `${CROSS_CC}`, `${MINGW_PREFIX}`, etc. instead of hardcoded values.

**GCC path (CC_FAMILY=gcc):**
- `01-build-binutils.sh` — GNU binutils + ld
- `03-build-gcc-bootstrap.sh` — bootstrap GCC (C only)
- `06-build-gcc-final.sh` — final GCC (C, C++, LTO)

**Clang path (CC_FAMILY=clang):**
- `03-build-llvm.sh` — LLVM, Clang, LLD, compiler-rt for `${TARGET}`

**Shared (both paths):**
- `02-build-headers.sh` — mingw-w64 headers
- `04-build-crt.sh` — mingw-w64 CRT (uses `${CROSS_CC}`)
- `05-build-winpthreads.sh` — POSIX threads (uses `${CROSS_CC}`)
- `07-build-rust-cross.sh` — Rust std for `${RUST_TARGET}`
- `08-setup-pacman.sh` — pacman DB + dummy packages
- `09-build-base-libs.sh` — base libraries

The GCC path still produces standard `${TARGET}-gcc` binaries in `/usr/bin/`. The Clang path produces `${TARGET}-clang` binaries. Shared scripts use `${CROSS_CC}` so they work with either.

### 3. Config files

**Shell-based (use variables directly, no generation needed):**
- `config/mingw-env.sh` — sources env-config.sh, exports MSYSTEM/MINGW_PREFIX/etc.
- `config/makepkg_mingw.conf` — `CHOST`, `STRIP`, `OBJCOPY` come from env vars
- `config/dummy-packages.list` — stores base names only (e.g., `cmake`, `python`). The prefix `${MINGW_PACKAGE_PREFIX}-` is prepended by `08-setup-pacman.sh` at package creation time.

**Generated at container build time (non-shell formats):**

Templates in `config/` with `@VARIABLE@` placeholders. A generation step in the Containerfile (or in `08-setup-pacman.sh`) uses `sed` to expand them.

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

Single Containerfile, parameterized by `ARG MSYSTEM`:

```dockerfile
ARG MSYSTEM=UCRT64

# Stage 1: Build toolchain from source
FROM fedora:latest AS toolchain-builder
ARG MSYSTEM
COPY scripts/ /opt/msys2-cross/scripts/
COPY sources/ /build/sources/
RUN source /opt/msys2-cross/scripts/env-config.sh \
    && bash scripts/02-build-headers.sh \
    && if [ "$CC_FAMILY" = "gcc" ]; then \
           bash scripts/01-build-binutils.sh \
        && bash scripts/03-build-gcc-bootstrap.sh \
        && bash scripts/04-build-crt.sh \
        && bash scripts/05-build-winpthreads.sh \
        && bash scripts/06-build-gcc-final.sh; \
       else \
           bash scripts/03-build-llvm.sh \
        && bash scripts/04-build-crt.sh \
        && bash scripts/05-build-winpthreads.sh; \
       fi \
    && bash scripts/07-build-rust-cross.sh \
    && rm -rf /build

# Stage 2: Final cross-compilation environment
FROM fedora:latest AS msys2-cross
ARG MSYSTEM
# ... install host deps, copy toolchain, generate configs, setup pacman
```

Stage 2 `COPY` commands that currently reference `/ucrt64` must use the `MINGW_PREFIX` from env-config.sh. Since Dockerfile `COPY` doesn't support variable expansion, Stage 2 uses a shell-based `RUN` step to copy from the builder via a bind-mount, or the build scripts install directly to `${MINGW_PREFIX}` (which varies by environment) and Stage 2 copies `${MINGW_PREFIX}` generically.

Built with:
```sh
podman build --build-arg MSYSTEM=CLANG64 -t msys2-cross-clang64 .
```

### 5. CLI (`msys2-cross`)

**Environment selection:**
```sh
MSYSTEM=CLANG64 ./msys2-cross build libpng
./msys2-cross --msystem=CLANG64 build libpng
```

Parse `--msystem` early (before command dispatch). If not provided, use `$MSYSTEM` or default to `UCRT64`.

**Image naming:**
```
BOOTSTRAP_IMAGE="msys2-cross-${MSYSTEM_LOWER}"
WORK_IMAGE="msys2-cross-${MSYSTEM_LOWER}-work"
```

**Setup:**
```sh
./msys2-cross --msystem=CLANG64 setup
```

Calls `podman build --build-arg MSYSTEM=CLANG64 -t msys2-cross-clang64 .`

**Source downloads:**
`download-sources.sh` gains LLVM source download (llvm-project tarball) alongside GCC sources. Both are always downloaded (they're shared across environments).

**All other commands** (`build`, `install`, `deps`, `shell`, etc.) work unchanged — they operate on the image identified by `MSYSTEM_LOWER`.

### 6. LLVM build (`scripts/03-build-llvm.sh`)

Build llvm-mingw-style toolchain from LLVM source:

1. Build LLVM + Clang + LLD targeting `${TARGET}`
2. Build compiler-rt (builtins, sanitizers) for `${TARGET}`
3. Install to `/usr/bin/${TARGET}-clang`, etc.

Pin to a specific LLVM version in `common.sh` (matched to MSYS2's current LLVM version).

LLVM build uses `cmake -G Ninja` and takes ~1-2h. Cached by the multi-stage Containerfile like GCC is today.

### 7. RPM spec

`msys2-cross.spec` would need to be parameterized or split into per-environment spec files. Since the RPM packaging is secondary to the container workflow, this can be deferred — the spec file can initially remain UCRT64-only.

## Migration path

Phase 1 — Parameterize UCRT64 (no functional change):
1. Create `env-config.sh` with UCRT64 values
2. Refactor all scripts, configs, and wrappers to use variables
3. Generate meson/cmake/cargo configs at build time
4. Add `--msystem` to CLI
5. Rename images to include environment suffix
6. Verify UCRT64 still builds and works identically

Phase 2 — Add CLANG64:
1. Add CLANG64 case to env-config.sh
2. Write `03-build-llvm.sh`
3. Add LLVM source to `download-sources.sh`
4. Test CLANG64 builds with known packages

Phase 3 — Add CLANGARM64:
1. Add CLANGARM64 case to env-config.sh
2. Verify aarch64 cross-compilation works
3. Test with known packages (may need additional patches for aarch64-specific issues)

## Scope boundaries

**In scope:**
- env-config.sh central module
- Parameterization of all scripts, configs, wrappers
- LLVM build script
- CLI `--msystem` flag
- Per-environment image naming
- Config file generation (meson, cmake, cargo)
- Patch updates for 4 affected patches
- download-sources.sh update for LLVM sources

**Out of scope (deferred):**
- RPM spec parameterization
- MINGW32/MINGW64 environments (32-bit, legacy)
- Wine integration per environment
- Multi-environment images (one image shipping all environments)
- CI/CD for multiple environments
