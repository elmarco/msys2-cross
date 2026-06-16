# MSYS2 Linux Cross-Compilation Toolchain

This file is for AI assistants and code generators. User-facing documentation is in README.md.

## Design constraints

- **Offline builds**: Containers run with `--network=none`. All sources must be pre-downloaded on the host. Never add network-dependent steps to build scripts.
- **No PKGBUILD modifications on disk**: `makepkg-mingw` works on a copy (`cp PKGBUILD PKGBUILD.orig`, restore after build). Patches must not corrupt the original. Use `sed` replacements that preserve array structure — never delete lines from the middle of bash arrays.
- **Bind-mount workflow**: Users clone MINGW-packages on the host and mount into the container. The container never clones repos itself.
- **Target environments**: UCRT64 (GCC, x86_64), CLANG64 (Clang/LLVM, x86_64), CLANGARM64 (Clang/LLVM, aarch64). Selected via `--msystem` flag. One container image per environment.

## Architecture decisions

These are load-bearing — violating them breaks the build:

- **Sysroot at `MINGW_PREFIX`**: `/ucrt64` for UCRT64, `/clang64` for CLANG64, `/clangarm64` for CLANGARM64. Matches MSYS2's conventions so PKGBUILDs work unmodified.
- **Central `env-config.sh`**: `scripts/env-config.sh` maps `MSYSTEM` → all derived variables (TARGET, MINGW_PREFIX, CC_FAMILY, CROSS_CC, etc.). All build scripts, wrappers, and the CLI source this module.
- **Config generation from `.in` templates**: Non-shell configs (meson cross-file, cmake toolchain, cargo config) are generated from `config/*.in` templates by `08-setup-pacman.sh` at container build time. Output goes to `/opt/msys2-cross/generated/`.
- **Cross-compiler in `/usr/bin/`**: Standard `${TARGET}-gcc` (GCC) or `${TARGET}-clang` (LLVM) naming. Sysroot discovery via symlinks `/usr/${TARGET}/{include,lib} → ${MINGW_PREFIX}/{include,lib}`.
- **Per-environment images**: `msys2-cross-ucrt64`, `msys2-cross-clang64`, `msys2-cross-clangarm64`. The Containerfile uses ARG directives; the CLI passes `--build-arg` to podman.
- **pacman with separate DB** (`/var/lib/pacman/mingw/`): Isolates from Fedora's dnf. All pacman commands must use `--config /opt/msys2-cross/config/pacman-mingw.conf`.
- **CC must NOT be exported globally**: `config/mingw-env.sh` intentionally does NOT export CC/CXX. Autotools finds the cross-compiler via `--host=${MINGW_CHOST}`. Setting CC globally breaks `config.guess` (it uses `$CC -dumpmachine` and misidentifies the build machine).
- **Cargo offline mode**: `config/cargo-cross.toml.in` (template) generates `generated/cargo-cross.toml` at build time; sets `[net] offline = true`. Host cargo registry is bind-mounted read-only into the container.
- **Fedora uses `lib64`**: GCC installs to `/usr/lib64/gcc/` not `/usr/lib/gcc/`. The Containerfile accounts for this.

## Pitfalls

Things that have caused real bugs — check these before modifying related code:

- **pkg-config/pkgconf recursion**: Do NOT symlink pkg-config or pkgconf into `/ucrt64/bin`. Fedora's pkgconf finds itself via PATH and hangs in infinite recursion. Use the meson cross file's `pkgconfig =` entry instead.
- **Container UID mapping**: Running with `-v host:container:rw` may create files owned by container UIDs (100999). Use `podman unshare chown` to fix, or mount `:ro` when possible.
- **Strip tool**: `makepkg_mingw.conf` sets `STRIP=/usr/bin/${CROSS_STRIP}`. If PE binaries come out corrupted, verify this is being picked up by makepkg.
- **Meson boolean vs feature options**: Meson `feature` options take `enabled`/`disabled`/`auto`. Meson `boolean` options take `true`/`false`. Using the wrong type silently fails. When writing patches, check the `meson_options.txt` or `meson.options` in the package.
- **`--build` flag in PKGBUILDs**: Many MSYS2 PKGBUILDs pass `--build=${MINGW_CHOST}` to configure, which is correct on MSYS2 (build machine IS mingw32) but wrong for cross-compilation. `makepkg-mingw` auto-rewrites this, but packages with custom configure (GMP) may still fail.
- **Meson implicit setup**: Some PKGBUILDs call `meson` without the `setup` subcommand (old-style). The `mingw-meson` wrapper detects this and injects `--cross-file`. If a build says `Build type: native build`, the wrapper isn't being used.
- **Fedora makepkg `---mirror` bug**: Fedora's patched makepkg passes `---mirror` (triple dash) to curl, which curl rejects. The SRPM generator works around this with a curl wrapper that strips triple-dash args.
- **Build tools as dummy packages**: Host-only tools like `gperf`, `ragel`, `nasm` that generate source code should be in `dummy-packages.list`, not cross-compiled. If a `BuildRequires` for `${MINGW_PACKAGE_PREFIX}-<tool>` appears in a generated spec and that tool is installed on the host, it's probably missing from the dummy list.

## makepkg-mingw auto-rewrite patterns

`config/makepkg-mingw` applies per-package patches first, then these generic rewrites (in order):

1. **Autotools `--host`/`--build` injection**: Adds `--host=${MINGW_CHOST} --build=<linux-triple>` to `configure` lines containing `--prefix=${MINGW_PREFIX}`
2. **`--build=${MINGW_CHOST}` fix**: Rewrites to `--build=<linux-triple>` (handles `${MINGW_CHOST}`, `"${MINGW_CHOST}"`, and `${CHOST}` forms)
3. **`CHOST=${MINGW_CHOST}` pattern** (zlib-style configure): Replaces with `CC=${MINGW_CHOST}-gcc` + `--host`/`--build` flags. Handles both single-line and multi-line (backslash continuation)
4. **Meson references**: Routes `meson setup` to `mingw-meson` wrapper, `meson compile`/`install` to `/usr/bin/meson`. Handles `${MINGW_PREFIX}/bin/meson.exe`, bare `meson`, and both quoting styles
5. **CMake references**: Rewrites `${MINGW_PREFIX}/bin/cmake(.exe)` to `${MINGW_PREFIX}/bin/cmake` (which is the `mingw-cmake` wrapper)
6. **`MSYS2_ARG_CONV_EXCL` removal**: Strips all forms (env prefix with continuation, inline prefix, standalone export). MSYS2-only path conversion suppression, not needed on Linux
7. **Python exe references**: Rewrites `${MINGW_PREFIX}/bin/python3(.exe)` → `/usr/bin/python3`. Also rewrites CMake `-DPython3_EXECUTABLE=`, `-DPython_EXECUTABLE=`, `-DPYTHON_EXECUTABLE=`
8. **`noextract` + manual tar removal**: Removes `noextract=()` arrays and replaces manual `tar -xf` lines with `true` (MSYS2 path workaround not needed on Linux)

After rewrites, **validation warnings** are emitted for patterns that should have been caught but weren't (e.g., `--build=${MINGW_CHOST}` still present, meson/cmake still referencing `${MINGW_PREFIX}/bin/`).

## Wrapper behavior

- **`mingw-meson`**: Uses `generated/cross-file.meson` (built from `config/cross-file.meson.in`). Sources `mingw-env.sh` for `MINGW_PREFIX`. Detects subcommands — `compile`/`install`/`test` bypass cross-file injection. Detects old-style implicit `setup` (no subcommand) and injects cross-file automatically.
- **`mingw-cmake`**: Uses `generated/toolchain.cmake` (built from `config/toolchain.cmake.in`) via `-DCMAKE_TOOLCHAIN_FILE`. Detects `--build`/`--install`/`--open`/`--preset` subcommands and bypasses cross-flags for those.
- **`mingw-pkg-config`**: Sources `mingw-env.sh` and sets `PKG_CONFIG_LIBDIR` to `${MINGW_PREFIX}/lib/pkgconfig:${MINGW_PREFIX}/share/pkgconfig` so pkg-config finds cross-compiled `.pc` files.
- **`native-pkg-config`**: Resets `PKG_CONFIG_LIBDIR` to system paths (`/usr/lib64/pkgconfig:/usr/share/pkgconfig`). Used for native build-time dependencies so they don't accidentally pick up cross `.pc` files. Referenced in `generated/cross-file.meson`.
- **`cygpath`**: No-op shim that returns its input unchanged. MSYS2 PKGBUILDs call `cygpath -m` to convert Unix paths to Windows paths — on Linux, paths are already correct.
- **`pacman-mingw`**: Wrapper that always passes `--config /opt/msys2-cross/config/pacman-mingw.conf`.

## Dependency resolver internals

`scripts/resolve-deps.sh` runs inside the container. It performs a DFS traversal of package dependencies, using pacman to check what's already installed.

**Iterative checkout loop**: The host-side `find_all_missing_deps()` runs the resolver iteratively. When the resolver encounters a package whose source directory doesn't exist under `/src`, it emits `NEED_CHECKOUT:<pkg>` to stderr. The host catches these, runs `checkout_pkg` for each, and re-runs the resolver. This converges because each iteration can only add packages. The loop terminates when no new checkouts are needed, or no requested checkouts succeed (package doesn't exist in MINGW-packages), or after 20 iterations (safety cap).

**Output format** (stdout, consumed by `cmd_build` in `msys2-cross`):
```
pkg-a
pkg-b
pkg-c
---rebuild---
pkg-a
```

Lines before `---rebuild---` are packages to build/install in order. Lines after are packages that need a second build to resolve circular dependencies (e.g., libwebp depends on libtiff which depends on libwebp). The rebuild pass uses `install_single --force` to overwrite the already-installed version.

**Cycle detection**: When DFS encounters a node already on the stack (back-edge), it records the child as needing rebuild. After the initial build, these cycle members are rebuilt with their full dependency set available.

## Split package handling

`checkout_pkg()` in `lib-mingw-pkg.sh` handles split packages by stripping common suffixes (`-runtime`, `-tools`, `-libs`, `-devel`, `-git`) to find the source directory. For example, `mingw-w64-gettext-runtime` maps to the `mingw-w64-gettext` source dir.

`install_single()` finds all `*.pkg.tar.*` files in a package directory and installs them all, handling the case where one PKGBUILD produces multiple split packages.

## lib-mingw-pkg.sh public API

| Function | Purpose |
|---|---|
| `normalize_pkg(name)` | Adds `mingw-w64-` prefix if missing |
| `ensure_mingw_packages()` | Clones sparse MINGW-packages repo if absent (uses `MINGW_PACKAGES_DIR`) |
| `checkout_pkg(pkg)` | Sparse-checks out a package. Handles split packages. Sets `_checkout_actual` to the resolved source dir |
| `download_sources(pkg)` | Runs `makepkg --verifysource` with `config/makepkg-download.conf`. Calls `_pre_clone_git_sources` and `fetch_cargo_deps` |
| `_pre_clone_git_sources(pkgbuild)` | Works around Fedora makepkg VCS bug: pre-clones `git+` sources so makepkg doesn't fail |
| `fetch_cargo_deps(pkgbuild)` | Pre-fetches Rust crate dependencies by extracting `Cargo.lock` from the source and running `cargo fetch` |
| `parse_pkgbuild(path)` | Evaluates a PKGBUILD in a subshell and emits shell variable assignments for `_pkgbase`, `_pkgname[]`, `_pkgver`, `_pkgrel`, `_pkgdesc`, `_url`, `_license[]`, `_depends[]`, `_makedepends[]`, `_source[]` |
| `load_dummy_packages()` | Loads `config/dummy-packages.list` + scans `packages/` dir PKGBUILDs for additional dummy packages and their `Provides:` entries |

## Writing patches (patches/*.sh)

- **Never delete lines** from bash arrays — use `sed 's/pattern/replacement/'`
- Patches run via `source` BEFORE the PKGBUILD is sourced — **PKGBUILD variables like `_realname`, `pkgver`, `pkgname` are NOT available**. Use only literal strings in sed patterns
- Patches run BEFORE the generic auto-rewrites in makepkg-mingw
- Name: `<pkgbase>.sh` (e.g., `mingw-w64-glib2.sh`)
- For Rust packages: `sed -i '/cargo update/d; /cargo fetch/d'` to skip network-dependent commands

### Disabling gobject-introspection

`g-ir-scanner` tries to execute compiled `.exe` files — fails without Wine. The most common reason for writing a patch:

- Meson `feature` options: `sed -i 's/--auto-features=enabled/--auto-features=enabled -Dintrospection=disabled/' PKGBUILD`
- Meson `boolean` options: use `-Dintrospection=false` (not `disabled`)
- Autotools: `sed -i 's/--enable-introspection/--disable-introspection/' PKGBUILD`
- When no `--auto-features` to hook into: append to `--prefix`: `sed -i 's|--prefix="${MINGW_PREFIX}"|--prefix="${MINGW_PREFIX}" -Dintrospection=false|' PKGBUILD`
- Also disable `-Dvapi=false` when present (vapi generation depends on GIR files)

## RPM/SRPM internals

### Toolchain spec (`msys2-cross.spec`)

Builds three sub-packages: `msys2-cross` (toolchain + base libs), `msys2-cross-rust` (Rust cross-std), `msys2-cross-extra-deps` (additional host deps).

**Bootstrap Provides**: The spec declares virtual `Provides:` for gettext sub-packages (`gettext-runtime`, `gettext-libtextstyle`, `gettext-tools`, `gettext`). These break the libiconv↔gettext circular dependency in mock: libtre depends on gettext-runtime, but gettext can't be built until libiconv is available. The virtual provides let mock install packages that transitively need gettext before the real gettext RPM exists.

**Do NOT add libiconv to Provides** — packages that BuildRequire libiconv need the real RPM with headers, and a virtual provide would shadow it (DNF considers the dependency satisfied without installing actual files).

### MINGW SRPM generator (`scripts/make-mingw-srpm.sh`)

Generates a Fedora-style SRPM from any MSYS2 PKGBUILD:

1. Parses PKGBUILD arrays (`depends`, `makedepends`, `source`) via `lib-mingw-pkg.sh`
2. Maps MINGW package names to RPM names (prefix `mingw-w64-ucrt-x86_64-`)
3. **Filters gettext sub-packages** from `BuildRequires` — they'd create unresolvable cycles since gettext itself needs to be built from a MINGW PKGBUILD
4. Detects `git+` sources → adds `BuildRequires: git`
5. Detects cross-compilation patches → embeds as `SourceN`
6. Handles split packages (multiple `pkgname` entries from one `pkgbase`)
7. Maps SPDX licenses from PKGBUILD to RPM format
8. The generated `%build` section includes a `curl` wrapper to work around the Fedora makepkg `---mirror` bug

### Dummy package system

Two sources of dummy packages (host tools that don't need cross-compilation):
1. `config/dummy-packages.list` — section-aware list (`# [host]`, `# [shared]`, `# [gcc]`, `# [clang]`). Base names without MINGW prefix; prefix is prepended by `08-setup-pacman.sh` at package creation time. GCC/Clang sections are filtered by `CC_FAMILY`.
2. `packages/` directory — PKGBUILDs for toolchain components, plus their `Provides:` entries

`load_dummy_packages()` merges both. If a MINGW dependency resolves to a dummy package, the resolver skips it.
