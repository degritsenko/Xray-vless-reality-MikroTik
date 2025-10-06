Тут инструкция, как завести контейнер c xray-vless туннелем, который можно подключать к 3x-ui панели. Как заворачивать траффик в тунель можно почитать [тут](https://gist.github.com/degritsenko/64bd43e0d854fc730b71a45872be3542).
Собранные образы можно взять на [docker hub](https://hub.docker.com/r/gritsenko/xray-mikrotik)

```
/container/config set registry-url=https://registry-1.docker.io tmpdir=/docker/tmp

/container envs
add key=SERVER_ADDRESS    name=xvr value=example.com
add key=SERVER_PORT       name=xvr value=443
add key=USER_ID           name=xvr value=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
add key=ENCRYPTION        name=xvr value=none
add key=FINGERPRINT_FP    name=xvr value=chrome
add key=SERVER_NAME_SNI   name=xvr value=google.com
add key=PUBLIC_KEY_PBK    name=xvr value=AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
add key=SHORT_ID_SID      name=xvr value=abcdef123456

/interface veth add address=172.18.20.6/30 gateway=172.18.20.5 gateway6="" name=xray-vless
/ip address add interface=xray-vless address=172.18.20.5/30
/ip firewall nat add action=masquerade chain=srcnat out-interface=xray-vless

/container/add remote-image=gritsenko/xray-mikrotik:latest hostname=xray-vless interface=xray-vless logging=no start-on-boot=yes envlist=xvr root-dir=/docker/container-xray-mikrotik dns=172.18.20.5
```

Как собирать для разных архитектур:
```
docker buildx build --platform linux/amd64,linux/arm64,linux/arm/v7 -t username/xray-mikrotik:latest --push .
```