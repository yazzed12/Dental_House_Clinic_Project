from __future__ import annotations

import unittest
from pathlib import Path

from tests.route_inventory import active_route_inventory, to_tsv


CONTRACTS_DIR = Path(__file__).resolve().parent / "contracts"


class RouteInventoryCharacterizationTests(unittest.TestCase):
    def test_active_route_inventory_matches_snapshot(self):
        expected = (CONTRACTS_DIR / "route_inventory.tsv").read_text()
        actual = to_tsv(active_route_inventory())
        self.assertEqual(expected, actual)

    def test_current_application_has_74_api_routes(self):
        self.assertEqual(74, len(active_route_inventory()))

    def test_unauthenticated_medical_endpoint_snapshot_matches_inventory(self):
        inventory = active_route_inventory()
        public = {
            f"{route.method} {route.path}"
            for route in inventory
            if route.authentication == "public"
        }
        expected = set(
            (CONTRACTS_DIR / "unauthenticated_medical_endpoints.txt")
            .read_text()
            .splitlines()
        )
        self.assertEqual(expected, set())
        self.assertTrue(expected <= public)


if __name__ == "__main__":
    unittest.main()
