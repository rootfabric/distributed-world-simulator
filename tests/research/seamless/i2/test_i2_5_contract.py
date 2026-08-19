from __future__ import annotations

import json
import unittest
from pathlib import Path


class I25ContractTests(unittest.TestCase):
    def test_i2_5_contract_01_exact_gate_scope(self) -> None:
        repo_root = Path(__file__).resolve().parents[4]
        path = repo_root / "config/research/seamless/i2/i2-5-partition-fencing-contract.v1.json"
        contract = json.loads(path.read_text(encoding="utf-8"))
        self.assertEqual("distributed_world_simulator.sm1_i2_5_partition_fencing_contract.v1", contract["schema"])
        self.assertEqual("SM1-I2.5", contract["checkpoint"])
        self.assertEqual("b4b7ea41e40cda748fc1920ebe9bb6c3c90f3f54", contract["accepted_i2_4_base"])
        self.assertEqual("SM1_I2_4_REPAIR_R1_FRESH_INDEPENDENT_REVIEW_PASS", contract["accepted_i2_4_review"])
        self.assertFalse(contract["production_activation"])
        self.assertTrue(contract["donor_only"])
        self.assertEqual("DETERMINISTIC_DIRECTORY_REACHABILITY_INJECTION_FAIL_CLOSED", contract["partition_model"])
        self.assertEqual("ACCEPTED_I2_4_DURABLE_DIRECTORY_COMPARE_AND_SWAP_ONLY", contract["canonical_mutation_path"])
        self.assertEqual("ACCEPTED_I2_2_DIRECTORY_AUTHORIZE_OWNERSHIP_TUPLE_ONLY", contract["canonical_authorization_path"])
        self.assertFalse(contract["local_runtime_claim"]["self_upgrade_allowed"])
        self.assertIn("PARTITIONED_AUTHORITY_MUTATION_ADMISSION_FAILS_CLOSED", contract["required_invariants"])
        self.assertIn("OLD_OWNER_AFTER_AUTHORITY_PROCESS_RESTART_IS_FENCED", contract["required_invariants"])
        self.assertIn("OLD_OWNER_AFTER_DIRECTORY_PROCESS_RESTART_IS_FENCED", contract["required_invariants"])
        self.assertIn("AUTHORITY_LIVENESS_DETECTION", contract["out_of_scope"])
        self.assertIn("AUTOMATIC_FAILOVER_TRIGGER", contract["out_of_scope"])
        self.assertEqual("SM1-I2.6_INTEGRATED_ONE_WRITER_PROOF", contract["next_checkpoint"])


if __name__ == "__main__":
    unittest.main()
