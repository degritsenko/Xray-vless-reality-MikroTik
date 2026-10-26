#!/bin/sh
set -eu

fail() {
    echo "Startup failed: $*" >&2
    exit 1
}

: "${SERVER_ADDRESS:?Environment variable SERVER_ADDRESS not set}"
: "${SERVER_PORT:?Environment variable SERVER_PORT not set}"
: "${USER_ID:?Environment variable USER_ID not set}"
: "${ENCRYPTION:?Environment variable ENCRYPTION not set}"
: "${FINGERPRINT_FP:?Environment variable FINGERPRINT_FP not set}"
: "${SERVER_NAME_SNI:?Environment variable SERVER_NAME_SNI not set}"
: "${PUBLIC_KEY_PBK:?Environment variable PUBLIC_KEY_PBK not set}"
: "${SHORT_ID_SID?Environment variable SHORT_ID_SID not set}"

SERVER_PORT=$(jq -en --arg value "$SERVER_PORT" \
    '$value | select(test("^[0-9]+$")) | tonumber | select(. >= 1 and . <= 65535)') \
    || fail "SERVER_PORT must be an integer between 1 and 65535"

# Use the DNS configuration supplied by RouterOS; do not rewrite resolv.conf.
SERVER_IP_ADDRESS=$(getent ahostsv4 "$SERVER_ADDRESS" | awk '{print $1; exit}')
[ -n "$SERVER_IP_ADDRESS" ] \
    || fail "Cannot resolve an IPv4 address for $SERVER_ADDRESS; check the container DNS"

# On a repeated start, the existing server /32 route still identifies the uplink.
SERVER_ROUTE=$(ip -4 -j route get "$SERVER_IP_ADDRESS")
NET_IFACE=$(printf '%s' "$SERVER_ROUTE" | jq -er '.[0].dev | select(. != null and . != "tun0")') \
    || fail "Cannot determine the physical interface for $SERVER_IP_ADDRESS"
NET_GATEWAY=$(printf '%s' "$SERVER_ROUTE" | jq -r '.[0].gateway // empty')

# Keep the existing archive extraction/cache behavior.
mkdir -p /tmp/xray
if [ ! -f /tmp/xray/xray ]; then
    7z x /opt/xray/xray.7z -o/tmp/xray -y >/dev/null \
        || fail "Cannot extract /opt/xray/xray.7z"
    chmod 755 /tmp/xray/xray
fi

umask 077
mkdir -p /opt/xray/config
jq --arg server "$SERVER_IP_ADDRESS" --arg iface "$NET_IFACE" --argjson port "$SERVER_PORT" '
    .outbounds[0].settings.vnext[0] |= (
        .address = $server |
        .port = $port |
        .users[0].id = env.USER_ID |
        .users[0].encryption = env.ENCRYPTION
    ) |
    .outbounds[0].streamSettings.realitySettings |= (
        .fingerprint = env.FINGERPRINT_FP |
        .serverName = env.SERVER_NAME_SNI |
        .publicKey = env.PUBLIC_KEY_PBK |
        .shortId = env.SHORT_ID_SID
    ) |
    .outbounds[0].streamSettings.sockopt.interface = $iface
' /opt/xray/config.template.json > /opt/xray/config/config.json

# Reject bad configurations before changing any routes.
/tmp/xray/xray run -test -config /opt/xray/config/config.json \
    || fail "Xray configuration is invalid"

# Create a persistent TUN that Xray will open by name when it starts.
if ip link show dev tun0 >/dev/null 2>&1; then
    ip tuntap del dev tun0 mode tun
fi
ip tuntap add dev tun0 mode tun
ip addr add 172.31.200.10/30 dev tun0
ip link set dev tun0 up

# Pin the same IPv4 used in the Xray outbound before switching the default.
if [ -n "$NET_GATEWAY" ]; then
    ip -4 route replace "$SERVER_IP_ADDRESS/32" via "$NET_GATEWAY" dev "$NET_IFACE"
else
    ip -4 route replace "$SERVER_IP_ADDRESS/32" dev "$NET_IFACE"
fi
ip -4 route replace default dev tun0

exec /tmp/xray/xray run -config /opt/xray/config/config.json
