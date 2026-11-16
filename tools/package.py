#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Build the deterministic, allowlisted Nearby App Store ZIP."""
import argparse
import hashlib
from pathlib import Path
import zipfile

from guard import FILES, load_bundle

ROOT = Path(__file__).resolve().parents[1]


def package(app, output=None):
    manifest, files = load_bundle(app)
    output = Path(output) if output else ROOT / 'dist' / f'{manifest["id"]}-{manifest["version"]}.zip'
    output.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(output, 'w', compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        for name in FILES:
            info = zipfile.ZipInfo(name, date_time=(2026, 11, 16, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o100644 << 16
            archive.writestr(info, files[name])
    print(f'{output}: {output.stat().st_size} bytes; {len(files)} files, {sum(map(len, files.values()))} source/data bytes')
    print('sha256 ' + hashlib.sha256(output.read_bytes()).hexdigest())
    return output


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, default=ROOT / 'app')
    parser.add_argument('--out', type=Path)
    args = parser.parse_args()
    package(args.root, args.out)
