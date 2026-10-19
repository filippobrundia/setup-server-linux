#!/usr/bin/env python3
"""Ingresso via pipe fino al confine sudo, isolato e senza installazioni."""
import hashlib
import io
import os
from pathlib import Path
import shlex
import subprocess
import tarfile
import tempfile
import unittest
import urllib.request

ROOT = Path(__file__).resolve().parents[1]

class InstallerTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.home = self.root / 'home'
        self.home.mkdir()
        self.bin = self.root / 'bin'
        self.bin.mkdir()
        self.script = ROOT / 'install.sh'
        self.version = (ROOT / 'VERSION').read_text().strip()
        self.name = 'setup-server-linux-' + self.version
        self.archive = self.root / 'archive.tar.gz'
        with tarfile.open(self.archive, 'w:gz') as tf:
            payload = b'#!/bin/bash\nexit 99\n'
            member = tarfile.TarInfo(self.name + '/bootstrap.sh')
            member.mode = 0o755
            member.size = len(payload)
            tf.addfile(member, io.BytesIO(payload))
        self.digest = hashlib.sha256(self.archive.read_bytes()).hexdigest()
        self.sums = self.root / 'SHA256SUMS'
        self.sums.write_bytes(f'{self.digest}  {self.name}.tar.gz\n'.encode())
        self.command('id', 'case "$1" in -u) echo 1000 ;; -un) echo tester ;; -nG) echo "tester sudo" ;; *) exit 90 ;; esac')
        self.command('sudo', '[ "$2" = --admin ] && [ "$3" = tester ] && [ "$4" = --check ] || exit 91\nprintf "BOOTSTRAP_BOUNDARY_OK\\n" > "$INSTALL_TEST_TRACE"\necho BOOTSTRAP_BOUNDARY_OK')
        self.command('curl', 'while [ "$#" -gt 0 ]; do\ncase "$1" in -o) dst=$2; shift 2 ;; https:*) url=$1; shift ;; *) shift ;; esac\ndone\ncase "$url" in */SHA256SUMS) cp "$INSTALL_TEST_SUMS" "$dst" ;; *.tar.gz) cp "$INSTALL_TEST_ARCHIVE" "$dst" ;; *) exit 92 ;; esac')

    def command(self, name, body):
        p = self.bin / name
        p.write_text('#!/bin/bash\nset -eu\n' + body + '\n')
        p.chmod(0o755)

    def run_installer(self, digest=None, expected=0):
        env = dict(os.environ, HOME=str(self.home), PATH=str(self.bin) + ':' + os.environ['PATH'],
                   INSTALL_TEST_TRACE=str(self.root / 'trace'), INSTALL_TEST_SUMS=str(self.sums),
                   INSTALL_TEST_ARCHIVE=str(self.archive))
        cmd = f'cat {shlex.quote(str(self.script))} | bash -s -- --check --sha256 {shlex.quote(digest or self.digest)}'
        r = subprocess.run(['script', '-qec', cmd, '/dev/null'], env=env, capture_output=True, text=True, timeout=120)
        self.assertEqual(r.returncode, expected, r.stdout + r.stderr)
        self.assertEqual((self.root / 'trace').exists(), expected == 0)
        return r

    def test_lf_pipeline_and_resume(self):
        self.run_installer()
        self.assertIn('già estratto', self.run_installer().stdout)

    def test_crlf_pipeline(self):
        self.sums.write_bytes(self.sums.read_bytes().replace(b'\n', b'\r\n'))
        self.run_installer()

    def test_corrupted_archive_stops_before_sudo(self):
        self.archive.write_bytes(self.archive.read_bytes() + b'corruption')
        self.assertIn('calcolato:', self.run_installer(expected=3).stdout)

    def test_missing_manifest_entry_stops_before_sudo(self):
        self.sums.write_bytes(f'{self.digest}  wrong-name.tar.gz\n'.encode())
        self.run_installer(expected=3)

    def test_duplicate_manifest_entry_stops_before_sudo(self):
        self.sums.write_bytes(self.sums.read_bytes() * 2)
        self.run_installer(expected=3)

    def test_independent_digest_mismatch_stops_before_sudo(self):
        self.run_installer(digest='0' * 64, expected=3)

    @unittest.skipUnless(os.environ.get('PUBLIC_INSTALL_TAG'), 'Download pubblico solo su richiesta esplicita')
    def test_live_public_download_until_sudo_boundary(self):
        tag = os.environ['PUBLIC_INSTALL_TAG']
        self.assertEqual(tag, 'v' + self.version)
        self.script = self.root / 'public-install.sh'
        self.script.write_bytes(urllib.request.urlopen(f'https://raw.githubusercontent.com/filippobrundia/setup-server-linux/{tag}/install.sh', timeout=30).read())
        self.assertEqual(self.script.read_bytes(), (ROOT / 'install.sh').read_bytes())
        (self.bin / 'curl').unlink()
        self.digest = os.environ['PUBLIC_INSTALL_SHA256']
        self.run_installer()

if __name__ == '__main__':
    unittest.main(verbosity=2)
