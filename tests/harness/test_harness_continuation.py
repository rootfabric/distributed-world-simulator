from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))
from harness.continuation import build_continuation

POLICY = {"review_evidence_sinks":{"default_harness_work_order":"EXECUTION_LEDGER","github_pr_gate":"GITHUB_PR_REVIEW","chat":"FORBIDDEN_AS_AUTHORITY"}}

def state() -> dict:
    return {"active_work_order":{"work_order_id":"WO-1","goal_checkpoint":"CP-1","review_required":True},"reduced_work_order":{"state":"IMPLEMENTED"},"review":{"post_build_state":"MISSING","review_target_head_sha":"a"*40},"repository":{"implementation_head_sha":"a"*40},"human_attention":{"open_items":[]},"findings":[],"checkpoint_blockers":["POST_BUILD_REVIEW_NOT_FRESH_PASS","EVIDENCE_MAP_MISSING"],"checkpoint_proposal_blocked":True}

class HarnessContinuationTests(unittest.TestCase):
    def test_missing_review_is_role_boundary_not_human_stop(self):
        r=build_continuation(state(),POLICY); self.assertEqual("ROLE_BOUNDARY",r["handoff_class"]); self.assertEqual("REVIEWER",r["next_actor"]); self.assertFalse(r["human_decision_required"]); self.assertFalse(r["mission_complete"])
    def test_chat_only_pass_does_not_authorize_transition(self):
        v=state(); v["chat_review_verdict"]="PASS"; r=build_continuation(v,POLICY); self.assertEqual("REVIEWER",r["next_actor"]); self.assertIn("DURABLE_REVIEW_PASS",r["resume_condition"])
    def test_pr_handoff_can_require_github_review_sink(self):
        v=state(); v["active_work_order"]["handoff"]={"review_evidence_sink":"GITHUB_PR_REVIEW"}; self.assertEqual("GITHUB_PR_REVIEW",build_continuation(v,POLICY)["evidence_sink"])
    def test_stale_review_routes_back_to_reviewer(self):
        v=state(); v["review"]["post_build_state"]="STALE"; self.assertEqual("REVIEWER",build_continuation(v,POLICY)["next_actor"])
    def test_review_pass_then_missing_evidence_routes_to_director(self):
        v=state(); v["review"]["post_build_state"]="PASS"; v["checkpoint_blockers"]=["EVIDENCE_MAP_MISSING"]; r=build_continuation(v,POLICY); self.assertEqual("DIRECTOR",r["next_actor"]); self.assertEqual("INGEST_DURABLE_REVIEW_AND_REFRESH_EVIDENCE_MAP",r["next_action"])
    def test_missing_predicates_route_to_verifier(self):
        v=state(); v["review"]["post_build_state"]="PASS"; v["checkpoint_blockers"]=["REQUIRED_PREDICATES_INCOMPLETE"]; self.assertEqual("VERIFIER",build_continuation(v,POLICY)["next_actor"])
    def test_blocking_human_attention_is_real_human_gate(self):
        v=state(); v["human_attention"]["open_items"]=[{"blocking":True}]; r=build_continuation(v,POLICY); self.assertEqual("HUMAN_DECISION_REQUIRED",r["handoff_class"]); self.assertEqual("HUMAN",r["next_actor"])
    def test_system_finding_routes_to_director_and_keeps_mission_open(self):
        v=state(); v["findings"]=["MAIN_MOVED_REVIEW_REQUIRED"]; r=build_continuation(v,POLICY); self.assertEqual("SYSTEM_BLOCKED",r["handoff_class"]); self.assertEqual("DIRECTOR",r["next_actor"]); self.assertFalse(r["mission_complete"])
    def test_ready_local_work_routes_to_director_not_mission_complete(self):
        v=state(); v["review"]["post_build_state"]="PASS"; v["checkpoint_blockers"]=[]; v["checkpoint_proposal_blocked"]=False; r=build_continuation(v,POLICY); self.assertEqual("DIRECTOR",r["next_actor"]); self.assertFalse(r["mission_complete"])
    def test_declared_parent_mission_survives_role_boundary(self):
        v=state(); v["active_work_order"]["mission"]={"mission_id":"MISSION-ROOT","objective":"Restore main and resume P4","parent_mission_id":"PROJECT-V0","completion_condition":"MAIN_NON_RED_AND_P4_RESUMED"}; r=build_continuation(v,POLICY); self.assertEqual("MISSION-ROOT",r["mission_id"]); self.assertEqual("PROJECT-V0",r["parent_mission_id"])

if __name__ == "__main__": unittest.main()
