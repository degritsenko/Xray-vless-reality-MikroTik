# Xray VLESS + REALITY для MikroTik

RouterOS 7.25 · AMD64 / ARMv7 / ARM64 · IPv4 · [Docker Hub](https://hub.docker.com/r/gritsenko/xray-mikrotik/tags?name=latest)

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
