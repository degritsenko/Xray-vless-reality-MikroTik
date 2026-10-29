"""Disposable local REALITY server; the tested client needs no test tools."""
import json
from pathlib import Path
import subprocess
import time

xray = '/opt/xray/xray'
subprocess.run(['openssl', 'req', '-x509', '-newkey', 'ec', '-pkeyopt',
                'ec_paramgen_curve:prime256v1', '-nodes', '-days', '1',
                '-subj', '/CN=example.com', '-keyout', '/tmp/fallback.key',
                '-out', '/tmp/fallback.crt'], check=True)
keys = subprocess.check_output([xray, 'x25519'], text=True)
private = next(line.split()[-1] for line in keys.splitlines() if line.startswith('PrivateKey:'))
public = next(line.split()[-1] for line in keys.splitlines() if line.startswith('Password'))
config = {
    'log': {'loglevel': 'warning'},
    'inbounds': [{'port': 443, 'protocol': 'vless',
        'settings': {'clients': [{'id': '11111111-1111-4111-8111-111111111111'}],
                     'decryption': 'none'},
        'streamSettings': {'network': 'tcp', 'security': 'reality',
            'realitySettings': {'dest': '127.0.0.1:8443', 'serverNames': ['example.com'],
                'privateKey': private, 'shortIds': ['abcdef123456']}}}],
    'outbounds': [
        {'tag': 'tcp', 'protocol': 'freedom', 'settings': {
            'redirect': '127.0.0.1:8080',
            'finalRules': [{'action': 'allow', 'ip': ['127.0.0.1/32'], 'port': '8080'}]}},
        {'tag': 'udp', 'protocol': 'freedom', 'settings': {
            'redirect': '127.0.0.1:5353',
            'finalRules': [{'action': 'allow', 'ip': ['127.0.0.1/32'], 'port': '5353'}]}}],
    'routing': {'rules': [{'type': 'field', 'network': 'udp', 'outboundTag': 'udp'}]}}
Path('/tmp/server.json').write_text(json.dumps(config))
services = subprocess.Popen(['python3', '/tests/services.py'])
server = subprocess.Popen([xray, 'run', '-config', '/tmp/server.json'])
time.sleep(1)
assert server.poll() is None and services.poll() is None
Path('/tmp/public-key').write_text(public)
raise SystemExit(server.wait())
