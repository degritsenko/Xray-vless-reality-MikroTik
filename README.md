# Xray VLESS + REALITY для MikroTik

RouterOS 7.25 · AMD64 / ARMv5 / ARMv7 / ARM64 · IPv4 · [Docker Hub](https://hub.docker.com/r/gritsenko/xray-mikrotik/tags?name=latest)

### [Как заввернуть трафик в туннель](https://gist.github.com/degritsenko/64bd43e0d854fc730b71a45872be3542)

Команды для новой установки. Уже существующие записи повторно не добавлять. Внешний интерфейс — `wan`.

## 1. Переменные xvr

Подставьте параметры своего сервера. `XRAY_LOG_LEVEL` необязателен, по умолчанию — `warning`. `FLOW` укажите, если он есть в VLESS-ссылке (например, `xtls-rprx-vision`); `SPIDER_X` — если в REALITY-ссылке есть `spx`. Если параметра в ссылке нет, соответствующую переменную не добавляйте. Для пустого Short ID используйте `value=""`.

```routeros
/container/envs/add list=xvr key=SERVER_ADDRESS value="vpn.example.com"
/container/envs/add list=xvr key=SERVER_PORT value="443"
/container/envs/add list=xvr key=USER_ID value="11111111-1111-4111-8111-111111111111"
/container/envs/add list=xvr key=ENCRYPTION value="none"
/container/envs/add list=xvr key=XRAY_LOG_LEVEL value="warning"
/container/envs/add list=xvr key=FLOW value="xtls-rprx-vision"
/container/envs/add list=xvr key=SPIDER_X value="/"
/container/envs/add list=xvr key=FINGERPRINT_FP value="chrome"
/container/envs/add list=xvr key=SERVER_NAME_SNI value="example.com"
/container/envs/add list=xvr key=PUBLIC_KEY_PBK value="REPLACE_WITH_SERVER_PUBLIC_KEY"
/container/envs/add list=xvr key=SHORT_ID_SID value="abcdef123456"
```

## 2. Сеть

`xray-veth` 

```routeros
/interface/veth/add name=xray-veth address=172.18.20.6/30 gateway=172.18.20.5 gateway6=""
/ip/address/add address=172.18.20.5/30 interface=xray-veth comment="Xray container gateway"
```

## 3. NAT

```routeros
/ip/firewall/nat/add chain=srcnat action=masquerade out-interface=xray-veth comment="Traffic to Xray container"
/ip/firewall/nat/add chain=srcnat action=masquerade src-address=172.18.20.6/32 out-interface=wan comment="Xray container internet access"
```

## 4. Контейнер

```routeros
/container/config/set registry-url=https://registry-1.docker.io tmpdir=/docker/tmp
/container/add remote-image=gritsenko/xray-mikrotik:latest hostname=xray-vless interface=xray-veth envlists=xvr dns=8.8.8.8 root-dir=/docker/xray-native-tun logging=yes start-on-boot=yes
/container/print
```



```routeros
/container/start xray-mikrotik
```

## Сборка образа

Для сборки всех архитектур и отправки в свой Docker Hub:

```sh
docker buildx build --platform linux/amd64,linux/arm/v5,linux/arm/v7,linux/arm64 \
  -t <dockerhub-username>/xray-mikrotik:latest --push .
```
