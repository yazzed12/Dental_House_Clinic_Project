from __future__ import annotations

import unittest

from app.core.security import get_password_hash, verify_password


class ModularSecurityTests(unittest.TestCase):
    def test_correct_password_succeeds(self):
        stored_hash = get_password_hash("CorrectPassword!")
        self.assertTrue(verify_password("CorrectPassword!", stored_hash))

    def test_incorrect_password_fails(self):
        stored_hash = get_password_hash("CorrectPassword!")
        self.assertFalse(verify_password("IncorrectPassword!", stored_hash))

    def test_password123_fails_when_it_is_not_the_stored_password(self):
        stored_hash = get_password_hash("A-Different-Password!")
        self.assertFalse(verify_password("password123", stored_hash))

    def test_password123_succeeds_only_when_it_is_the_stored_password(self):
        stored_hash = get_password_hash("password123")
        self.assertTrue(verify_password("password123", stored_hash))

    def test_hashing_and_verification_roundtrip(self):
        password = "RoundtripPassword!42"
        stored_hash = get_password_hash(password)
        self.assertNotEqual(password, stored_hash)
        self.assertTrue(verify_password(password, stored_hash))


if __name__ == "__main__":
    unittest.main()
