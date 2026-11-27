"""Regression checks for the release APK verification gate (no SDK required)."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

SCRIPT = Path(__file__).with_name('apk-certificate-sha256.sh').resolve()
DIGEST = 'a' * 64


class CertificateGateTests(unittest.TestCase):
    def run_gate(self, output, status, *, keystore=False):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            apk = root / 'app.apk'
            apk.write_bytes(b'fixture')
            verifier = root / 'apksigner'
            verifier.write_text('#!/bin/sh\ncat <<\'CERT_OUTPUT\'\n' + output + '\nCERT_OUTPUT\nexit ' + str(status) + '\n')
            verifier.chmod(0o755)
            keytool = root / 'keytool'
            keytool.write_text('#!/bin/sh\necho "SHA256: ' + ':'.join(['AA'] * 32) + '"\n')
            keytool.chmod(0o755)
            args = ['bash', str(SCRIPT), str(apk)]
            if keystore:
                store = root / 'release.p12'
                store.write_bytes(b'fixture')
                args.extend([str(store), 'fixture-password', 'release'])
            return subprocess.run(args, env={**os.environ, 'APKSIGNER': str(verifier), 'KEYTOOL': str(keytool)}, text=True, capture_output=True)

    def test_accepts_verified_old_format(self):
        result = self.run_gate('Signer #1 certificate SHA-256 digest: ' + DIGEST, 0)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), DIGEST)

    def test_accepts_verified_new_format_and_matching_keystore(self):
        result = self.run_gate('V2 Signer: certificate SHA-256 digest: ' + DIGEST.upper(), 0, keystore=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), DIGEST)

    def test_rejects_nonzero_even_with_digest(self):
        result = self.run_gate('DOES NOT VERIFY\nSigner #1 certificate SHA-256 digest: ' + DIGEST, 1)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(result.stdout, '')

    def test_keystore_cannot_override_verification_failure(self):
        result = self.run_gate('DOES NOT VERIFY', 1, keystore=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(result.stdout, '')

    def test_keystore_cannot_replace_missing_apk_digest(self):
        result = self.run_gate('', 0, keystore=True)
        self.assertNotEqual(result.returncode, 0)


if __name__ == '__main__':
    unittest.main()
