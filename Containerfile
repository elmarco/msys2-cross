# MSYS2 Linux Bootstrap — Cross-compilation container for UCRT64
#
# Builds a GCC cross-compiler targeting x86_64-w64-mingw32 (UCRT) from source,
# then sets up makepkg-mingw so MSYS2 MINGW-packages PKGBUILDs can be built
# on Linux without modification.
#
# Usage:
#   podman build -t msys2-cross .
#   podman run -v ./MINGW-packages:/src msys2-cross bash -c \
#       "cd mingw-w64-zlib && makepkg-mingw -sLf"

# ===========================================================================
# Stage 1: Build the cross-toolchain from source
# ===========================================================================
FROM fedora:latest AS toolchain-builder

COPY scripts/ /opt/msys2-cross/scripts/
COPY sources/ /build/sources/
RUN bash /opt/msys2-cross/scripts/00-install-host-deps.sh \
    && bash /opt/msys2-cross/scripts/01-build-binutils.sh \
    && bash /opt/msys2-cross/scripts/02-build-headers.sh \
    && bash /opt/msys2-cross/scripts/03-build-gcc-bootstrap.sh \
    && bash /opt/msys2-cross/scripts/04-build-crt.sh \
    && bash /opt/msys2-cross/scripts/05-build-winpthreads.sh \
    && bash /opt/msys2-cross/scripts/06-build-gcc-final.sh
RUN bash /opt/msys2-cross/scripts/07-build-rust-cross.sh \
    && rm -rf /build

# ===========================================================================
# Stage 2: Assemble the final cross-compilation environment
# ===========================================================================
FROM fedora:latest AS msys2-cross

# Install host build dependencies (split: base + extras)
COPY scripts/common.sh scripts/00-install-host-deps.sh scripts/00-install-extra-deps.sh /opt/msys2-cross/scripts/
RUN bash /opt/msys2-cross/scripts/00-install-host-deps.sh
RUN bash /opt/msys2-cross/scripts/00-install-extra-deps.sh

# Copy cross-toolchain from builder stage (GCC + Rust std)
COPY --from=toolchain-builder /ucrt64 /ucrt64
COPY --from=toolchain-builder /usr/bin/x86_64-w64-mingw32-* /usr/bin/
COPY --from=toolchain-builder /usr/x86_64-w64-mingw32 /usr/x86_64-w64-mingw32
COPY --from=toolchain-builder /usr/lib64/gcc/x86_64-w64-mingw32 /usr/lib64/gcc/x86_64-w64-mingw32
COPY --from=toolchain-builder /usr/libexec/gcc/x86_64-w64-mingw32 /usr/libexec/gcc/x86_64-w64-mingw32
COPY --from=toolchain-builder /usr/lib/rustlib/x86_64-pc-windows-gnu /usr/lib/rustlib/x86_64-pc-windows-gnu

# Recreate sysroot symlinks (include/lib point into /ucrt64)
# Also add build tool wrappers where PKGBUILDs expect them
RUN mkdir -p /usr/x86_64-w64-mingw32 /ucrt64/bin \
    && ln -sfn /ucrt64/include /usr/x86_64-w64-mingw32/include \
    && ln -sfn /ucrt64/lib /usr/x86_64-w64-mingw32/lib \
    && ln -sfn /opt/msys2-cross/wrappers/mingw-cmake /ucrt64/bin/cmake \
    && ln -sfn /opt/msys2-cross/wrappers/mingw-meson /ucrt64/bin/meson \
    && ln -sfn /opt/msys2-cross/wrappers/mingw-meson /ucrt64/bin/meson.exe \
    && ln -sfn /opt/msys2-cross/wrappers/mingw-pkg-config /ucrt64/bin/x86_64-w64-mingw32-pkg-config \
    && ln -sfn /usr/bin/x86_64-w64-mingw32-gcc /ucrt64/bin/cc

# Install build infrastructure
COPY config/ /opt/msys2-cross/config/
COPY wrappers/ /opt/msys2-cross/wrappers/
COPY patches/ /opt/msys2-cross/patches/
COPY packages/ /opt/msys2-cross/packages/
RUN chmod +x /opt/msys2-cross/wrappers/* \
    && chmod +x /opt/msys2-cross/config/makepkg-mingw

# Set up pacman and package the toolchain
COPY scripts/08-setup-pacman.sh /opt/msys2-cross/scripts/
RUN bash /opt/msys2-cross/scripts/08-setup-pacman.sh

# Build base libraries (libiconv, gettext) that MSYS2 packages implicitly need
COPY scripts/09-build-base-libs.sh /opt/msys2-cross/scripts/
RUN bash /opt/msys2-cross/scripts/09-build-base-libs.sh

# Environment setup
ENV MSYSTEM=UCRT64
ENV MINGW_PREFIX=/ucrt64
ENV MINGW_CHOST=x86_64-w64-mingw32
ENV MINGW_PACKAGE_PREFIX=mingw-w64-ucrt-x86_64
ENV PATH="/opt/msys2-cross/wrappers:/opt/msys2-cross/config:${PATH}"

# Configure Cargo for Rust cross-compilation
RUN mkdir -p /root/.cargo /home/builduser/.cargo \
    && ln -sf /opt/msys2-cross/config/cargo-cross.toml /root/.cargo/config.toml \
    && ln -sf /opt/msys2-cross/config/cargo-cross.toml /home/builduser/.cargo/config.toml \
    && chown -R builduser: /home/builduser/.cargo

# Clean up build artifacts
RUN rm -rf /build /tmp/*

RUN mkdir -p /src && chown builduser: /src

USER builduser
WORKDIR /src
CMD ["/bin/bash"]
