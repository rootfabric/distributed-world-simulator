"""Control-only routing oracle for stacked CHAR1 game product.

Main historically has direct P3 route; this exact staged R3C2 product branch
has CHAR1 on top of P3 on top of P1. No loosening to 'any valid Earth script'.
"""
import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
def read(path):
    return (ROOT / path).read_text(encoding="utf-8")


class EarthChar1RoutingControl(unittest.TestCase):
    def test_exact_catalog_route_not_permissive(self):
        catalog = json.loads(read("config/worlds/catalog.json"))
        earth = [e for e in catalog["worlds"] if e.get("id") == "earth"]
        self.assertEqual(len(earth), 1)
        self.assertEqual(earth[0]["runtime_script"],
            "res://scripts/app/earth_char1_avatar_app.gd")

    def test_exact_layered_ancestry(self):
        self.assertTrue(read("scripts/app/earth_char1_avatar_app.gd").startswith(
            'extends "res://scripts/app/earth_p3_resource_mining_app.gd"'))
        self.assertTrue(read("scripts/app/earth_p3_resource_mining_app.gd").startswith(
            'extends "res://scripts/app/earth_p1_modern_inventory_app.gd"'))
        self.assertTrue(read("scripts/app/earth_p1_modern_inventory_app.gd").startswith(
            'extends "res://scripts/app/earth_p1_app.gd"'))

    def test_legacy_p1_inheritance_methods_not_eliminated(self):
        source = read("tests/runtime/test_v0_p1_earth_wiring.gd")
        self.assertIn("CHAR1 product does not bypass inherited P1 inventory owner", source)
        self.assertIn("CHAR1 product retains inherited canonical P1 item interaction", source)
        self.assertIn("CHAR1 product retains M3 gameplay attach", source)
        self.assertIn("product_script.can_instantiate()", source)
        self.assertNotIn("may advance to P3", source)

    def test_control_changes_no_product_config_files(self):
        source = read("tests/runtime/test_v0_p1_earth_wiring.gd")
        self.assertIn("CURRENT_EARTH_RUNTIME_PATH", source)
        self.assertIn('P3_RUNTIME_PATH := "res://scripts/app/earth_p3_resource_mining_app.gd"', source)
        self.assertIn("P1_RUNTIME_PATH", source)


if __name__ == "__main__":
    unittest.main()
