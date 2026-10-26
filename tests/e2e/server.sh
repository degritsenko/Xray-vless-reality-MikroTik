#!/bin/sh
set -eu
mkdir -p /tmp/xray
7z x /opt/xray/xray.7z -o/tmp/xray -y >/dev/null
chmod +x /tmp/xray/xray
openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 \
    -nodes -days 1 -subj /CN=example.com \
    -keyout /tmp/fallback.key -out /tmp/fallback.crt 2>/dev/null
/tmp/xray/xray x25519 > /tmp/keys
private_key=$(awk '/PrivateKey:/ {print $2}' /tmp/keys)
public_key=$(awk '/^Password/ {print $NF}' /tmp/keys)
[ -n "$private_key" ] && [ -n "$public_key" ]
jq -n --arg key "$private_key" '{
  log: {loglevel: "debug"},
  inbounds: [{port: 443, protocol: "vless",
    settings: {clients: [{id: "11111111-1111-4111-8111-111111111111"}], decryption: "none"},
    streamSettings: {network: "tcp", security: "reality", realitySettings: {
      dest: "127.0.0.1:8443", serverNames: ["example.com"],
      privateKey: $key, shortIds: ["abcdef123456"]
    }}
  }],
  outbounds: [
    {tag: "tcp", protocol: "freedom", settings: {redirect: "127.0.0.1:8080", finalRules: [{action: "allow", ip: ["127.0.0.1/32"], port: "8080"}]}},
    {tag: "udp", protocol: "freedom", settings: {redirect: "127.0.0.1:5353", finalRules: [{action: "allow", ip: ["127.0.0.1/32"], port: "5353"}]}}
  ],
  routing: {rules: [{type: "field", network: "udp", outboundTag: "udp"}]}
}' > /tmp/server.json
python3 /tests/e2e/services.py &
/tmp/xray/xray run -config /tmp/server.json &
pid=$!
sleep 1
kill -0 "$pid"
printf '%s\n' "$public_key" > /fixture/public-key
wait "$pid"
