#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.10"
# dependencies = ["pyserial>=3.5,<4"]
# ///
# SPDX-License-Identifier: GPL-2.0-or-later
"""Solana OS diagnostics and guarded Nearby upload; never flashes firmware.

uv run tools/badge.py upload app --run --wait 2
Opening a CH340 port may reset the board. One invocation keeps one connection.
"""
import argparse
import base64
import hashlib
import json
from pathlib import Path
import re
import struct
import sys
import time
import zlib

from guard import BundleError, FILES, load_bundle, valid_path

APP_ID = "nearby"
ANSI = re.compile(rb"\x1b\[[0-?]*[ -/]*[@-~]")
PROMPT = rb"sol> ?"
RECV = rb"recv: (?:(ready|more|ok) (\d+)|error ([^\r\n]+))\r?\n"


class BadgeError(RuntimeError):
    pass


class Console:
    def __init__(self, port):
        self.port, self.buffer = port, b""

    def until(self, pattern, timeout=10):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            found = re.search(pattern, self.buffer)
            if found:
                result, self.buffer = self.buffer[:found.end()], self.buffer[found.end():]
                return result, found
            self.buffer += ANSI.sub(b"", self.port.read(8192))
            if len(self.buffer) > 2 * 1024 * 1024:
                raise BadgeError("console response too large")
        raise BadgeError("console timeout")

    def ready(self):
        # Let any reset/boot finish before sending the first command.
        deadline = time.monotonic() + 5.5
        while time.monotonic() < deadline:
            self.buffer += ANSI.sub(b"", self.port.read(8192))
        reset = max(self.buffer.rfind(b"ESP-ROM"), self.buffer.rfind(b"rst:"))
        if reset >= 0:
            self.buffer = self.buffer[reset:]  # Ignore any prompt from before a reset.
        if b"sol>" not in self.buffer:
            self.port.write(b"\n")
        self.until(PROMPT, 25)
        self.buffer = b""

    def send(self, text):
        self.port.write(text.encode("ascii") + b"\n")
        self.port.flush()

    def command(self, text, timeout=10):
        self.send(text)
        result, _ = self.until(PROMPT, timeout)
        return result.decode("utf-8", "replace").strip()

    def sums(self):
        out = self.command("lua sums " + APP_ID)
        expected = re.search(r"sums: (\d+) files", out)
        rows = re.findall(r"(?m)^([0-9a-f]{64}) (\d+) ([a-z0-9_./-]+)\r?$", out)
        if not expected or int(expected[1]) != len(rows):
            raise BadgeError("cannot read installed checksums: " + out)
        return {name: (sha, int(size)) for sha, size, name in rows}

    def receive(self, name, content):
        digest = hashlib.sha256(content).hexdigest()
        encoded, sent, first = base64.b64encode(content), 0, True
        self.send(f"lua recv {APP_ID} {name} {len(content)} {digest}")
        while True:
            _, found = self.until(RECV, 12)
            if found[3]:
                raise BadgeError(found[3].decode("utf-8", "replace"))
            kind, count = found[1].decode(), int(found[2])
            if kind == "ok":
                if sent != len(encoded) or count != len(content):
                    raise BadgeError("receiver acknowledged incomplete file: " + name)
                self.until(PROMPT)
                return
            if kind != ("ready" if first else "more") or not 0 < count <= 2048:
                raise BadgeError("invalid receive handshake: " + name)
            chunk = encoded[sent:sent + count]
            if not chunk and content:
                raise BadgeError("receiver requested excess data: " + name)
            if chunk:
                self.port.write(chunk)
                self.port.flush()
            sent += len(chunk)
            first = False


def bundle(folder):
    try:
        return load_bundle(folder)
    except BundleError as error:
        raise BadgeError(str(error)) from error


def upload(console, manifest, files):
    if not isinstance(manifest, dict) or manifest.get("id") != APP_ID:
        raise BadgeError("only the nearby app may be uploaded")
    if any(name not in FILES or not valid_path(name) for name in files):
        raise BadgeError("upload paths differ from the Nearby allowlist")
    before = console.sums()
    if before and "app.json" not in before:
        if before.keys() - files.keys() or any(record != (hashlib.sha256(files[name]).hexdigest(), len(files[name]))
                                               for name, record in before.items()):
            raise BadgeError("partial app differs from local package; refusing overwrite")
    elif before:
        out = console.command(f"cat hh/apps/{APP_ID}/app.json")
        try:
            existing, _ = json.JSONDecoder().raw_decode(out[out.index("{"):])
        except (ValueError, TypeError) as error:
            raise BadgeError("existing app has no readable manifest; refusing overwrite") from error
        if not isinstance(existing, dict) or any(existing.get(k) != manifest[k] for k in ("id", "name", "author")):
            raise BadgeError("existing app ownership differs; refusing overwrite")
        if before.keys() - files.keys():
            raise BadgeError("existing app contains extra files; refusing partial update")
    console.command("open home")
    time.sleep(0.8)  # Lua task releases its files asynchronously.
    changed = 0  # Manifest last: launchable only once data has arrived.
    for name in sorted(files, key=lambda name: name == "app.json"):
        data = files[name]
        if before.get(name) != (hashlib.sha256(data).hexdigest(), len(data)):
            print(f"Uploading {name} ({len(data)} bytes).", flush=True)
            for attempt in range(3):
                try:
                    console.receive(name, data)
                    break
                except BadgeError as error:
                    if str(error) != "timeout" or attempt == 2:
                        raise BadgeError(f"{name}: {error}") from error
                    # Firmware timeout preserves the old file; require its prompt.
                    console.until(PROMPT, 10)
                    print(f"Retry {attempt + 1}/2: {name} after receiver timeout.", flush=True)
            changed += 1
    after = console.sums()
    wanted = {name: (hashlib.sha256(data).hexdigest(), len(data)) for name, data in files.items()}
    if after != wanted:
        raise BadgeError("installed checksums differ; app was not launched")
    print(f"Verified {len(files)} files; uploaded {changed}; {sum(map(len, files.values()))} bytes.")


def save_shot(text, path):
    start = re.search(rb"SHOT-BEGIN (\d+) (\d+)", text)
    if not start or b"SHOT-END" not in text:
        raise BadgeError("incomplete screenshot")
    width, height = map(int, start.groups())
    if not 0 < width <= 1024 or not 0 < height <= 1024:
        raise BadgeError("invalid screenshot dimensions")
    rgb, covered = bytearray(width * height * 3), bytearray(width * height)
    for x, y, n, encoded in re.findall(rb"(?m)^SHOT (\d+) (\d+) (\d+) ([A-Za-z0-9+/=]+)\r?$", text):
        x, y, n = int(x), int(y), int(n)
        data = base64.b64decode(encoded, validate=True)
        if not 0 <= y < height or not 0 <= x < width or x + n > width or len(data) != n * 2:
            raise BadgeError("invalid screenshot row")
        for i, (pixel,) in enumerate(struct.iter_unpack("<H", data)):
            at = y * width + x + i
            r, g, b = pixel >> 11, pixel >> 5 & 63, pixel & 31
            rgb[at * 3:at * 3 + 3] = bytes((r << 3 | r >> 2, g << 2 | g >> 4, b << 3 | b >> 2))
            covered[at] = 1
    if 0 in covered:
        raise BadgeError("screenshot has missing pixels")
    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))
    rows = b"".join(b"\0" + rgb[y * width * 3:(y + 1) * width * 3] for y in range(height))
    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(png + chunk(b"IDAT", zlib.compress(rows)) + chunk(b"IEND", b""))
    print(f"Saved {path} ({width}x{height}).")


def choose_port(requested=None, ports=None):
    if requested:
        return requested
    if ports is None:
        from serial.tools import list_ports
        ports = list_ports.comports()
    candidates = sorted({p.device for p in ports if (
        getattr(p, "vid", None) == 0x1A86
        or re.search(r"(?:/dev/(?:cu|tty)\.(?:usbserial|wchusbserial)|/dev/ttyUSB)", p.device)
    )})
    if len(candidates) != 1:
        raise BadgeError("specify --port: expected exactly one USB-serial badge")
    return candidates[0]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("info", "list", "mem", "shot", "upload", "run"))
    parser.add_argument("source", nargs="?", type=Path, help="upload package folder")
    parser.add_argument("--port", help="serial device; auto-detects one CH340/USB-serial port")
    parser.add_argument("--run", action="store_true", help="launch after verified upload")
    parser.add_argument("--key", action="append", choices=("up", "down", "left", "right", "select", "back", "home"), default=[])
    parser.add_argument("--wait", type=float, default=0.5, help="wait after launch/keys, in seconds")
    parser.add_argument("--shot", type=Path, help="capture final screen as PNG")
    parser.add_argument("--mem", action="store_true", help="print final Lua memory statistics")
    args = parser.parse_args()
    if args.wait < 0 or args.wait > 60:
        parser.error("--wait must be between 0 and 60 seconds")
    if args.action == "upload" and not args.source:
        parser.error("upload requires a package folder")
    package = bundle(args.source) if args.action == "upload" else None
    import serial
    with serial.Serial(port=None, baudrate=115200, timeout=0.1, write_timeout=5, exclusive=True) as port:
        port.dtr = port.rts = False
        port.port = choose_port(args.port)
        port.open()
        console = Console(port)
        console.ready()
        if package:
            if "Board: ESP32-C5 badge" not in console.command("info"):
                raise BadgeError("target is not a Solana OS ESP32-C5 badge")
            upload(console, *package)
        elif args.action in {"info", "list", "mem"}:
            print(console.command({"info": "info", "list": "lua list", "mem": "lua mem"}[args.action]))
        if args.action == "run" or args.run:
            print(console.command("lua run " + APP_ID))
            time.sleep(0.5)
        for key in args.key:
            console.command("key " + key)
        time.sleep(args.wait)
        if args.mem:
            print(console.command("lua mem"))
        if args.shot or args.action == "shot":
            console.send("shot")
            image, _ = console.until(rb"SHOT-END", 60)
            save_shot(image, args.shot or Path("work/badge.png"))


if __name__ == "__main__":
    try:
        main()
    except (BadgeError, OSError, ValueError) as error:
        sys.exit("Error: " + str(error))
