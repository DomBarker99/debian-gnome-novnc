#!/usr/bin/env python3
"""Authenticate over RFB and verify a real, nonblank desktop framebuffer."""
import os
from pathlib import Path
import socket
import struct
import subprocess
from PIL import Image

password = os.environ['VNC_TEST_PASSWORD'].encode('ascii')
assert len(password) == 8

def receive(sock, length):
    result = bytearray()
    while len(result) < length:
        part = sock.recv(length - len(result))
        if not part:
            raise RuntimeError('VNC connection closed unexpectedly')
        result.extend(part)
    return bytes(result)

with socket.create_connection(('127.0.0.1', 5901), timeout=20) as sock:
    version = receive(sock, 12)
    assert version.startswith(b'RFB 003.'), version
    sock.sendall(b'RFB 003.008\n')
    count = receive(sock, 1)[0]
    assert count, 'VNC server reported no security types'
    types = receive(sock, count)
    assert 2 in types and 1 not in types, 'VNC must require password authentication'
    sock.sendall(b'\x02')
    challenge = receive(sock, 16)
    key = bytes(int(f'{byte:08b}'[::-1], 2) for byte in password)
    encrypted = subprocess.run(
        ['openssl', 'enc', '-des-ecb', '-provider', 'default', '-provider', 'legacy',
         '-nosalt', '-nopad', '-K', key.hex()],
        input=challenge, capture_output=True, check=True,
    ).stdout
    sock.sendall(encrypted)
    assert struct.unpack('>I', receive(sock, 4))[0] == 0, 'VNC authentication failed'
    sock.sendall(b'\x01')
    width, height = struct.unpack('>HH', receive(sock, 4))
    receive(sock, 16)  # Server pixel format; request a known format below.
    name_length = struct.unpack('>I', receive(sock, 4))[0]
    receive(sock, name_length)
    assert 640 <= width <= 4096 and 480 <= height <= 2160
    sock.sendall(struct.pack('>BxxxBBBBHHHBBBxxx', 0, 32, 24, 0, 1, 255, 255, 255, 16, 8, 0))
    sock.sendall(struct.pack('>BBHi', 2, 0, 1, 0))  # Raw encoding.
    sock.sendall(struct.pack('>BBHHHH', 3, 0, 0, 0, width, height))
    canvas = Image.new('RGB', (width, height))
    while True:
        message = receive(sock, 1)[0]
        if message == 0:
            receive(sock, 1)
            rectangles = struct.unpack('>H', receive(sock, 2))[0]
            assert rectangles > 0
            for _ in range(rectangles):
                x, y, w, h, encoding = struct.unpack('>HHHHi', receive(sock, 12))
                assert encoding == 0, f'Unexpected framebuffer encoding: {encoding}'
                pixels = receive(sock, w * h * 4)
                rectangle = Image.frombytes('RGB', (w, h), pixels, 'raw', 'BGRX')
                canvas.paste(rectangle, (x, y))
            break
        if message == 2:  # Bell.
            continue
        if message == 3:  # Clipboard message.
            receive(sock, 3)
            length = struct.unpack('>I', receive(sock, 4))[0]
            receive(sock, length)
            continue
        raise RuntimeError(f'Unexpected VNC message type: {message}')
    target = Path('/tmp/gnome-framebuffer.png')
    canvas.save(target)
    colors = canvas.resize((160, 100)).getcolors(16000)
    print(f'Authenticated VNC; {width}x{height} framebuffer, {len(colors) if colors else 0} sampled colors.')
    assert colors and len(colors) > 64, 'Desktop framebuffer is blank or not rendered'
