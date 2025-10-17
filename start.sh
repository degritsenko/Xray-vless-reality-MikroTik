#!/bin/sh
echo "Starting setup container please wait"

cleanup() {
    echo "Stopping Xray and tun2socks"
    killall xray 2>/dev/null
    killall tun2socks 2>/dev/null
    exit 0
}
trap cleanup SIGTERM

# Проверка обязательных переменных окружения
: "${SERVER_ADDRESS:?Environment variable SERVER_ADDRESS not set}"
: "${SERVER_PORT:?Environment variable SERVER_PORT not set}"
: "${USER_ID:?Environment variable USER_ID not set}"
: "${ENCRYPTION:?Environment variable ENCRYPTION not set}"
: "${FINGERPRINT_FP:?Environment variable FINGERPRINT_FP not set}"
: "${SERVER_NAME_SNI:?Environment variable SERVER_NAME_SNI not set}"
: "${PUBLIC_KEY_PBK:?Environment variable PUBLIC_KEY_PBK not set}"
: "${SHORT_ID_SID:?Environment variable SHORT_ID_SID not set}"

# Разрешение IP сервера
SERVER_IP_ADDRESS=$(getent hosts "$SERVER_ADDRESS" | awk '{print $1; exit}' || true)
if [ -z "$SERVER_IP_ADDRESS" ]; then
  echo "Failed to resolve $SERVER_ADDRESS"
  echo "Please configure DNS on Mikrotik"
  exit 1
fi

# Определение интерфейса
NET_IFACE=$(ip -o link show | awk -F': ' '{print $2}' | grep -vE '^lo|^tun0' | head -n1 | cut -d'@' -f1)

# Настройка туннеля
ip tuntap del mode tun dev tun0 2>/dev/null
ip tuntap add mode tun dev tun0
ip addr add 172.31.200.10/30 dev tun0
ip link set dev tun0 up
ip route del default via 172.18.20.5 2>/dev/null
ip route add default via 172.31.200.10
ip route add "$SERVER_IP_ADDRESS/32" via 172.18.20.5

# Настройка DNS
rm -f /etc/resolv.conf
echo "nameserver 172.18.20.5" > /etc/resolv.conf

# Создание конфига Xray
mkdir -p /opt/xray/config
cat <<EOF > /opt/xray/config/config.json
{
  "log": {
    "access": "none",
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "port": 10800,
      "listen": "0.0.0.0",
      "protocol": "socks",
      "settings": {
        "udp": true
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls", "quic"],
        "routeOnly": true
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "vless",
      "settings": {
        "vnext": [
          {
            "address": "$SERVER_ADDRESS",
            "port": $SERVER_PORT,
            "users": [
              {
                "id": "$USER_ID",
                "encryption": "$ENCRYPTION",
                "alterId": 0
              }
            ]
          }
        ]
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "fingerprint": "$FINGERPRINT_FP",
          "serverName": "$SERVER_NAME_SNI",
          "publicKey": "$PUBLIC_KEY_PBK",
          "spiderX": "",
          "shortId": "$SHORT_ID_SID"
        }
      },
      "tag": "proxy"
    }
  ]
}
EOF

# --- Распаковка бинарников во временный каталог ---
echo "Preparing binaries in /tmp"
mkdir -p /tmp/xray /tmp/tun2socks

if [ ! -f /tmp/xray/xray ]; then
    7z x /opt/xray/xray.7z -o/tmp/xray -y >/dev/null || {
        echo "Failed to extract /opt/xray/xray.7z"
        exit 1
    }
    chmod 755 /tmp/xray/xray
fi

if [ ! -f /tmp/tun2socks/tun2socks ]; then
    7z x /opt/tun2socks/tun2socks.7z -o/tmp/tun2socks -y >/dev/null || {
        echo "Failed to extract /opt/tun2socks/tun2socks.7z"
        exit 1
    }
    chmod 755 /tmp/tun2socks/tun2socks
fi

# --- Запуск ---
echo "Starting Xray core"
/tmp/xray/xray run -config /opt/xray/config/config.json &

echo "Starting tun2socks"
/tmp/tun2socks/tun2socks -loglevel silent -device tun0 -proxy socks5://127.0.0.1:10800 -interface "$NET_IFACE" &

wait -n