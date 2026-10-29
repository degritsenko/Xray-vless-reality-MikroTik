#!/bin/sh
set -eu
/opt/xray/xray version
test "$(stat -c %a /tmp)" = 1777
test "$(command -v ip)" = /usr/bin/ip
test "$(command -v jq)" = /usr/bin/jq
jq -en --argjson port 443 '{port: $port} | .port == 443'
getent ahostsv4 localhost
ip -j link show | jq -e 'length > 0'
TZ=Europe/Moscow date +%z | grep -qx '+0300'
test -s /etc/ssl/certs/ca-certificates.crt
test -s /usr/share/licenses/xray/LICENSE
test -s /usr/share/licenses/libc6/copyright
for tool in apt apt-get dpkg python3 readelf gcc curl; do
    if command -v "$tool" >/dev/null 2>&1; then
        echo "Unexpected runtime tool: $tool" >&2; exit 1
    fi
done
for applet in dpkg dpkg-deb rpm rpm2cpio; do
    if /bin/busybox --list | grep -qx "$applet"; then
        echo "Unexpected compiled package-manager applet: $applet" >&2; exit 1
    fi
done
test ! -d /var/lib/dpkg
test ! -d /var/lib/apt
test ! -d /var/cache/apt
test ! -e /tmp/collect-runtime.py
echo 'PASS: BusyBox, Debian utilities, DNS/NSS, JSON, timezone, CA and runtime contents'
