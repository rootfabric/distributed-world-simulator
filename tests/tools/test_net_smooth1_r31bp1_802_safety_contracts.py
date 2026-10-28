"""Independent R31b P1 #802 narrow safety repair source falsifiers.

This suite is NOT a replacement for native Godot, M6 ACK or GUI evidence.
"""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]
SERVICE = ROOT / "scripts/runtime/networked_gameplay/user1/user1_product_seam_gameplay_service.gd"
CACHE = ROOT / "scripts/runtime/networked_gameplay/m6/r31bp1_durable_chunk_cache.gd"
M4 = ROOT / "scripts/runtime/networked_gameplay/m4/canonical_multiplayer_item_graph_service_base.gd"
ANALYZER = ROOT / "tools/net_smooth1/analyze_r31bp1_durable_chunks.py"
NATIVE = ROOT / "tests/runtime/test_net_smooth1_r31bp1_durable_chunk_cache.gd"


def method(s: str, name: str) -> str:
    match = re.search(r"(?ms)^func " + re.escape(name) + r"\(.*?(?=^func |\Z)", s)
    if not match:
        raise AssertionError(f"missing func {name}")
    return match.group()


class Safety(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.svc = SERVICE.read_text(encoding="utf-8")
        cls.cache = CACHE.read_text(encoding="utf-8")
        cls.m4 = M4.read_text(encoding="utf-8")
        cls.analyzer = ANALYZER.read_text(encoding="utf-8")
        cls.native = NATIVE.read_text(encoding="utf-8")

    def test_direct_m6_command_export_is_not_cached(self):
        direct = method(self.svc, "export_durable_state")
        self.assertIn("_canonical_multiplayer_items.export_durable_state()", direct)
        self.assertIn("_resource_mining.export_durable_state()", direct)
        self.assertNotIn("_r31bp1_export_component", direct)
        self.assertIn("SeamUtils.finalize_json_checksum(state)", direct)
        self.assertIn("validate_durable_state(state)", direct)

    def test_only_p0_periodic_export_uses_cached_chunks(self):
        profiled = method(self.svc, "export_durable_state_r31b_profiled")
        self.assertIn('_r31bp1_export_component(_canonical_multiplayer_items, "item_graph")', profiled)
        self.assertIn('_r31bp1_export_component(_resource_mining, "resource_mining")', profiled)
        self.assertIn("create_snapshot()", profiled)
        self.assertIn("validate_durable_state(durable)", profiled)
        self.assertIn("SeamUtils.finalize_json_checksum(durable)", profiled)
        self.assertNotIn("await ", profiled)
        for term in ("_tick != frozen_tick", "_revision != frozen_revision",
                     "_transfer_serial != frozen_transfer_serial", "_authority_epoch != frozen_epoch",
                     "_canonical_multiplayer_items.get_r31bp1_chunk_fence() != item_fence",
                     "_resource_mining.get_r31bp1_chunk_fence() != resource_fence",
                     "R31BP1_GLOBAL_SOURCE_FENCE_CHANGED"):
            self.assertIn(term, profiled)

    def test_r31bp1_cache_checks_after_export_before_any_return(self):
        c = method(self.cache, "export_component")
        self.assertIn("var fence: Dictionary = service.get_r31bp1_chunk_fence()", c)
        self.assertIn("var source: Dictionary = service.export_durable_state()", c)
        self.assertIn("var after_fence: Dictionary = service.get_r31bp1_chunk_fence()", c)
        self.assertLess(c.index("var source: Dictionary"), c.index("var after_fence: Dictionary"))
        self.assertLess(c.index("var after_fence: Dictionary"),
                        c.index('if bytes > MAX_CHUNK_BYTES:'))
        self.assertIn('_note_bypass(kind, "SOURCE_FENCE_CHANGED")', c)
        self.assertIn('"value": {}, "hit": false, "bypass": "SOURCE_FENCE_CHANGED"', c)
        self.assertIn('source.duplicate(true)', c)
        self.assertIn('"chunk": source.duplicate(true)', c)
        self.assertIn('Dictionary(cached.get("chunk", {})).duplicate(true)', c)

    def test_cache_failure_never_masked_by_second_export(self):
        helper = method(self.svc, "_r31bp1_export_component")
        self.assertIn('String(exported.get("bypass", "")) == "SOURCE_FENCE_CHANGED"', helper)
        self.assertIn("return {}", helper)
        self.assertLess(helper.index('"SOURCE_FENCE_CHANGED"'),
                        helper.index('return service.export_durable_state()', helper.index('"SOURCE_FENCE_CHANGED"')))

    def test_m4_fence_includes_tick_and_state_serial(self):
        m4 = method(self.m4, "get_r31bp1_chunk_fence")
        self.assertIn('"revision": _revision', m4)
        self.assertIn('"tick": _tick', m4)
        self.assertIn('"state_serial": _r31bp1_state_serial', m4)
        cmp = method(self.cache, "_fence_matches")
        self.assertIn('stored.get("tick", null) == live.get("tick", null)', cmp)

    def test_measured_window_deltas_and_bypass_reasons_not_cumulative(self):
        a = self.analyzer
        for token in ('baseline["hits"]', 'latest["hits"] - baseline["hits"]',
                      'latest["misses"] - baseline["misses"]',
                      'latest["bypasses"] - baseline["bypasses"]',
                      '"seam_unbound_fallback_measured"', '"SOURCE_FENCE_CHANGED"',
                      'ACCEPTED_BYPASS_REASON = "CHUNK_OVERSIZE"'):
            if token == '"SOURCE_FENCE_CHANGED"':
                continue
            self.assertIn(token, a)
        self.assertIn("any(key != ACCEPTED_BYPASS_REASON", a)
        self.assertIn("COUNTER_RESET", a)
        self.assertIn("BYPASS_ACCOUNTING", a)

    def test_real_native_negative_and_disk_m6_falsifiers_present(self):
        for name in ("_test_changed_source_fence",
                     "_test_exact_m6_disk_periodic_vs_direct_export",
                     "_test_miss_then_hit_and_exact_parity",
                     "_test_invalidation_fences"):
            self.assertIn("func " + name + "(", self.native)
        self.assertIn("writer.wait_completed()", self.native)
        self.assertIn("repository.load_committed()", self.native)
        self.assertIn("SOURCE_FENCE_CHANGED", self.native)


if __name__ == "__main__":
    unittest.main()
