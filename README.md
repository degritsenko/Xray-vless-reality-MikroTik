# Xray VLESS + REALITY для MikroTik

RouterOS 7.25 · AMD64 / ARMv5 / ARMv7 / ARM64 · IPv4 · [Docker Hub](https://hub.docker.com/r/gritsenko/xray-mikrotik/tags?name=latest)

Команды для новой установки. Уже существующие записи повторно не добавлять. Внешний интерфейс — `wan`.

## 1. Переменные xvr

Подставьте параметры своего сервера. Для пустого Short ID используйте `value=""`.

```routeros
/container/envs/add list=xvr key=SERVER_ADDRESS value="vpn.example.com"
/container/envs/add list=xvr key=SERVER_PORT value="443"
/container/envs/add list=xvr key=USER_ID value="11111111-1111-4111-8111-111111111111"
/container/envs/add list=xvr key=ENCRYPTION value="none"
/container/envs/add list=xvr key=FINGERPRINT_FP value="chrome"
/container/envs/add list=xvr key=SERVER_NAME_SNI value="example.com"
/container/envs/add list=xvr key=PUBLIC_KEY_PBK value="REPLACE_WITH_SERVER_PUBLIC_KEY"
/container/envs/add list=xvr key=SHORT_ID_SID value="abcdef123456"
```

## 2. Сеть

`xray-veth` не включать в мост.

```routeros
/interface/veth/add name=xray-veth address=172.18.20.6/30 gateway=172.18.20.5 gateway6=""
/ip/address/add address=172.18.20.5/30 interface=xray-veth comment="Xray container gateway"
```

## 3. DNS и NAT

DNS-правила должны находиться перед запретом input. В `place-before` указан комментарий запрещающего правила — замените его, если у вас он другой.

```routeros
/ip/dns/set allow-remote-requests=yes
/ip/firewall/filter/add chain=input action=accept in-interface=xray-veth src-address=172.18.20.6 dst-address=172.18.20.5 protocol=udp dst-port=53 place-before=[find where chain=input and comment="drop all not coming from LAN"] comment="container -> local DNS (UDP/53)"
/ip/firewall/filter/add chain=input action=accept in-interface=xray-veth src-address=172.18.20.6 dst-address=172.18.20.5 protocol=tcp dst-port=53 place-before=[find where chain=input and comment="drop all not coming from LAN"] comment="container -> local DNS (TCP/53)"
# LAN -> Xray: обратный трафик возвращается через 172.18.20.5
/ip/firewall/nat/add chain=srcnat action=masquerade out-interface=xray-veth comment="Traffic to Xray container"
# Xray -> WAN: выход контейнера к VPN-серверу
/ip/firewall/nat/add chain=srcnat action=masquerade src-address=172.18.20.6/32 out-interface=wan comment="Xray container internet access"
```

## 4. Контейнер

```routeros
/container/config/set registry-url=https://registry-1.docker.io tmpdir=/docker/tmp
/container/add remote-image=gritsenko/xray-mikrotik:latest hostname=xray-vless interface=xray-veth envlists=xvr dns=172.18.20.5 root-dir=/docker/xray-native-tun logging=yes start-on-boot=yes
/container/print
```

После окончания загрузки запустите контейнер по его номеру, например `0`:

```routeros
/container/start 0
```

## Локальная сборка ARMv5

```sh
docker buildx build --platform linux/arm/v5 -t xray-mikrotik:armv5-local --load .
python3 tests/test-armv5.py xray-mikrotik:armv5-local
```

Для ARMv5 Dockerfile использует `debian:trixie-slim` как промежуточную стадию и `busybox:1.38.0-glibc` как финальную базу. Xray 26.9.9 скачивается из официального релиза для выбранной архитектуры с проверкой SHA256; хранить архивы бинарников в репозитории не требуется.

Из Debian переносятся `ip`, `jq`, `getent`, рекурсивные ELF-зависимости и загрузчик, CA-сертификаты, часовые пояса, конфиги iproute2 и лицензии. BusyBox 1.38.0 пересобирается в отдельной build-стадии для ARMv5TE/soft-float без встроенных `dpkg`, `dpkg-deb`, `rpm` и `rpm2cpio`; все исходные hardlink-апплеты базы заменяются. BusyBox использует тот же набор glibc, что и утилиты Debian. `PATH` отдаёт приоритет утилитам Debian; `/tmp` имеет права `1777`. Пакетные менеджеры, Python, binutils и кеши остаются в промежуточной стадии. Сборки AMD64, ARMv7 и ARM64 продолжают использовать Alpine.

Тест запускает исходный entrypoint в финальном ARMv5-образе, проверяет DNS, конфигурацию, TUN, TCP/UDP через локальный VLESS/REALITY-сервер и корректную остановку. Тестовые Python/OpenSSL находятся в отдельном образе. Нужны Docker с ARM-эмуляцией, `NET_ADMIN` и `/dev/net/tun`; MikroTik и внешние VPN-серверы тест не меняет.

Для измерения слоёв через OCI:

```sh
mkdir -p artifacts/armv5
docker buildx build --platform linux/arm/v5 --provenance=false \
  --output type=oci,dest=artifacts/armv5/image.oci.tar,compression=gzip,force-compression=true .
python3 build/inspect-oci.py artifacts/armv5/image.oci.tar artifacts/armv5
```

`sizes.json` содержит сжатые и распакованные размеры tar-слоёв; `inventory.txt` — полный состав объединённой файловой системы, включая права и ссылки. Локальная сборка не публикует ARMv5 в Docker Hub и не меняет удалённый `latest`.
