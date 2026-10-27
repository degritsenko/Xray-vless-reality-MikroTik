ARG ALPINE_VERSION=3.22
FROM alpine:${ALPINE_VERSION} AS extract
ARG TARGETARCH
RUN apk add --no-cache p7zip
COPY ./xray-core/Xray-linux-${TARGETARCH}.7z /tmp/xray.7z
RUN mkdir -p /out && 7z x /tmp/xray.7z -o/out -y >/dev/null && chmod 755 /out/xray

FROM alpine:${ALPINE_VERSION}
RUN apk add --no-cache tzdata iproute2 jq
RUN mkdir -p /opt/xray/config
COPY --from=extract /out/xray /opt/xray/xray
COPY ./config.template.json /opt/xray/config.template.json
COPY ./start.sh /opt/start.sh
RUN chmod +x /opt/start.sh && sed -i 's/\r//' /opt/start.sh
ENTRYPOINT ["/opt/start.sh"]
CMD []
