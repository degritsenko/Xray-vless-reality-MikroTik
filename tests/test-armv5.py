"""Functional integration test; creates and cleans up only its own containers."""
import json
from pathlib import Path
import subprocess
import sys
import time
import uuid

image = sys.argv[1] if len(sys.argv) > 1 else 'xray-mikrotik:armv5-local'
tests = Path(__file__).resolve().parent
prefix = 'xray-v5-test-' + uuid.uuid4().hex[:10]
network, server, client = (prefix + suffix for suffix in ('-net', '-server', '-client'))
fixture = 'xray-mikrotik:armv5-test-tools'


def docker(*args, check=True):
    result = subprocess.run(['docker', *map(str, args)], text=True,
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    if check and result.returncode:
        raise RuntimeError(f'docker {args}:\n{result.stdout}')
    return result


try:
    print(docker('run', '--rm', '--platform', 'linux/arm/v5', '-e', 'QEMU_CPU=arm926',
                 '-v', f'{tests}:/tests:ro', '--entrypoint', '/bin/sh', image,
                 '/tests/runtime.sh').stdout, flush=True)
    docker('build', '--build-arg', f'XRAY_IMAGE={image}', '-t', fixture, tests / 'e2e')
    docker('network', 'create', network)
    docker('run', '-d', '--name', server, '--network', network,
           '--network-alias', 'reality-server', fixture)
    public = ''
    for _ in range(150):
        result = docker('exec', server, 'cat', '/tmp/public-key', check=False)
        if result.returncode == 0:
            public = result.stdout.strip()
            break
        assert docker('inspect', '-f', '{{.State.Running}}', server).stdout.strip() == 'true', \
            'REALITY fixture exited'
        time.sleep(0.2)
    assert public, 'REALITY fixture did not start'
    env = {'SERVER_ADDRESS': 'reality-server', 'SERVER_PORT': '443',
           'USER_ID': '11111111-1111-4111-8111-111111111111', 'ENCRYPTION': 'none',
           'FINGERPRINT_FP': 'chrome', 'SERVER_NAME_SNI': 'example.com',
           'PUBLIC_KEY_PBK': public, 'SHORT_ID_SID': 'abcdef123456'}
    args = [part for key, value in env.items() for part in ('-e', f'{key}={value}')]
    for key, value, message in (
            ('SERVER_PORT', '70000', 'SERVER_PORT must be an integer'),
            ('PUBLIC_KEY_PBK', 'invalid-key', 'Xray configuration is invalid')):
        invalid = dict(env, **{key: value})
        invalid_args = [part for name, setting in invalid.items()
                        for part in ('-e', f'{name}={setting}')]
        result = docker('run', '--rm', '--platform', 'linux/arm/v5', '--network', network,
                        '-e', 'QEMU_CPU=arm926', *invalid_args, '--entrypoint', '/bin/sh', image,
                        '-c', 'before=$(ip -j route); '
                        'if /opt/start.sh >/tmp/rejected.log 2>&1; then exit 1; fi; '
                        'cat /tmp/rejected.log; '
                        f'grep -q "{message}" /tmp/rejected.log && '
                        'test "$before" = "$(ip -j route)" && '
                        'test ! -e /sys/class/net/tun0')
        print(f'PASS: reject invalid {key} before changing routes', flush=True)
    docker('run', '-d', '--platform', 'linux/arm/v5', '--name', client,
           '--network', network, '--cap-add', 'NET_ADMIN', '--device', '/dev/net/tun',
           '-e', 'QEMU_CPU=arm926', *args, image)
    for _ in range(150):
        result = docker('exec', client, 'cat', '/sys/class/net/tun0/carrier', check=False)
        if result.returncode == 0 and result.stdout.strip() == '1':
            break
        time.sleep(0.2)
    else:
        raise AssertionError('ARMv5 client did not open TUN')
    config = json.loads(docker('exec', client, 'cat', '/opt/xray/config/config.json').stdout)
    assert config['inbounds'][0]['protocol'] == 'tun'
    assert config['outbounds'][0]['streamSettings']['sockopt']['interface'] == 'eth0'
    assert config['outbounds'][0]['settings']['vnext'][0]['address'].count('.') == 3
    print('PASS: actual entrypoint, Docker DNS hostname, generated configuration and TUN startup', flush=True)
    route = json.loads(docker('exec', client, 'ip', '-4', '-j', 'route', 'get', '198.18.0.10').stdout)
    assert route[0]['dev'] == 'tun0'
    print(docker('run', '--rm', '--network', f'container:{client}',
                 '--entrypoint', 'python3', fixture, '/tests/probe.py').stdout, flush=True)
    docker('stop', '-t', '5', client)
    state = json.loads(docker('inspect', client).stdout)[0]['State']
    assert state['ExitCode'] == 0, state
    print('PASS: clean SIGTERM shutdown', flush=True)
except BaseException:
    for name in (server, client):
        print(docker('logs', name, check=False).stdout, file=sys.stderr)
    raise
finally:
    docker('rm', '-f', client, server, check=False)
    docker('network', 'rm', network, check=False)
