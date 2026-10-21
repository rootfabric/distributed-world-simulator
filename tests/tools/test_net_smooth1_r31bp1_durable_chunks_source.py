"""R31b P1 source contracts: immutable owner-native chunk boundary, no validation waiver."""
from pathlib import Path
import re
import unittest

ROOT=Path(__file__).resolve().parents[2]
M4=ROOT/"scripts/runtime/networked_gameplay/m4/canonical_multiplayer_item_graph_service.gd"
RES=ROOT/"scripts/runtime/networked_gameplay/p3/resource_mining_service.gd"
SVC=ROOT/"scripts/runtime/networked_gameplay/user1/user1_product_seam_gameplay_service.gd"
ADAPTER=ROOT/"scripts/runtime/networked_gameplay/m6/m6_dedicated_gameplay_authority_adapter.gd"
SERVER=ROOT/"scripts/runtime/networked_gameplay/m3/m3_dedicated_server_runtime_p2.gd"
RUNNER=ROOT/"tools/net_smooth1/run_net_smooth1.py"
WRITER=ROOT/"scripts/persistence/async_checkpoint_writer.gd"

def method(src: str, name: str) -> str:
    x=re.search(r"(?ms)^func "+re.escape(name)+r"\(.*?(?=^func |\Z)",src)
    if x is None:
        raise AssertionError("missing function "+name)
    return x.group(0)

class R31BP1Source(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.code={p:p.read_text(encoding="utf-8") for p in
                  (M4,RES,SVC,ADAPTER,SERVER,RUNNER,WRITER)}

    def text(self,path):
        return self.code[path]

    def test_item_fence_revision_epoch_and_unversioned_mutations(self):
        root=self.text(M4)
        fence=method(root,"get_r31bp1_durable_source_fence")
        for item in ("_authority_owner_id","_authority_epoch","_revision","_tick",
                     "_r31bp1_durable_source_serial","get_replay_projection_generation()",
                     "_live_enabled6","_live_spatial6","_live_fixture_owner6",
                     "get_instance_id()"):
            self.assertIn(item,fence)
        self.assertIn("_r31bp1_durable_source_serial += 1",method(root,"ensure_player"))
        self.assertIn("super.ensure_player(actor)",method(root,"ensure_player"))
        self.assertIn("_r31bp1_durable_source_serial += 1",method(root,"configure_live_items"))
        self.assertIn("_r31bp1_durable_source_serial += 1",method(root,"restore_durable_state"))

    def test_resource_fence_matches_real_mining_generation_and_aba(self):
        res=self.text(RES)
        fence=method(res,"get_r31bp1_durable_source_fence")
        for item in ("_authority_owner_id","_authority_epoch","_generation",
                     "_r31bp1_durable_source_serial","get_instance_id()"):
            self.assertIn(item,fence)
        self.assertIn("_generation += 1",method(res,"mine"))
        self.assertIn("_r31bp1_durable_source_serial += 1",method(res,"setup"))
        self.assertIn("_r31bp1_durable_source_serial += 1",
                      method(res,"restore_durable_state"))

    def test_legacy_durable_export_and_validation_unchanged(self):
        original=method(self.text(SVC),"export_durable_state")
        self.assertIn("SeamUtils.finalize_json_checksum(state)",original)
        self.assertIn("validate_durable_state(state)",original)
        self.assertIn("_canonical_multiplayer_items.export_durable_state()",original)
        self.assertIn("_resource_mining.export_durable_state()",original)
        self.assertNotIn("_r31bp1",original)

    def test_two_bounded_private_cached_chunks_and_exact_copies(self):
        src=self.text(SVC)
        cache=method(src,"_r31bp1_export_chunk")
        self.assertIn("R31BP1_MAX_CHUNK_BYTES",cache)
        self.assertIn("_r31bp1_item_chunk",cache)
        self.assertIn("_r31bp1_resource_chunk",cache)
        self.assertIn("cached.duplicate(true)",cache)
        self.assertIn("source.duplicate(true)",cache)
        self.assertIn("fence.duplicate(true)",cache)
        self.assertIn("get_r31bp1_durable_source_fence()",cache)
        self.assertIn('"FENCE_CHANGED"',cache)
        self.assertIn('"value": {}, "cache_hit": false',cache)
        self.assertIn("port.export_durable_state()",cache)
        # No worker-side source: all access still happens synchronously on main.
        self.assertNotIn("Thread.new()",cache)
        self.assertNotIn("await ",cache)
        self.assertIn("4 * 1024 * 1024",src)

    def test_p1_product_exact_fence_and_all_legacy_validation(self):
        main=method(self.text(SVC),"export_durable_state_r31bp1_chunks")
        for key in ("_seam_transfers_quiescent()","create_snapshot()",
                    "_build_remote_player_durable_state(snapshot)",
                    "_build_remote_ownership_durable_state(snapshot)",
                    "_shared_items.export_durable_state()",
                    '_r31bp1_export_chunk(', 'SeamUtils.finalize_json_checksum(durable)',
                    'validate_durable_state(durable)',"_tick != fenced_tick",
                    "_revision != fenced_revision","_transfer_serial != fenced_serial",
                    "_canonical_multiplayer_items.get_r31bp1_durable_source_fence()",
                    "_resource_mining.get_r31bp1_durable_source_fence()"):
            self.assertIn(key,main)
        for k in ("snapshot_ms","players_ms","ownership_ms","item_graph_ms",
                  "resource_ms","final_checksum_ms","validation_ms",
                  "item_graph_cache_hit","resource_cache_hit","item_graph_bypass",
                  "resource_bypass"):
            self.assertIn(k,main)
        self.assertNotIn("await ",main)

    def test_m6_worker_and_command_ack_unchanged(self):
        a=method(self.text(ADAPTER),"capture_frozen_gameplay_source_r31bp1_chunks")
        self.assertIn("export_durable_state_r31bp1_chunks()",a)
        self.assertIn('"logical_session_id": _logical_session_id',a)
        s=method(self.text(SERVER),"_submit_async_movement_checkpoint")
        self.assertIn("capture_frozen_gameplay_source_r31bp1_chunks()",s)
        self.assertIn("capture_frozen_gameplay_source_r31b_profiled()",s)
        self.assertIn("_movement_checkpoint_writer.submit_frozen_gameplay_source(",s)
        self.assertIn("_checkpoint_generation + 1",s)
        self.assertNotIn("wait_completed()",s)
        w=self.text(WRITER)
        self.assertIn("frozen_gameplay.duplicate(true)",w)
        self.assertIn("replay_state.duplicate(true)",w)
        self.assertIn("M6Adapter.wrap_frozen_gameplay_source(",w)

    def test_flags_cannot_change_default_or_enable_unauthorized(self):
        srv=method(self.text(SERVER),"setup")
        for k in ("DWS_NET_R31BP1_DURABLE_CHUNKS","R31BP1_INVALID_MODE",
                  "R31BP1_REQUIRES_R31B_DURABLE_ATTRIBUTION",
                  "r31bp1_durable_chunks_canary"):
            self.assertIn(k,srv)
        h=self.text(RUNNER)
        self.assertIn("r31bp1_durable_chunks=args.r31bp1_durable_chunks",h)
        self.assertIn("if role == 'server' and args.r31bp1_durable_chunks:",h)
        self.assertIn("R31BP1 durable chunks requires --r3c4r31b-durable-attribution",h)

if __name__=="__main__":
    unittest.main()
