#!/bin/sh
set -eu
case_name=${1:-native}
export SERVER_ADDRESS=audit-server SERVER_PORT=443
export USER_ID=11111111-1111-4111-8111-111111111111
export ENCRYPTION=none FINGERPRINT_FP=chrome SERVER_NAME_SNI=example.com
export PUBLIC_KEY_PBK=AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
export SHORT_ID_SID=abcdef123456
printf '\n192.0.2.10 audit-server\n' >> /etc/hosts
if [ "$case_name" != network_failure ]; then
    ip link add eth0 type dummy
    ip addr add 172.18.20.6/30 dev eth0
    ip link set eth0 up
    ip route add default via 172.18.20.5
fi
before_dns=$(sha256sum /etc/resolv.conf)
pid=
cleanup() { if [ -n "$pid" ]; then kill "$pid" 2>/dev/null || true; wait "$pid" 2>/dev/null || true; fi; }
trap cleanup EXIT
fail() { echo "FAIL: $*" >&2; cat /tmp/startup.log 2>/dev/null || true; exit 1; }
case "$case_name" in
    empty_shortid) export SHORT_ID_SID='' ;;
    invalid_port) export SERVER_PORT='443,"injected":true' ;;
    invalid_config) export ENCRYPTION=invalid ;;
    escaped_string) export FINGERPRINT_FP='bad"fingerprint';;
    dns_failure) export SERVER_ADDRESS=missing.invalid ;;
esac
/opt/start.sh > /tmp/startup.log 2>&1 &
pid=$!
case "$case_name" in
    invalid_port|invalid_config|escaped_string|dns_failure|network_failure)
        for i in $(seq 1 120); do
            [ -r "/proc/$pid/stat" ] || break
            [ "$(awk '{print $3}' "/proc/$pid/stat")" != Z ] || break
            sleep 0.1
        done
        if kill -0 "$pid" 2>/dev/null && [ "$(awk '{print $3}' "/proc/$pid/stat")" != Z ]; then fail 'bad setup did not stop'; fi
        status=0
        wait "$pid" || status=$?
        pid=
        [ "$status" -ne 0 ] || fail 'bad setup returned success'
        [ "$before_dns" = "$(sha256sum /etc/resolv.conf)" ] || fail 'DNS was modified'
        if [ "$case_name" != network_failure ]; then
            ip -4 route show default | grep -q 'via 172.18.20.5 dev eth0' || fail 'invalid config changed default route'
        fi
        if [ "$case_name" = escaped_string ]; then
            jq -e '.outbounds[0].streamSettings.realitySettings.fingerprint == "bad\"fingerprint"' /opt/xray/config/config.json >/dev/null || fail 'string was not JSON-escaped'
        fi
        ;;
    *)
        for i in $(seq 1 70); do
            [ "$(cat "/proc/$pid/comm" 2>/dev/null || true)" != xray ] || break
            kill -0 "$pid" 2>/dev/null || break
            sleep 0.1
        done
        [ "$(cat "/proc/$pid/comm" 2>/dev/null || true)" = xray ] || fail 'Xray did not replace startup shell'
        for i in $(seq 1 50); do
            [ "$(cat /sys/class/net/tun0/carrier 2>/dev/null || true)" != 1 ] || break
            sleep 0.1
        done
        [ "$(cat /sys/class/net/tun0/carrier 2>/dev/null || true)" = 1 ] || fail 'Xray did not open TUN'
        ip link show dev tun0 | grep -q UP || fail 'TUN is down'
        ip -4 route get 198.18.0.1 | grep -q 'dev tun0' || fail 'traffic does not use TUN'
        ip -4 route get 192.0.2.10 | grep -q 'via 172.18.20.5 dev eth0' || fail 'server route loops into TUN'
        ss -lnt | grep -q ':10800 ' && fail 'SOCKS port is still open'
        [ "$before_dns" = "$(sha256sum /etc/resolv.conf)" ] || fail 'DNS was modified'
        jq -e '.inbounds[0].protocol == "tun" and .outbounds[0].settings.vnext[0].address == "192.0.2.10"' /opt/xray/config/config.json >/dev/null || fail 'wrong TUN/outbound config'
        if [ "$case_name" = exit_status ]; then
            kill -KILL "$pid"
            status=0; wait "$pid" || status=$?; pid=
            [ "$status" -eq 137 ] || fail 'Xray failure status was lost'
        else
            kill -TERM "$pid"
            wait "$pid" || fail 'SIGTERM did not stop Xray cleanly'
            pid=
        fi
        if [ "$case_name" = repeat ]; then
            # Re-run in the same namespace with the previous TUN/default still present.
            /opt/start.sh > /tmp/startup.log 2>&1 & pid=$!
            for i in $(seq 1 70); do
                [ "$(cat "/proc/$pid/comm" 2>/dev/null || true)" != xray ] || break
                sleep 0.1
            done
            [ "$(cat "/proc/$pid/comm" 2>/dev/null || true)" = xray ] || fail 'repeat start failed'
            kill -TERM "$pid"; wait "$pid"; pid=
        fi
        ;;
esac
echo "PASS: $case_name"
