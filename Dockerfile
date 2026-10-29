# syntax=docker/dockerfile:1
ARG ALPINE_VERSION=3.22
ARG TARGETARCH
ARG TARGETVARIANT

FROM --platform=$BUILDPLATFORM alpine:3.22 AS extract
ARG TARGETARCH
ARG TARGETVARIANT
ARG XRAY_VERSION=26.9.9
RUN apk add --no-cache ca-certificates curl unzip
COPY build/xray-checksums.txt /tmp/checksums
RUN set -eu; \
    case "$TARGETARCH/$TARGETVARIANT" in \
      amd64/) asset=Xray-linux-64.zip ;; \
      arm64/|arm64/v8) asset=Xray-linux-arm64-v8a.zip ;; \
      arm/v7) asset=Xray-linux-arm32-v7a.zip ;; \
      arm/v5) asset=Xray-linux-arm32-v5.zip ;; \
      *) echo "Unsupported platform: $TARGETARCH/$TARGETVARIANT" >&2; exit 1 ;; \
    esac; \
    checksum=$(awk -v asset="$asset" '$2 == asset {print $1}' /tmp/checksums); \
    test -n "$checksum"; \
    curl -fsSL --retry 3 "https://github.com/XTLS/Xray-core/releases/download/v${XRAY_VERSION}/${asset}" -o /tmp/xray.zip; \
    echo "$checksum  /tmp/xray.zip" | sha256sum -c -; \
    mkdir /out; unzip -j /tmp/xray.zip xray LICENSE -d /out; chmod 755 /out/xray

FROM busybox:1.38.0-glibc AS busybox-base

FROM --platform=$BUILDPLATFORM debian:trixie-slim AS busybox-toolchain
RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
       gcc libc6-dev gcc-arm-linux-gnueabi make libc6-dev-armel-cross \
       ca-certificates curl bzip2 \
    && rm -rf /var/lib/apt/lists/*

FROM busybox-toolchain AS busybox-build
ARG BUSYBOX_SHA256=34f9ea6ff8636f2c9241153b9114eefa9e65674a45318ae1ef95bb5f31c53bb2
WORKDIR /src
RUN curl -fsSL --connect-timeout 20 --max-time 120 --retry 3 \
      https://busybox.net/downloads/busybox-1.38.0.tar.bz2 -o busybox.tar.bz2 \
    && echo "$BUSYBOX_SHA256  busybox.tar.bz2" | sha256sum -c - \
    && tar -xjf busybox.tar.bz2 --strip-components=1
RUN make defconfig >/dev/null \
    && sed -i -E 's/^CONFIG_(DPKG|DPKG_DEB|RPM|RPM2CPIO|TC|WERROR)=y/# CONFIG_\1 is not set/' .config \
    && make oldconfig </dev/null >/dev/null \
    && make -j4 CROSS_COMPILE=arm-linux-gnueabi- \
         EXTRA_CFLAGS="-march=armv5te -mfloat-abi=soft" busybox \
    && mkdir -p /out \
    && cp busybox .config LICENSE AUTHORS /out/ \
    && cp /usr/share/doc/libgcc-14-dev-armel-cross/copyright /out/GCC-runtime-copyright

FROM debian:trixie-slim AS armv5-packages
# Python/binutils are collection/audit tools and never enter the runtime.
RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
       iproute2 jq libc-bin ca-certificates tzdata python3 binutils \
    && rm -rf /var/lib/apt/lists/*
COPY --from=busybox-build /out/busybox /tmp/busybox
COPY build/collect-runtime.py /tmp/collect-runtime.py
RUN python3 /tmp/collect-runtime.py

FROM busybox-base AS base-armv5
# Replace all hardlinked applets, so no original binary retains dpkg code.
# Use one coherent Debian glibc set; no Debian rootfs is ever copied.
RUN rm -rf /bin /lib/lib*.so* /lib/ld-linux.so.3
COPY --from=busybox-build /out/busybox /bin/busybox
COPY --from=armv5-packages /runtime/ /
RUN ["/bin/busybox", "--install", "-s", "/bin"]
COPY --from=busybox-build /out/LICENSE /out/AUTHORS /out/GCC-runtime-copyright /usr/share/licenses/busybox/
COPY --from=busybox-build /out/.config /usr/share/licenses/busybox/build.config
COPY build/busybox-NOTICE /usr/share/licenses/busybox/NOTICE
ENV PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
RUN /bin/busybox true && getent hosts localhost && jq -en '1 + 1 == 2' \
    && ip -j link show >/dev/null

FROM alpine:${ALPINE_VERSION} AS alpine-base
RUN apk add --no-cache tzdata iproute2 jq ca-certificates
FROM alpine-base AS base-amd64
FROM alpine-base AS base-arm64
FROM alpine-base AS base-arm64v8
FROM alpine-base AS base-armv7

FROM base-${TARGETARCH}${TARGETVARIANT} AS runtime
RUN mkdir -p /opt/xray/config /tmp /run && chmod 1777 /tmp
COPY --from=extract /out/xray /opt/xray/xray
COPY --from=extract /out/LICENSE /usr/share/licenses/xray/LICENSE
COPY --chmod=755 ./start.sh /opt/start.sh
RUN sed -i 's/\r//' /opt/start.sh && /opt/xray/xray version
ENTRYPOINT ["/opt/start.sh"]
CMD []
