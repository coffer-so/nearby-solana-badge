# SPDX-License-Identifier: MIT
from contextlib import redirect_stdout
import hashlib
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import zipfile

from support import MANIFEST, app_fixture
import guard
import package


class PackageTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.app = app_fixture(self.root / 'app')
        self.manifest = dict(MANIFEST)

    def manifest_file(self):
        (self.app / 'app.json').write_text(json.dumps(self.manifest))

    def build(self, output=None):
        with patch.object(package, 'ROOT', self.root), redirect_stdout(io.StringIO()):
            return package.package(self.app, output)

    def test_filename_and_exact_allowlist(self):
        for version in ('1.0.0', '1.0.1'):
            self.manifest['version'] = version
            self.manifest_file()
            output = self.build()
            self.assertEqual(output, self.root / 'dist' / f'nearby-{version}.zip')
            with zipfile.ZipFile(output) as archive:
                self.assertEqual(archive.namelist(), list(guard.FILES))
                self.assertEqual(json.loads(archive.read('app.json'))['id'], 'nearby')
                self.assertEqual(archive.read('license.txt'),
                                 (Path(__file__).resolve().parents[1] / 'LICENSE').read_bytes())

    def test_distribution_license_is_required(self):
        (self.app / 'license.txt').unlink()
        with self.assertRaisesRegex(guard.BundleError, 'allowlist'):
            self.build()

    def test_rebuild_is_byte_identical_and_output_override_works(self):
        first, second = self.root / 'one.zip', self.root / 'two.zip'
        self.build(first)
        self.build(second)
        self.assertEqual(hashlib.sha256(first.read_bytes()).digest(), hashlib.sha256(second.read_bytes()).digest())

    def test_foreign_id_invalid_version_permission_and_host_are_rejected(self):
        changes = ({'id': 'doom-by-coffer'}, {'version': '../escape'}, {'permissions': ['mesh', 'profile', 'http', 'rpc']},
                   {'hosts': ['api.fxtwitter.com', 'unreviewed.example']})
        for change in changes:
            self.manifest = {**MANIFEST, **change}
            self.manifest_file()
            with self.subTest(change=change), self.assertRaises(guard.BundleError):
                self.build()
        self.assertFalse((self.root / 'dist').exists())

    def test_private_research_and_logs_are_not_copied_or_read(self):
        for name in ('research/synthetic-profile.json', 'logs/synthetic-console.log'):
            path = self.root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text('synthetic developer-only data')
        with zipfile.ZipFile(self.build()) as archive:
            self.assertEqual(set(archive.namelist()), set(guard.FILES))

    def test_extra_or_symlinked_app_files_are_rejected(self):
        extra = self.app / 'profile.json'
        extra.write_text('{"name":"synthetic fixture"}')
        with self.assertRaisesRegex(guard.BundleError, 'allowlist'):
            self.build()
        extra.unlink()
        logo = self.app / 'art/coffer.png'
        data = logo.read_bytes()
        logo.unlink()
        target = self.root / 'external.png'
        target.write_bytes(data)
        logo.symlink_to(target)
        with self.assertRaisesRegex(guard.BundleError, 'Symlinks'):
            self.build()

    def test_credentials_are_rejected_without_echoing_value(self):
        for text in ('local password="synthetic-sensitive-value"',
                     'local ssid="synthetic-sensitive-value"',
                     'local api_key="synthetic-sensitive-value"',
                     'local h={Authorization="Bearer synthetic-sensitive-value"}',
                     '-----BEGIN PRIVATE KEY-----', 'wifi connect example synthetic-sensitive-value'):
            (self.app / 'net.lua').write_text(text)
            with self.subTest(text=text), self.assertRaises(guard.BundleError) as error:
                self.build()
            self.assertNotIn('synthetic-sensitive-value', str(error.exception))

    def test_main_size_and_logo_dimensions_are_enforced(self):
        (self.app / 'main.lua').write_bytes(b' ' * 65537)
        with self.assertRaisesRegex(guard.BundleError, 'badge limit'):
            self.build()
        (self.app / 'main.lua').write_text('return {}')
        data = bytearray((self.app / 'art/coffer.png').read_bytes())
        data[19] = 26
        (self.app / 'art/coffer.png').write_bytes(data)
        with self.assertRaisesRegex(guard.BundleError, '22x27'):
            self.build()


if __name__ == '__main__':
    unittest.main()
