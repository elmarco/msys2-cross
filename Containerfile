# MSYS2 Linux Bootstrap — Cross-compilation container
#
# Builds a cross-compiler targeting Windows from source, then sets up
# makepkg-mingw so MSYS2 MINGW-packages PKGBUILDs can be built on Linux.
#
# Usage:
#   podman build --build-arg MSYSTEM=UCRT64 -t msys2-cross-ucrt64 .
#   podman build --build-arg MSYSTEM=CLANG64 --build-arg MINGW_PREFIX=/clang64 \
#       --build-arg TARGET=x86_64-w64-mingw32 -t msys2-cross-clang64 .

ARG MSYSTEM=UCRT64
ARG MINGW_PREFIX=/ucrt64
ARG TARGET=x86_64-w64-mingw32
ARG CC_FAMILY=gcc
ARG RUST_TARGET=x86_64-pc-windows-gnu
ARG MINGW_PACKAGE_PREFIX=mingw-w64-ucrt-x86_64

# ===========================================================================
# Stage 1: Build the cross-toolchain from source
#
# Each build step is a separate COPY+RUN pair so that modifying a late-stage
# script (e.g. llvm-runtimes) doesn't invalidate the cache for earlier heavy
# steps (e.g. the LLVM build). Path-specific steps use `if` guards and are
# no-ops for the other path.
# ===========================================================================
FROM fedora:latest AS toolchain-builder
ARG MSYSTEM
ARG CC_FAMILY

COPY scripts/common.sh scripts/env-config.sh /opt/msys2-cross/scripts/
COPY sources/ /build/sources/

COPY scripts/00-install-host-deps.sh /opt/msys2-cross/scripts/
RUN export MSYSTEM=${MSYSTEM} \
    && bash /opt/msys2-cross/scripts/00-install-host-deps.sh

COPY scripts/01-build-binutils.sh /opt/msys2-cross/scripts/
RUN export MSYSTEM=${MSYSTEM} \
    && bash /opt/msys2-cross/scripts/01-build-binutils.sh

COPY scripts/03-build-llvm.sh /opt/msys2-cross/scripts/
RUN if [ "$CC_FAMILY" = "clang" ]; then \
        export MSYSTEM=${MSYSTEM} \
        && bash /opt/msys2-cross/scripts/03-build-llvm.sh; \
    fi

COPY scripts/02-build-headers.sh /opt/msys2-cross/scripts/
RUN export MSYSTEM=${MSYSTEM} \
    && bash /opt/msys2-cross/scripts/02-build-headers.sh

COPY scripts/03-build-gcc-bootstrap.sh /opt/msys2-cross/scripts/
RUN if [ "$CC_FAMILY" = "gcc" ]; then \
        export MSYSTEM=${MSYSTEM} \
        && bash /opt/msys2-cross/scripts/03-build-gcc-bootstrap.sh; \
    fi

COPY scripts/04-build-crt.sh /opt/msys2-cross/scripts/
RUN export MSYSTEM=${MSYSTEM} \
    && bash /opt/msys2-cross/scripts/04-build-crt.sh

COPY scripts/05-build-winpthreads.sh /opt/msys2-cross/scripts/
RUN export MSYSTEM=${MSYSTEM} \
    && bash /opt/msys2-cross/scripts/05-build-winpthreads.sh

COPY scripts/06-build-gcc-final.sh /opt/msys2-cross/scripts/
RUN if [ "$CC_FAMILY" = "gcc" ]; then \
        export MSYSTEM=${MSYSTEM} \
        && bash /opt/msys2-cross/scripts/06-build-gcc-final.sh; \
    fi

COPY scripts/03-build-llvm-runtimes.sh /opt/msys2-cross/scripts/
RUN if [ "$CC_FAMILY" = "clang" ]; then \
        export MSYSTEM=${MSYSTEM} \
        && bash /opt/msys2-cross/scripts/03-build-llvm-runtimes.sh; \
    fi

COPY scripts/07-build-rust-cross.sh /opt/msys2-cross/scripts/
RUN export MSYSTEM=${MSYSTEM} \
    && bash /opt/msys2-cross/scripts/07-build-rust-cross.sh \
    && rm -rf /build

# ===========================================================================
# Stage 2: Assemble the final cross-compilation environment
# ===========================================================================
FROM fedora:latest AS msys2-cross
ARG MSYSTEM
ARG MINGW_PREFIX
ARG TARGET
ARG CC_FAMILY
ARG RUST_TARGET
ARG MINGW_PACKAGE_PREFIX

# Install host build dependencies (split: base + extras)
COPY scripts/common.sh scripts/env-config.sh scripts/00-install-host-deps.sh scripts/00-install-extra-deps.sh /opt/msys2-cross/scripts/
RUN bash /opt/msys2-cross/scripts/00-install-host-deps.sh
RUN bash /opt/msys2-cross/scripts/00-install-extra-deps.sh

# Copy cross-toolchain from builder stage
COPY --from=toolchain-builder ${MINGW_PREFIX} ${MINGW_PREFIX}
COPY --from=toolchain-builder /usr/bin/${TARGET}-* /usr/bin/
COPY --from=toolchain-builder /usr/${TARGET} /usr/${TARGET}
COPY --from=toolchain-builder /usr/lib/rustlib/${RUST_TARGET} /usr/lib/rustlib/${RUST_TARGET}

# GCC-specific paths (only exist when CC_FAMILY=gcc)
RUN --mount=from=toolchain-builder,source=/,target=/builder \
    if [ "${CC_FAMILY}" = "gcc" ]; then \
        mkdir -p /usr/lib64/gcc /usr/libexec/gcc \
        && cp -a /builder/usr/lib64/gcc/${TARGET} /usr/lib64/gcc/ \
        && cp -a /builder/usr/libexec/gcc/${TARGET} /usr/libexec/gcc/; \
    fi

# LLVM tools (only exist when CC_FAMILY=clang)
RUN --mount=from=toolchain-builder,source=/,target=/builder \
    if [ "${CC_FAMILY}" = "clang" ]; then \
        cp -a /builder/usr/bin/clang* /builder/usr/bin/lld* \
              /builder/usr/bin/llvm-* /builder/usr/bin/ld.lld* \
              /usr/bin/; \
        mkdir -p /usr/lib/clang \
        && cp -a /builder/usr/lib/clang/. /usr/lib/clang/; \
    fi

# Recreate sysroot symlinks and build tool wrappers
RUN export MSYSTEM=${MSYSTEM} \
    && source /opt/msys2-cross/scripts/env-config.sh \
    && mkdir -p /usr/${TARGET} ${MINGW_PREFIX}/bin \
    && ln -sfn ${MINGW_PREFIX}/include /usr/${TARGET}/include \
    && ln -sfn ${MINGW_PREFIX}/lib /usr/${TARGET}/lib \
    && ln -sfn /opt/msys2-cross/wrappers/mingw-cmake ${MINGW_PREFIX}/bin/cmake \
    && ln -sfn /opt/msys2-cross/wrappers/mingw-meson ${MINGW_PREFIX}/bin/meson \
    && ln -sfn /opt/msys2-cross/wrappers/mingw-meson ${MINGW_PREFIX}/bin/meson.exe \
    && ln -sfn /opt/msys2-cross/wrappers/mingw-pkg-config ${MINGW_PREFIX}/bin/${TARGET}-pkg-config \
    && ln -sfn /usr/bin/${CROSS_CC} ${MINGW_PREFIX}/bin/cc

# Install build infrastructure
COPY config/ /opt/msys2-cross/config/
COPY wrappers/ /opt/msys2-cross/wrappers/
COPY patches/ /opt/msys2-cross/patches/
COPY packages/ /opt/msys2-cross/packages/
RUN chmod +x /opt/msys2-cross/wrappers/* \
    && chmod +x /opt/msys2-cross/config/makepkg-mingw

# Set up pacman, generate configs, and package the toolchain
COPY scripts/08-setup-pacman.sh /opt/msys2-cross/scripts/
RUN export MSYSTEM=${MSYSTEM} \
    && bash /opt/msys2-cross/scripts/08-setup-pacman.sh

# Build base libraries (libiconv, gettext)
COPY scripts/09-build-base-libs.sh scripts/lib-mingw-pkg.sh /opt/msys2-cross/scripts/
RUN export MSYSTEM=${MSYSTEM} \
    && bash /opt/msys2-cross/scripts/09-build-base-libs.sh

# Environment setup
ENV MSYSTEM=${MSYSTEM}
ENV MINGW_PREFIX=${MINGW_PREFIX}
ENV MINGW_CHOST=${TARGET}
ENV MINGW_PACKAGE_PREFIX=${MINGW_PACKAGE_PREFIX}
ENV PATH="/opt/msys2-cross/wrappers:/opt/msys2-cross/config:${PATH}"
ENV USER=builduser

# Configure Cargo for Rust cross-compilation
RUN mkdir -p /root/.cargo /home/builduser/.cargo \
    && ln -sf /opt/msys2-cross/generated/cargo-cross.toml /root/.cargo/config.toml \
    && ln -sf /opt/msys2-cross/generated/cargo-cross.toml /home/builduser/.cargo/config.toml \
    && chown -R builduser: /home/builduser/.cargo

# Clean up build artifacts
RUN rm -rf /build /tmp/*

RUN mkdir -p /src && chown builduser: /src

USER builduser
WORKDIR /src
CMD ["/bin/bash"]
