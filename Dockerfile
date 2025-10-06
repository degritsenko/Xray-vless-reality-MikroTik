ARG ALPINE_VERSION=3.22
FROM alpine:${ALPINE_VERSION}
ARG TARGETARCH

RUN set -ex; \
    apk update && apk add --no-cache tzdata iproute2 p7zip

RUN mkdir /opt/tun2socks/
COPY ./tun2socks/tun2socks-linux-${TARGETARCH}.7z /opt/tun2socks/tun2socks.7z

RUN mkdir /opt/xray/ && mkdir /opt/xray/config/
COPY ./xray-core/Xray-linux-${TARGETARCH}.7z /opt/xray/xray.7z

COPY ./start.sh /opt/start.sh
RUN chmod +x /opt/start.sh && sed -i 's/\r//' /opt/start.sh

RUN sed -i 's/^tty/#tty/' /etc/inittab
ENTRYPOINT ["/opt/start.sh"]
CMD []