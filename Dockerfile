ARG ALPINE_VERSION=3.22
FROM alpine:${ALPINE_VERSION}
ARG TARGETARCH

RUN apk add --no-cache tzdata iproute2 p7zip jq

# Keep the archive in the image and extract it on startup.
RUN mkdir -p /opt/xray/config
COPY ./xray-core/Xray-linux-${TARGETARCH}.7z /opt/xray/xray.7z
COPY ./config.template.json /opt/xray/config.template.json
COPY ./start.sh /opt/start.sh
RUN chmod +x /opt/start.sh && sed -i 's/\r//' /opt/start.sh

ENTRYPOINT ["/opt/start.sh"]
CMD []
