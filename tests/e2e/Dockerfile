ARG XRAY_IMAGE=xray-mikrotik:armv5-local
ARG TEST_PLATFORM=linux/arm/v5
FROM --platform=$TEST_PLATFORM ${XRAY_IMAGE} AS tested
FROM python:3.13-slim
RUN apt-get update && apt-get install -y --no-install-recommends openssl \
    && rm -rf /var/lib/apt/lists/*
COPY --from=tested /opt/xray/xray /opt/xray/xray
COPY . /tests/
ENTRYPOINT ["python3", "/tests/server.py"]
