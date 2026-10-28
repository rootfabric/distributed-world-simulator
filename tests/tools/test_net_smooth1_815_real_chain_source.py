"""Original code remains pinned; v2 cannot silently become an accepted live codec."""
from __future__ import annotations
import copy
import sys
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/net_smooth1"))
import verify_815_real_chain_report as audit


class SourceIsolation(unittest.TestCase):
    def test_original_full_compact_frame_and_utils_byte_identical(self):
        audit.check_source(ROOT)

    def test_new_wire_schema_explicit_and_not_in_live_runtime(self):
        name = "compact_gameplay_snapshot_v2.gd"
        for path in (ROOT / "scripts").rglob("*.gd"):
            if path.name != name:
                self.assertNotIn(name, path.read_text(encoding="utf-8"), str(path))
        codec = (ROOT / "scripts/runtime/networked_gameplay/contracts" / name).read_text()
        self.assertIn('planet_simulator.compact_gameplay_snapshot.v2', codec)
        self.assertIn('IEEE754_BINARY64_LE_HEX_V1', codec)
        self.assertIn('FullSnapshot.validate(source)', codec)
        self.assertIn('FullSnapshot.validate(snapshot)', codec)
        self.assertIn('"c": source["checksum"]', codec)
        self.assertNotIn('JSON.parse', codec)
        self.assertNotIn('_wire_number(', codec)
        self.assertNotIn('return true #', codec)

    def test_real_contract_falsifier_not_fake_shape(self):
        helper = (ROOT / "tests/runtime/support/r31_815_real_snapshot_chain.gd").read_text()
        for token in ('Full.create(', 'Full.validate(', 'Compact.encode(', 'Compact.validate(', 'Compact.decode(', 'Frame.create(', 'Frame.encode(', 'Frame.decode('):
            self.assertIn(token, helper)
        self.assertIn('FRAME_CREATE_JSON', helper)
        self.assertIn('before_f64le', helper)
        self.assertIn('CORPUS_SEED: int = 81526026', helper)
        self.assertIn('CORPUS_COUNT: int = 2048', helper)

    def test_real_user1_service_not_replaced_by_fixture(self):
        path = ROOT / "tests/runtime/test_net_smooth1_815_user1_snapshot_v2.gd"
        source = path.read_text()
        for token in ('user1_product_seam_gameplay_service.gd', 'service.create_snapshot()', 'service.simulate_fixed_movement_tick(', 'service.advance_fixed_server_tick(', 'service.get_product_seam_state(', 'service.join(', 'service.leave(', 'service.validate_durable_state('):
            self.assertIn(token, source)
        self.assertNotIn('class Stub', source)
        self.assertNotIn('service.set(', source)

    def test_report_no_false_historical_or_live_acceptance(self):
        # Complete-looking proof with one deliberately forbidden claim must
        # be rejected BEFORE any assumed numerical checks are consulted.
        example = {'schema': 'dws.net_smooth.815.real_snapshot_chain.v1',
                   'fixture_kind': 'DETERMINISTIC_EARTH_LOCAL_DTO_NOT_LIVE_INCIDENT',
                   'historical_incident_proven': True}
        with self.assertRaisesRegex(ValueError, 'CANNOT_CLAIM_LIVE_ROOT_CAUSE'):
            audit.validate(example)
        example['historical_incident_proven'] = False
        example['live_network_activation'] = True
        with self.assertRaisesRegex(ValueError, 'LIVE_ACTIVATION_FORBIDDEN'):
            audit.validate(example)


if __name__ == '__main__':
    unittest.main()
