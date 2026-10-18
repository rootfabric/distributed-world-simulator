"""SEAM-E2E source-only negative tests: never a runtime release PASS."""
import copy
import importlib.util
import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
P = ROOT / "tools/seam_e2e/check_contract.py"
S = ROOT / "config/testing/seam-e2e-r1-acceptance.v1.json"
D = ROOT / "docs/testing/SEAM_E2E_R1_MULTISERVER_WORLD_ACCEPTANCE_RU.md"
module_spec = importlib.util.spec_from_file_location("seam_e2e_contract", P)
checker = importlib.util.module_from_spec(module_spec)
module_spec.loader.exec_module(checker)
BASE = json.loads(S.read_text(encoding="utf-8"))

class SEAME2EContract(unittest.TestCase):
    def red(self, mutate):
        altered = copy.deepcopy(BASE)
        mutate(altered)
        with self.assertRaises(checker.ContractError):
            checker.validate_spec(altered)

    def test_complete_spec_is_not_runtime_pass(self):
        result = checker.validate_spec(BASE)
        self.assertEqual(result["gates"], 15)
        self.assertEqual(result["spec_verdict"], "SPEC_CONTRACT_PASS")
        self.assertEqual(result["product_verdict"], "NOT_YET_PROVEN")

    def test_two_authorities_not_full_multiserver(self):
        self.red(lambda m: m["topology"].update(min_authority_processes=2))

    def test_one_host_is_not_accepted(self):
        self.red(lambda m: m["topology"].update(
            min_distinct_physical_or_independent_vm_hosts=1))

    def test_direct_client_to_simulation_bypasses_gateway(self):
        self.red(lambda m: m["topology"].update(
            direct_client_simulation_server_transport_forbidden=False))

    def test_third_server_chain_mandatory(self):
        self.red(lambda m: m["minimum_coverage"].update(
            directed_chain=["A->B", "B->A"]))

    def test_missing_cross_player_gameplay_gate_fails(self):
        self.red(lambda m: m["acceptance_gates"].pop(4))

    def test_canonical_construction_proof_cannot_be_dropped(self):
        def change(m):
            for row in m["acceptance_gates"]:
                if row["id"] == "S06_CROSS_OWNER_CONSTRUCTION":
                    row["proof_types"].remove("canonical_state_digest")
        self.red(change)

    def test_cross_owner_observation_needs_both_traces(self):
        def change(m):
            for row in m["acceptance_gates"]:
                if row["id"] == "S04_SIMULTANEOUS_CROSS_BORDER_CO_PRESENCE":
                    row["proof_types"].remove("authority_trace")
        self.red(change)

    def test_historical_sm1_is_not_product_acceptance(self):
        self.red(lambda m: m["forbidden_substitutions"].remove(
            "TWO_AUTHORITY_SM1_LAB_AS_FULL_N_SERVER_ACCEPTANCE"))

    def test_safety_threshold_cannot_waive_duplicate_items(self):
        self.red(lambda m: m["quality_targets"].update(
            duplicate_canonical_effect_count_max=1))

    def test_frame_p99_threshold_cannot_be_relaxed(self):
        self.red(lambda m: m["quality_targets"].update(
            client_frame_p99_ms_max=27))

    def test_insufficient_item_runs_rejected(self):
        def change(m):
            for row in m["acceptance_gates"]:
                if row["id"] == "S05_CROSS_OWNER_ITEM_EXCHANGE":
                    row["min_runs"] = 1
        self.red(change)

    def test_control_review_remains_blocking(self):
        self.red(lambda m: m["release_decision"].update(
            independent_verifier_pass=False))

    def test_spec_must_not_claim_product_accepted(self):
        self.red(lambda m: m.update(status="ACCEPTED"))

    def test_human_scope_documents_recorded(self):
        t = D.read_text(encoding="utf-8")
        for required in ("S01", "S15", "Quaternius", "ItemId",
                         "BLOCKED_NOT_IMPLEMENTED", "NOT_YET_PROVEN",
                         "30-минутный", "A → B → C"):
            self.assertIn(required, t)

if __name__ == "__main__":
    unittest.main()
