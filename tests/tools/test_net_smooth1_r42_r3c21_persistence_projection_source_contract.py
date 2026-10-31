"""Independent R3C21 M6 same-revision projection source fences.

Native Godot and real server persistence are mandatory; source contracts by
themselves never prove checkpoint durability, GUI FPS or reconnect.
"""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]
CHECKPOINT = (ROOT / "scripts/persistence/authoritative_checkpoint.gd").read_text(encoding="utf-8")
RECOVERY = (ROOT / "scripts/persistence/authoritative_recovery_repository.gd").read_text(encoding="utf-8")
TEST = (ROOT / "tests/runtime/test_net_smooth1_r42_r3c21_same_revision_tick_mirror.gd").read_text(encoding="utf-8")
WORKFLOW = (ROOT / ".github/workflows/net-smooth-r42-r3c3-r21-client-frame-exact.yml").read_text(encoding="utf-8")

def gd_function(source: str, name: str) -> str:
    match = re.search(r"^static func " + re.escape(name) + r"\(", source, re.M)
    if match is None:
        raise ValueError("Missing static method: " + name)
    tail = source[match.end():]
    next_method = re.search(r"^(?:static )?func ", tail, re.M)
    return source[match.start():match.end()+next_method.start() if next_method else len(source)]

def invariant_present(projection: str) -> bool:
    # Only tick mirror and its derived checksum may be removed from
    # ownership. Data/revision/canonical rows remain in the projection.
    m = re.search(r"ownership\.erase\(\"server_tick\"\)(.*?)gameplay\[\"ownership\"\]", projection, re.S)
    if not m:
        return False
    ownership = m.group(1)
    return (
        'ownership.erase("checksum")' in ownership
        and 'ownership.erase("revision")' not in ownership
        and 'ownership.erase("players")' not in ownership
        and 'ownership.clear()' not in ownership
        and 'gameplay.erase("ownership")' not in projection
    )

class ProjectionReview(unittest.TestCase):
    def test_projection_is_bounded_and_canonical_fields_kept(self):
        projection = gd_function(CHECKPOINT, "_revision_semantic_projection")
        self.assertTrue(invariant_present(projection))
        self.assertIn('semantic.erase("server_tick")',projection)
        self.assertIn('gameplay.erase("server_tick")',projection)
        self.assertIn('components.erase("durable_state_checksum")',projection)

    def test_negative_mutant_erase_revision_or_rows_is_rejected(self):
        projection = gd_function(CHECKPOINT, "_revision_semantic_projection")
        self.assertFalse(invariant_present(projection.replace(
            'ownership.erase("checksum")','ownership.erase("revision")')))
        self.assertFalse(invariant_present(projection.replace(
            'ownership.erase("checksum")','ownership.erase("players")')))

    def test_progression_must_still_fail_closed(self):
        m = gd_function(CHECKPOINT, "validate_progression")
        for phrase in ('validate(candidate)', 'validate(current)',
                       'AUTHORITATIVE_REVISION_ROLLBACK',
                       'AUTHORITATIVE_TICK_ROLLBACK',
                       '_revision_semantic_hash(candidate_snapshot)',
                       '_revision_semantic_hash(current_snapshot)',
                       'SAME_REVISION_AUTHORITATIVE_MUTATION'):
            self.assertIn(phrase,m)

    def test_diagnostics_not_in_acceptance_gate(self):
        m = gd_function(CHECKPOINT, "validate_progression")
        self.assertNotIn("debug_all_revision_difference_paths", m)
        m = re.search(r"^func save_atomic\((.*?)^func prepare\(", RECOVERY, re.M|re.S)
        self.assertIsNotNone(m)
        self.assertIn('DWS_NET_SMOOTH_TEST_HOOKS',m.group(0))
        self.assertIn('SAME_REVISION_AUTHORITATIVE_MUTATION',m.group(0))
        self.assertIn('return _failure(',m.group(0))

    def test_native_falsifier_is_mandatory_both_platforms(self):
        suite='tests/runtime/test_net_smooth1_r42_r3c21_same_revision_tick_mirror.gd'
        self.assertEqual(WORKFLOW.count(suite), 2)
        self.assertIn('runs-on: [self-hosted, Windows, X64]', WORKFLOW)
        self.assertIn('runs-on: [self-hosted, Linux, X64]', WORKFLOW)
        self.assertIn('candidate_tick_mirror',TEST)
        self.assertIn('candidate_row_mutation',TEST)
        self.assertIn('candidate_ownership_revision',TEST)
        self.assertIn('candidate_advanced',TEST)
        self.assertIn('quit(1)',TEST)

if __name__ == "__main__":
    unittest.main()
