%global gcc_version   16.1.0
%global binutils_ver  2.46
%global mingw_commit  818fa65100f7
%global mingw_ver     14.0.0
%global rust_version  1.96.0
%global target        x86_64-w64-mingw32
%global rust_target   x86_64-pc-windows-gnu

Name:           msys2-cross
Version:        %{gcc_version}
Release:        1%{?dist}
Summary:        UCRT64 cross-compilation toolchain for building Windows binaries

License:        GPL-3.0-or-later AND LGPL-2.1-or-later AND ZPL-2.1 AND BSD-2-Clause
URL:            https://github.com/user/msys2-cross
ExclusiveArch:  x86_64

# Toolchain sources
Source0:        https://ftp.gnu.org/gnu/gcc/gcc-%{gcc_version}/gcc-%{gcc_version}.tar.xz
Source1:        https://ftp.gnu.org/gnu/binutils/binutils-with-gold-%{binutils_ver}.tar.bz2
Source2:        https://github.com/mingw-w64/mingw-w64/archive/%{mingw_commit}.tar.gz
Source3:        https://static.rust-lang.org/dist/rustc-%{rust_version}-src.tar.xz

# Build infrastructure (this repo: scripts, config, wrappers, patches, packages)
Source10:       msys2-cross-scripts-%{version}.tar.gz

# PE binaries — no ELF debuginfo to extract
%global debug_package %{nil}

# ---- Build-time deps (from 00-install-host-deps.sh) ----
BuildRequires:  gcc
BuildRequires:  gcc-c++
BuildRequires:  make
BuildRequires:  cmake
BuildRequires:  ninja-build
BuildRequires:  meson
BuildRequires:  autoconf
BuildRequires:  automake
BuildRequires:  libtool
BuildRequires:  texinfo
BuildRequires:  bison
BuildRequires:  flex
BuildRequires:  gperf
BuildRequires:  gmp-devel
BuildRequires:  mpfr-devel
BuildRequires:  libmpc-devel
BuildRequires:  isl-devel
BuildRequires:  zlib-devel
BuildRequires:  readline-devel
BuildRequires:  diffutils
BuildRequires:  findutils
BuildRequires:  file
BuildRequires:  which
BuildRequires:  patch
BuildRequires:  git-core
BuildRequires:  tar
BuildRequires:  xz
BuildRequires:  bzip2
BuildRequires:  zstd
BuildRequires:  pacman
BuildRequires:  fakeroot
BuildRequires:  python3
BuildRequires:  rust
BuildRequires:  cargo

# ---- Runtime deps ----
Requires:       pacman
Requires:       fakeroot
Requires:       gcc
Requires:       gcc-c++
Requires:       make
Requires:       cmake
Requires:       meson
Requires:       ninja-build
Requires:       autoconf
Requires:       automake
Requires:       libtool
Requires:       python3

%description
Cross-compiler and sysroot for building Windows (PE) binaries targeting
x86_64-w64-mingw32 with the UCRT runtime.  Built from GCC %{gcc_version},
binutils %{binutils_ver}, and mingw-w64 %{mingw_ver}.

Includes makepkg-mingw so MSYS2 MINGW-packages PKGBUILDs can be built
directly on Fedora without modification.

# ---- Rust subpackage ----
%package        rust
Summary:        Rust cross-compilation support for %{target}
Requires:       %{name} = %{version}-%{release}
Requires:       rust
Requires:       cargo

%description    rust
Rust std library cross-compiled for %{rust_target}, enabling
cargo build --target %{rust_target} on Fedora.

# ---- Extra build deps metapackage ----
%package        extra-deps
Summary:        Extra host tools for building MINGW packages
Requires:       %{name} = %{version}-%{release}
Requires:       python3-devel
Requires:       python3-docutils
Requires:       python3-sphinx
Requires:       python3-lxml
Requires:       python3-setuptools
Requires:       python3-numpy
Requires:       python3-jinja2
Requires:       python3-cython
Requires:       perl
Requires:       ruby
Requires:       rubygem-asciidoctor
Requires:       doxygen
Requires:       graphviz
Requires:       swig
Requires:       vala
Requires:       gtk-doc
Requires:       itstool
Requires:       po4a
Requires:       nasm
Requires:       ragel
Requires:       gtk-update-icon-cache
Requires:       cargo-c

%description    extra-deps
Metapackage pulling in host tools that MINGW-packages commonly need
during build (Python, Perl, Ruby, doxygen, vala, etc.).

# =========================================================================
%prep
%setup -q -c -T -n %{name}-%{version}

# Unpack build infrastructure
tar xf %{SOURCE10}

# Place toolchain tarballs where the build scripts expect them
mkdir -p sources
cp %{SOURCE0} sources/
cp %{SOURCE1} sources/
cp %{SOURCE2} sources/
cp %{SOURCE3} sources/

# =========================================================================
%build
# GCC/binutils manage their own flags — Fedora's hardened CFLAGS/CXXFLAGS
# (e.g. -Werror=format-security, annobin specs) clash with GCC's internal
# -Werror and break the bootstrap build.
unset CFLAGS CXXFLAGS FFLAGS FCFLAGS LDFLAGS RUSTFLAGS CC CXX AR NM RANLIB

# Point build scripts at our working directories
export SRC_DIR=%{_builddir}/%{name}-%{version}/src
export BUILD_DIR=%{_builddir}/%{name}-%{version}/build
export SOURCES_CACHE=%{_builddir}/%{name}-%{version}/sources

# Stage all installs under DESTDIR (mock user cannot write to /usr)
export DESTDIR=%{_builddir}/%{name}-%{version}/staging

mkdir -p "${SRC_DIR}" "${BUILD_DIR}" "${DESTDIR}"

# Build cross-toolchain (scripts 01-07)
bash scripts/01-build-binutils.sh
bash scripts/02-build-headers.sh
bash scripts/03-build-gcc-bootstrap.sh
bash scripts/04-build-crt.sh
bash scripts/05-build-winpthreads.sh
bash scripts/06-build-gcc-final.sh
bash scripts/07-build-rust-cross.sh

# =========================================================================
%install
STAGING=%{_builddir}/%{name}-%{version}/staging

# ---- Cross-compiler binaries ----
mkdir -p %{buildroot}/usr/bin
for f in "${STAGING}"/usr/bin/%{target}-*; do
    [ -f "$f" ] || continue
    install -Dm755 "$f" "%{buildroot}/usr/bin/$(basename "$f")"
done

# ---- GCC internal libraries and tools ----
# Fedora uses lib64
for dir in lib64 lib; do
    if [ -d "${STAGING}/usr/${dir}/gcc/%{target}" ]; then
        mkdir -p "%{buildroot}/usr/${dir}/gcc"
        cp -a "${STAGING}/usr/${dir}/gcc/%{target}" "%{buildroot}/usr/${dir}/gcc/"
    fi
done
if [ -d "${STAGING}/usr/libexec/gcc/%{target}" ]; then
    mkdir -p %{buildroot}/usr/libexec/gcc
    cp -a "${STAGING}/usr/libexec/gcc/%{target}" %{buildroot}/usr/libexec/gcc/
fi

# ---- Sysroot ----
mkdir -p %{buildroot}/ucrt64
cp -a "${STAGING}"/ucrt64/* %{buildroot}/ucrt64/

# GCC sysroot discovery symlinks
mkdir -p %{buildroot}/usr/%{target}
# Preserve binutils' bin/ directory if present
if [ -d "${STAGING}/usr/%{target}/bin" ]; then
    cp -a "${STAGING}/usr/%{target}/bin" "%{buildroot}/usr/%{target}/"
fi
ln -sfn /ucrt64/include %{buildroot}/usr/%{target}/include
ln -sfn /ucrt64/lib %{buildroot}/usr/%{target}/lib

# ---- Rust std for cross target ----
RUST_SYSROOT=$(rustc --print sysroot)
if [ -d "${STAGING}${RUST_SYSROOT}/lib/rustlib/%{rust_target}" ]; then
    mkdir -p "%{buildroot}${RUST_SYSROOT}/lib/rustlib/%{rust_target}"
    cp -a "${STAGING}${RUST_SYSROOT}/lib/rustlib/%{rust_target}/"* \
        "%{buildroot}${RUST_SYSROOT}/lib/rustlib/%{rust_target}/"
fi

# ---- Build infrastructure ----
mkdir -p %{buildroot}/opt/msys2-cross
for d in config wrappers patches packages; do
    [ -d "$d" ] && cp -a "$d" %{buildroot}/opt/msys2-cross/
done
chmod +x %{buildroot}/opt/msys2-cross/wrappers/*
chmod +x %{buildroot}/opt/msys2-cross/config/makepkg-mingw

# Symlink wrappers into /ucrt64/bin where PKGBUILDs expect them
mkdir -p %{buildroot}/ucrt64/bin
ln -sfn /opt/msys2-cross/wrappers/mingw-cmake %{buildroot}/ucrt64/bin/cmake
ln -sfn /opt/msys2-cross/wrappers/mingw-meson %{buildroot}/ucrt64/bin/meson
ln -sfn /opt/msys2-cross/wrappers/mingw-meson %{buildroot}/ucrt64/bin/meson.exe
ln -sfn /opt/msys2-cross/wrappers/mingw-pkg-config %{buildroot}/ucrt64/bin/%{target}-pkg-config
ln -sfn /usr/bin/%{target}-gcc %{buildroot}/ucrt64/bin/cc
ln -sfn /usr/bin/gtk-update-icon-cache %{buildroot}/ucrt64/bin/gtk-update-icon-cache

# bsdtar xattr wrapper for pacman on non-overlay filesystems
install -Dm755 /dev/stdin %{buildroot}/usr/local/bin/bsdtar <<'WRAPPER'
#!/bin/bash
for arg in "$@"; do
    case "$arg" in
        -x*|--extract) exec /usr/bin/bsdtar --no-xattrs --no-fflags "$@" ;;
    esac
done
exec /usr/bin/bsdtar "$@"
WRAPPER

# ---- PATH setup ----
mkdir -p %{buildroot}%{_sysconfdir}/profile.d
cat > %{buildroot}%{_sysconfdir}/profile.d/msys2-cross.sh <<'EOF'
export PATH="/opt/msys2-cross/wrappers:/opt/msys2-cross/config:${PATH}"
EOF

# ---- Pacman setup ----
# Run script 08 with INSTALL_ROOT=buildroot so it creates repo DB, dummy
# packages, and pacman state directly in the buildroot (works as non-root).
# Uses INSTALL_ROOT instead of DESTDIR to avoid polluting the environment
# from common.sh (which adds DESTDIR/usr/bin to PATH etc.).
export INSTALL_ROOT=%{buildroot}
bash scripts/08-setup-pacman.sh

# =========================================================================
%files
/ucrt64
/usr/bin/%{target}-*
/usr/lib*/gcc/%{target}
/usr/libexec/gcc/%{target}
/usr/%{target}
/usr/local/bin/bsdtar
/opt/msys2-cross
/var/lib/pacman/mingw
/var/cache/pacman/mingw
%config(noreplace) %{_sysconfdir}/profile.d/msys2-cross.sh

%files rust
%{_prefix}/lib/rustlib/%{rust_target}

%files extra-deps
# Metapackage — deps only, no files

# =========================================================================
%changelog
* Fri Jun 12 2026 Marc-André Lureau <marcandre@redhat.com> - 16.1.0-1
- Initial source-built RPM of msys2-cross UCRT64 cross-toolchain
