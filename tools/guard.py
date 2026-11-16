# SPDX-License-Identifier: MIT
"""Shared, offline validation of the exact Nearby upload; never reads research/logs."""
import json
from pathlib import Path
import re
import struct

APP_ID = 'nearby'
FILES = ('main.lua', 'app.json', 'model.lua', 'net.lua', 'social.lua', 'gif.lua', 'text.lua', 'art/coffer.png', 'license.txt')
PERMISSIONS = frozenset(('mesh', 'profile', 'http'))
HOSTS = frozenset(('api.fxtwitter.com', 'wsrv.nl'))
VERSION = re.compile(r'[0-9A-Za-z][0-9A-Za-z.+-]{0,63}')
PART = re.compile(r'[a-z0-9_-]+(?:\.[a-z0-9_-]+)*')
SECRET = re.compile(
    r'''(?ix)
    (?:api[_-]?key|api[_-]?secret|client[_-]?secret|access[_-]?token|auth[_-]?token|private[_-]?key|password|passwd|ssid)
    ["'\]]*\s*[:=]\s*["'][^"'\r\n]+["']
    | authorization["'\]]*\s*[:=]\s*["']\s*(?:bearer|basic)\s+[^"']+
    | -----BEGIN\s+(?:RSA\s+|EC\s+|OPENSSH\s+)?PRIVATE\s+KEY-----
    | \bAKIA[0-9A-Z]{16}\b | \bgh[pousr]_[A-Za-z0-9]{20,}\b
    | \bwifi\s+connect\b
    '''
)


class BundleError(ValueError):
    pass


def valid_path(name):
    return (len(name) <= 64 and 1 <= len(name.split('/')) <= 4
            and all(PART.fullmatch(part) for part in name.split('/')))


def validate_manifest(manifest):
    if not isinstance(manifest, dict) or manifest.get('id') != APP_ID:
        raise BundleError('Manifest must identify only the nearby app')
    if not all(isinstance(manifest.get(k), str) and manifest[k].strip() for k in ('name', 'author')):
        raise BundleError('Manifest needs a name and author')
    if not isinstance(manifest.get('version'), str) or not VERSION.fullmatch(manifest['version']):
        raise BundleError('Invalid app version')
    permissions, hosts = manifest.get('permissions'), manifest.get('hosts', [])
    if not isinstance(permissions, list) or any(not isinstance(p, str) for p in permissions):
        raise BundleError('Invalid permissions')
    if len(permissions) != len(PERMISSIONS) or set(permissions) != PERMISSIONS:
        raise BundleError('Nearby requires only mesh/profile/http permissions')
    if not isinstance(hosts, list) or any(not isinstance(h, str) for h in hosts):
        raise BundleError('Invalid HTTP hosts')
    if len(hosts) != len(HOSTS) or set(hosts) != HOSTS:
        raise BundleError('HTTP hosts differ from the reviewed Nearby allowlist')


def validate_files(files):
    if set(files) != set(FILES):
        raise BundleError('App files must exactly match the Nearby allowlist')
    for name, data in files.items():
        if not valid_path(name):
            raise BundleError('Invalid bundle path')
        limit = 65536 if name == 'main.lua' else 2048 if name == 'app.json' else 262144
        if len(data) > limit:
            raise BundleError('File exceeds badge limit: ' + name)
        if name.endswith(('.lua', '.json')):
            try:
                source = data.decode('utf-8')
            except UnicodeError as error:
                raise BundleError('Source must be UTF-8: ' + name) from error
            if SECRET.search(source):
                # Report the filename, never the matched value or source line.
                raise BundleError('Credential-like content is not allowed: ' + name)
    bundled = [data for name, data in files.items() if name not in ('main.lua', 'app.json')]
    if len(bundled) > 64 or sum(map(len, bundled)) > 1048576:
        raise BundleError('Bundle exceeds file-count or total-size limit')
    logo = files['art/coffer.png']
    if (len(logo) < 33 or logo[:8] != b'\x89PNG\r\n\x1a\n' or logo[12:16] != b'IHDR'
            or struct.unpack('>II', logo[16:24]) != (22, 27)):
        raise BundleError('Coffer artwork must be the approved 22x27 PNG')
    try:
        manifest = json.loads(files['app.json'].decode('utf-8'))
    except (ValueError, UnicodeError) as error:
        raise BundleError('Invalid app.json') from error
    validate_manifest(manifest)
    return manifest


def load_bundle(folder):
    folder = Path(folder)
    if folder.is_symlink() or not folder.is_dir():
        raise BundleError('App folder must be a real directory')
    names = []
    for path in folder.rglob('*'):
        if path.is_symlink():
            raise BundleError('Symlinks are not allowed in an upload')
        if path.is_file():
            name = path.relative_to(folder).as_posix()
            if not valid_path(name):
                raise BundleError('Invalid bundle path')
            names.append(name)
    if set(names) != set(FILES):
        raise BundleError('App files must exactly match the Nearby allowlist')
    # Only allowlisted app paths are read. Private research, logs, and developer
    # fixtures outside app/ are neither searched nor copied into the upload.
    files = {name: (folder / name).read_bytes() for name in FILES}
    return validate_files(files), files
