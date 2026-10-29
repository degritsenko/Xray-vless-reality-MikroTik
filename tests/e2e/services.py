"""Local TCP, DNS/UDP and TLS fallback fixtures; no internet required."""
import http.server
import socket
import ssl
import struct
import threading


class HTTP(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header('Content-Length', '6')
        self.end_headers()
        self.wfile.write(b'TCP_OK')

    def log_message(self, *_):
        pass


def dns_server():
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.bind(('127.0.0.1', 5353))
    while True:
        query, peer = sock.recvfrom(4096)
        # One A answer for the question supplied by the client.
        response = query[:2] + struct.pack('!5H', 0x8180, 1, 1, 0, 0)
        response += query[12:] + b'\xc0\x0c' + struct.pack('!HHIH', 1, 1, 60, 4)
        sock.sendto(response + socket.inet_aton('192.0.2.123'), peer)


def tls_server():
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    context.minimum_version = ssl.TLSVersion.TLSv1_3
    context.set_alpn_protocols(['h2', 'http/1.1'])
    context.load_cert_chain('/tmp/fallback.crt', '/tmp/fallback.key')
    listener = socket.socket()
    listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    listener.bind(('127.0.0.1', 8443))
    listener.listen()
    while True:
        conn, _ = listener.accept()
        try:
            with context.wrap_socket(conn, server_side=True) as tls:
                tls.settimeout(2)
                tls.recv(4096)
        except (OSError, ssl.SSLError):
            conn.close()


threading.Thread(target=dns_server, daemon=True).start()
threading.Thread(target=tls_server, daemon=True).start()
http.server.HTTPServer(('127.0.0.1', 8080), HTTP).serve_forever()
