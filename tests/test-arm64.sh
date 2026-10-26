#!/bin/sh
# The image must already be built from this checkout for linux/arm64.
set -eu
image=${1:-xray-mikrotik:test-arm64}
script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
for case_name in native empty_shortid invalid_port invalid_config escaped_string dns_failure network_failure repeat exit_status; do
    docker run --rm --platform linux/arm64 --network none \
        --cap-add NET_ADMIN --device /dev/net/tun \
        -v "$script_dir/check-arm64.sh:/tests/check-arm64.sh:ro" \
        --entrypoint /bin/sh "$image" /tests/check-arm64.sh "$case_name"
done
