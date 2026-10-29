"""Runs in a sidecar sharing the final ARMv5 client's network namespace."""
import socket
import struct
import urllib.request

opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
with opener.open('http://198.18.0.10:8080/', timeout=15) as response:
    assert response.read() == b'TCP_OK'
print('PASS: TCP/HTTP through ARMv5 native TUN + VLESS/REALITY', flush=True)
query = struct.pack('!6H', 1234, 0x100, 1, 0, 0, 0)
query += b'\x05audit\x04test\x00' + struct.pack('!HH', 1, 1)
with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
    sock.settimeout(15)
    sock.sendto(query, ('198.18.0.10', 5353))
    answer, peer = sock.recvfrom(4096)
assert peer == ('198.18.0.10', 5353)
assert struct.unpack('!6H', answer[:12]) == (1234, 0x8180, 1, 1, 0, 0)
assert answer[12:len(query)] == query[12:]
assert answer[-4:] == socket.inet_aton('192.0.2.123')
print('PASS: DNS/UDP through ARMv5 native TUN + VLESS/REALITY', flush=True)
