"""Synthetic host-test bundle; no actual profile, avatar or Wi-Fi data."""
import json
from pathlib import Path
import struct
import sys
import zlib

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
from guard import FILES

MANIFEST = {'id': 'nearby', 'name': 'Nearby', 'version': '1.0.0', 'author': 'coffer team',
            'permissions': ['mesh', 'profile', 'http'], 'hosts': ['api.fxtwitter.com', 'wsrv.nl']}


def logo():
    def chunk(kind, data):
        return struct.pack('>I', len(data)) + kind + data + struct.pack('>I', zlib.crc32(kind + data))
    return (b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', 22, 27, 8, 6, 0, 0, 0))
            + chunk(b'IDAT', zlib.compress((b'\0' + bytes(22 * 4)) * 27)) + chunk(b'IEND', b''))


def app_fixture(folder, manifest=None):
    folder = Path(folder)
    for name in FILES:
        path = folder / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(logo() if name.endswith('.png') else (ROOT / 'LICENSE').read_bytes()
                         if name == 'license.txt' else b'-- synthetic fixture\nreturn {}\n')
    (folder / 'app.json').write_text(json.dumps(manifest or MANIFEST))
    return folder
