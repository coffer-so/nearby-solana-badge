#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Validate the Nearby app and host tools without opening a serial port."""
import argparse
from pathlib import Path
import subprocess
import sys

from guard import load_bundle

ROOT = Path(__file__).resolve().parents[1]
SPECS = ('model', 'social', 'gif', 'net', 'text', 'app')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--lua', default='lua5.5')
    args = parser.parse_args()
    _, files = load_bundle(ROOT / 'app')
    for name in files:
        if name.endswith('.lua'):
            subprocess.run([args.lua, '-', str(ROOT / 'app' / name)],
                           input='assert(loadfile(arg[1]))\n', text=True, check=True, cwd=ROOT)
    for spec in SPECS:
        subprocess.run([args.lua, str(ROOT / 'tests' / f'{spec}_spec.lua'), str(ROOT / 'app')],
                       check=True, cwd=ROOT)
    subprocess.run([sys.executable, '-m', 'unittest', 'discover', '-s', 'tests', '-p', 'test_*.py'],
                   check=True, cwd=ROOT)
    print(f'Nearby source guard: {len(files)} allowlisted files; no serial access')


if __name__ == '__main__':
    main()
