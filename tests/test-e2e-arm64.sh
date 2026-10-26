#!/bin/sh
# A disposable local REALITY server. Only the test image adds Python/OpenSSL.
set -eu
image=${1:-xray-mikrotik:test-arm64}
script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
prefix=xray-tun-test-$$
network=$prefix-network
volume=$prefix-fixture
server=$prefix-server
cleanup() {
    docker rm -f "$server" >/dev/null 2>&1 || true
    docker volume rm "$volume" >/dev/null 2>&1 || true
    docker network rm "$network" >/dev/null 2>&1 || true
}
trap cleanup EXIT INT TERM
docker build --platform linux/arm64 --build-arg "XRAY_IMAGE=$image" \
    -t xray-mikrotik:e2e-arm64 "$script_dir/e2e"
docker network create --internal "$network" >/dev/null
docker volume create "$volume" >/dev/null
docker run -d --platform linux/arm64 --name "$server" --network "$network" \
    -v "$script_dir:/tests:ro" -v "$volume:/fixture" \
    --entrypoint /bin/sh xray-mikrotik:e2e-arm64 /tests/e2e/server.sh >/dev/null
ready=false
for i in $(seq 1 100); do
    if [ "$(docker inspect --format '{{.State.Running}}' "$server")" != true ]; then
        docker logs "$server"; exit 1
    fi
    if docker exec "$server" test -s /fixture/public-key 2>/dev/null; then ready=true; break; fi
    sleep 0.1
done
if [ "$ready" != true ]; then docker logs "$server"; exit 1; fi
server_ip=$(docker inspect --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$server")
if ! docker run --rm --platform linux/arm64 --network "$network" \
    --cap-add NET_ADMIN --device /dev/net/tun \
    -e "SERVER_ADDRESS=$server_ip" -v "$script_dir:/tests:ro" -v "$volume:/fixture:ro" \
    --entrypoint /bin/sh xray-mikrotik:e2e-arm64 /tests/e2e/client.sh; then
    docker logs "$server"
    exit 1
fi
