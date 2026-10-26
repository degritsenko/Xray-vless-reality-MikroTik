#!/bin/sh
set -eu
export SERVER_PORT=443 USER_ID=11111111-1111-4111-8111-111111111111
export ENCRYPTION=none FINGERPRINT_FP=chrome SERVER_NAME_SNI=example.com
export PUBLIC_KEY_PBK=$(cat /fixture/public-key) SHORT_ID_SID=abcdef123456
jq '.log.loglevel = "debug"' /opt/xray/config.template.json > /tmp/template.json
cp /tmp/template.json /opt/xray/config.template.json
/opt/start.sh > /tmp/client.log 2>&1 &
pid=$!
trap 'kill "$pid" 2>/dev/null || true' EXIT
for i in $(seq 1 100); do
    [ "$(cat /sys/class/net/tun0/carrier 2>/dev/null || true)" != 1 ] || break
    sleep 0.1
done
ip -4 route get 198.18.0.10 | grep -q 'dev tun0'
if ! python3 - <<'PY'
import socket
import struct
import urllib.request
opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
with opener.open('http://198.18.0.10:8080/', timeout=10) as response:
    assert response.read() == b'TCP_OK'
print('PASS: TCP through native TUN + VLESS/REALITY', flush=True)
query = struct.pack('!6H', 1234, 0x100, 1, 0, 0, 0)
query += b'\x05audit\x04test\x00' + struct.pack('!HH', 1, 1)
sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
sock.settimeout(10)
sock.sendto(query, ('198.18.0.10', 5353))
answer, peer = sock.recvfrom(4096)
assert peer == ('198.18.0.10', 5353)
assert struct.unpack('!6H', answer[:12]) == (1234, 0x8180, 1, 1, 0, 0)
assert answer[12:12+len(query)-12] == query[12:]
assert answer[-4:] == socket.inet_aton('192.0.2.123')
print('PASS: DNS over UDP through native TUN + VLESS/REALITY', flush=True)
PY
then
    cat /tmp/client.log
    ip -s link show tun0
    ip -4 route
    ss -nt
    exit 1
fi
kill -TERM "$pid"
wait "$pid"
trap - EXIT
