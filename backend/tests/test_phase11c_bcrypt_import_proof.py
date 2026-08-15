from __future__ import annotations

import unittest

from tests.phase11c_bcrypt_import_proof import _require_local_url


class Phase11CLocalSafetyTests(unittest.TestCase):
    def test_local_http_supabase_urls_are_allowed(self):
        self.assertEqual(
            "http://127.0.0.1:54321", _require_local_url("http://127.0.0.1:54321/")
        )
        self.assertEqual(
            "http://localhost:54321", _require_local_url("http://localhost:54321")
        )

    def test_remote_and_https_urls_are_rejected(self):
        for url in (
            "https://project.supabase.co",
            "http://project.supabase.co",
            "https://127.0.0.1:54321",
            "",
        ):
            with self.subTest(url=url), self.assertRaises(RuntimeError):
                _require_local_url(url)


if __name__ == "__main__":
    unittest.main()
