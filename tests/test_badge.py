"""Protocol safety tests; no serial hardware or third-party modules required."""
import base64
import hashlib
import importlib.util
import json
from pathlib import Path
import struct
import tempfile
import unittest
from unittest.mock import patch
from types import SimpleNamespace

from support import MANIFEST, app_fixture

OURS = {"id":"nearby", "name":"Nearby", "author":"coffer team"}
import zlib

spec = importlib.util.spec_from_file_location("badge", Path(__file__).parents[1] / "tools/badge.py")
badge = importlib.util.module_from_spec(spec)
spec.loader.exec_module(badge)


class Receiver:
    """Actual protocol shape: request 2048, then only the final remainder."""
    def __init__(self, data, error=None):
        self.data, self.error = data, error
        self.expected, self.received, self.pending = base64.b64encode(data), b"", b""
        self.writes = []

    def write(self, value):
        self.writes.append(value)
        if value.startswith(b"lua recv "):
            command = value.decode().split()
            assert command[:3] == ["lua", "recv", "nearby"]
            assert int(command[-2]) == len(self.data)
            assert command[-1] == hashlib.sha256(self.data).hexdigest()
            self.pending += b"recv: ready 2048\r\n"
            if not self.data:
                self.pending += b"recv: ok 0\r\nsol> "
        else:
            assert 0 < len(value) <= 2048
            self.received += value
            if self.received == self.expected:
                if self.error:
                    self.pending += b"recv: error " + self.error + b"\r\nsol> "
                else:
                    self.pending += f"recv: ok {len(self.data)}\r\nsol> ".encode()
            else:
                self.pending += b"recv: more 2048\r\n"

    def read(self, _):
        # Force markers/prompt to cross reads, like real UART transport.
        result, self.pending = self.pending[:7], self.pending[7:]
        return result

    def flush(self):
        pass


class SafetyConsole:
    def __init__(self, manifest, sums):
        self.manifest, self.hashes, self.commands = manifest, sums, []

    def sums(self):
        return self.hashes

    def command(self, text):
        self.commands.append(text)
        return "echo\n" + json.dumps(self.manifest) + "\nsol> "

    def receive(self, name, data):
        self.commands.append("write:" + name)
        self.hashes[name] = hashlib.sha256(data).hexdigest(), len(data)


class RetryConsole(SafetyConsole):
    def __init__(self, errors):
        super().__init__({}, {})
        self.errors, self.attempts, self.resyncs = list(errors), 0, 0

    def receive(self, name, data):
        self.attempts += 1
        if self.errors:
            raise badge.BadgeError(self.errors.pop(0))
        super().receive(name, data)

    def until(self, pattern, timeout):
        assert pattern == badge.PROMPT and timeout == 10
        self.resyncs += 1
        return b"sol> ", None


class BadgeTests(unittest.TestCase):
    def test_exact_partial_install_resumes_without_manifest(self):
        data = {"main.lua": b"return", "app.json": b"{}"}
        partial = {"main.lua": (hashlib.sha256(data["main.lua"]).hexdigest(), 6)}
        console = SafetyConsole({}, partial)
        with patch.object(badge.time, "sleep"), patch("builtins.print"):
            badge.upload(console, OURS, data)
        self.assertEqual(console.commands, ["open home", "write:app.json"])

    def test_foreign_or_extra_partial_install_is_not_touched(self):
        data = {"main.lua": b"return", "app.json": b"{}"}
        for partial in ({"main.lua": ("f" * 64, 6)}, {"foreign.lua": ("f" * 64, 6)}):
            console = SafetyConsole({}, partial)
            with self.assertRaisesRegex(badge.BadgeError, "partial app differs"):
                badge.upload(console, OURS, data)
            self.assertEqual(console.commands, [])

    def test_upload_retries_only_explicit_firmware_timeout(self):
        console = RetryConsole(["timeout", "timeout"])
        with patch.object(badge.time, "sleep"), patch("builtins.print"):
            badge.upload(console, OURS, {"main.lua": b"return"})
        self.assertEqual((console.attempts, console.resyncs), (3, 2))

    def test_upload_stops_after_two_timeout_retries(self):
        console = RetryConsole(["timeout"] * 3)
        with patch.object(badge.time, "sleep"), patch("builtins.print"):
            with self.assertRaisesRegex(badge.BadgeError, "main.lua: timeout"):
                badge.upload(console, OURS, {"main.lua": b"return"})
        self.assertEqual((console.attempts, console.resyncs), (3, 2))

    def test_upload_never_retries_other_or_host_errors(self):
        for error in ("the SHA-256 doesn't match", "console timeout: no response", "not enough memory"):
            console = RetryConsole([error])
            with patch.object(badge.time, "sleep"), patch("builtins.print"):
                with self.assertRaises(badge.BadgeError):
                    badge.upload(console, OURS, {"main.lua": b"return"})
            self.assertEqual((console.attempts, console.resyncs), (1, 0))

    def test_upload_requires_prompt_before_retry(self):
        console = RetryConsole(["timeout"])
        with patch.object(badge.time, "sleep"), patch("builtins.print"), patch.object(
            console, "until", side_effect=badge.BadgeError("console timeout: no prompt")
        ):
            with self.assertRaisesRegex(badge.BadgeError, "no prompt"):
                badge.upload(console, OURS, {"main.lua": b"return"})
        self.assertEqual(console.attempts, 1)

    def test_receive_multiple_blocks_and_partial_last(self):
        data = bytes(range(256)) * 17
        receiver = Receiver(data)
        badge.Console(receiver).receive("lib/engine.lua", data)
        self.assertEqual(base64.b64decode(receiver.received), data)
        self.assertEqual([len(x) for x in receiver.writes[1:]], [2048, 2048, 1708])

    def test_zero_length_file(self):
        receiver = Receiver(b"")
        badge.Console(receiver).receive("empty.txt", b"")
        self.assertEqual(len(receiver.writes), 1)

    def test_receiver_hash_error_is_fatal(self):
        with self.assertRaisesRegex(badge.BadgeError, "SHA-256"):
            badge.Console(Receiver(b"hello", b"the SHA-256 doesn't match")).receive("main.lua", b"hello")

    def test_early_success_is_rejected(self):
        receiver = Receiver(b"hello")
        console = badge.Console(receiver)
        console.buffer = b"recv: ok 5\r\nsol> "
        with self.assertRaisesRegex(badge.BadgeError, "incomplete"):
            console.receive("main.lua", b"hello")
        self.assertEqual(len(receiver.writes), 1)

    def test_existing_foreign_app_is_not_touched(self):
        ours = {"id": "nearby", "name": "Nearby", "author": "Coffer team"}
        console = SafetyConsole({**ours, "author": "someone else"}, {"app.json": ("f" * 64, 1)})
        with self.assertRaisesRegex(badge.BadgeError, "ownership"):
            badge.upload(console, ours, {"app.json": b"{}", "main.lua": b"return"})
        self.assertFalse(any(x.startswith(("write:", "open ")) for x in console.commands))

    def test_extra_installed_files_are_not_deleted(self):
        ours = {"id": "nearby", "name": "Nearby", "author": "Coffer team"}
        console = SafetyConsole(ours, {"app.json": ("f" * 64, 1), "old.lua": ("f" * 64, 1)})
        with self.assertRaisesRegex(badge.BadgeError, "extra files"):
            badge.upload(console, ours, {"app.json": b"{}", "main.lua": b"return"})
        self.assertNotIn("open home", console.commands)

    def test_upload_writes_manifest_last_and_verifies(self):
        ours = {"id": "nearby", "name": "Nearby", "author": "Coffer team"}
        console = SafetyConsole(ours, {})
        with patch.object(badge.time, "sleep"), patch("builtins.print"):
            badge.upload(console, ours, {"app.json": b"{}", "main.lua": b"return", "model.lua": b"x"})
        self.assertEqual(console.commands, ["open home", "write:main.lua", "write:model.lua", "write:app.json"])

    def test_complete_screenshot_decodes_rgb565(self):
        row = base64.b64encode(struct.pack("<HH", 0xf800, 0x001f))
        with tempfile.TemporaryDirectory() as directory, patch("builtins.print"):
            path = Path(directory) / "screen.png"
            badge.save_shot(b"SHOT-BEGIN 2 1\nSHOT 0 0 2 " + row + b"\nSHOT-END\n", path)
            png = path.read_bytes()
        self.assertTrue(png.startswith(b"\x89PNG\r\n\x1a\n"))
        size, kind = struct.unpack_from(">I4s", png, 33)
        self.assertEqual(kind, b"IDAT")
        self.assertEqual(zlib.decompress(png[41:41 + size]), b"\0\xff\0\0\0\0\xff")

    def test_partial_screenshot_is_rejected(self):
        with self.assertRaisesRegex(badge.BadgeError, "missing pixels"):
            badge.save_shot(b"SHOT-BEGIN 2 1\nSHOT 0 0 1 AAA=\nSHOT-END\n", Path("unused.png"))

    def test_bundle_rejects_path_before_device_open(self):
        with tempfile.TemporaryDirectory() as directory:
            path = app_fixture(Path(directory))
            (path / "UPPER.lua").write_text("return")
            with self.assertRaisesRegex(badge.BadgeError, "bundle path"):
                badge.bundle(path)

    def test_only_nearby_target_and_allowlisted_paths_can_be_written(self):
        console = SafetyConsole({}, {})
        with self.assertRaisesRegex(badge.BadgeError, "only the nearby"):
            badge.upload(console, {**OURS, "id":"other-app"}, {"main.lua":b"return"})
        with self.assertRaisesRegex(badge.BadgeError, "allowlist"):
            badge.upload(console, OURS, {"../other-app/main.lua":b"return"})
        self.assertEqual(console.commands, [])

    def test_port_autodetection_is_unambiguous_and_never_opens_a_port(self):
        ports = [SimpleNamespace(device="/dev/cu.usbserial-test",vid=0x1A86)]
        self.assertEqual(badge.choose_port(ports=ports), ports[0].device)
        self.assertEqual(badge.choose_port("/dev/explicit", ports=[]), "/dev/explicit")
        for inventory in ([], ports+[SimpleNamespace(device="/dev/cu.usbserial-second",vid=0x1A86)]):
            with self.assertRaisesRegex(badge.BadgeError, "specify --port"):
                badge.choose_port(ports=inventory)

    def test_timeout_does_not_disclose_console_buffer(self):
        receiver = SimpleNamespace(read=lambda n:b"")
        console = badge.Console(receiver)
        console.buffer=b"synthetic-sensitive-output"
        with patch.object(badge.time, "monotonic", side_effect=[0,.05,.11]):
            with self.assertRaisesRegex(badge.BadgeError, "console timeout") as error:
                console.until(badge.PROMPT, .1)
        self.assertNotIn("synthetic-sensitive-output",str(error.exception))


if __name__ == "__main__":
    unittest.main()
