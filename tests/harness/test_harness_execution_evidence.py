from __future__ import annotations

import copy
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))

from scripts.harness.execution_evidence import (  # noqa: E402
    ExecutionEvidenceError,
    continuation_class,
    validate_execution_evidence,
)


HEAD = "a" * 40
BLOB = "b" * 40


def base_record() -> dict:
    return {
        "schema": "distributed_world_simulator.harness_execution_evidence.v1",
        "target_head": HEAD,
        "execution_level": "BEHAVIORAL_EXECUTION",
        "process_freshness": "FRESH_PROCESS",
        "carrier_integrity": "EXACT_TRANSITIVE_EXECUTABLE_CLOSURE",
        "transport": "DECLARED_EQUIVALENT_EXECUTION",
        "canonical_runner_executed": False,
        "equivalent_execution_executed": True,
        "equivalent_execution_allowed": True,
        "equivalent_predicates_complete": True,
        "equivalent_predicates": ["parent_gate", "parser_gate", "behavioral_gate", "fresh_process_gate"],
        "deviations": ["pwsh unavailable; predicates reproduced directly"],
        "role_authority": "IMPLEMENTER_SELF_CHECK",
        "role_independent": False,
        "post_freeze_executable_drift": False,
        "closure_manifest": {
            "target_head": HEAD,
            "root_executables": ["tests/example.gd"],
            "transitive_files": [
                {"path": "tests/example.gd", "git_blob_sha": BLOB, "identity_verified": True},
                {"path": "scripts/dependency.gd", "git_blob_sha": "c" * 40, "identity_verified": True},
            ],
        },
        "claims": {
            "parser_pass": True,
            "behavioral_pass": True,
            "fresh_process_pass": True,
            "canonical_carrier_pass": True,
            "independent_reviewer_pass": False,
            "independent_verifier_pass": False,
        },
    }


class HarnessExecutionEvidenceTests(unittest.TestCase):
    def test_valid_fresh_equivalent_implementer_execution_does_not_claim_independence(self) -> None:
        record = base_record()
        validate_execution_evidence(record)
        self.assertEqual(
            continuation_class(record, independent_role_required=True, checkpoint_accepted=False),
            "ROLE_BOUNDARY",
        )

    def test_parser_cannot_upgrade_to_behavioral(self) -> None:
        record = base_record()
        record["execution_level"] = "PARSER_PRELOAD"
        with self.assertRaisesRegex(ExecutionEvidenceError, "BEHAVIORAL_CLAIM_WITHOUT_BEHAVIORAL_EXECUTION"):
            validate_execution_evidence(record)

    def test_fresh_process_cannot_upgrade_to_independent_reviewer(self) -> None:
        record = base_record()
        record["claims"]["independent_reviewer_pass"] = True
        with self.assertRaisesRegex(ExecutionEvidenceError, "INDEPENDENT_REVIEWER_CLAIM_WITHOUT_INDEPENDENT_ROLE"):
            validate_execution_evidence(record)

    def test_top_level_exact_only_cannot_claim_canonical_carrier(self) -> None:
        record = base_record()
        record["carrier_integrity"] = "TOP_LEVEL_EXACT_ONLY"
        with self.assertRaisesRegex(ExecutionEvidenceError, "CANONICAL_CARRIER_CLAIM_WITHOUT_EXACT_TRANSITIVE_CLOSURE"):
            validate_execution_evidence(record)

    def test_exact_closure_requires_manifest(self) -> None:
        record = base_record()
        record.pop("closure_manifest")
        with self.assertRaisesRegex(ExecutionEvidenceError, "EXACT_CLOSURE_MANIFEST_REQUIRED"):
            validate_execution_evidence(record)

    def test_exact_closure_rejects_unverified_transitive_blob(self) -> None:
        record = base_record()
        record["closure_manifest"]["transitive_files"][1]["identity_verified"] = False
        with self.assertRaisesRegex(ExecutionEvidenceError, "CLOSURE_IDENTITY_NOT_VERIFIED"):
            validate_execution_evidence(record)

    def test_equivalent_execution_requires_explicit_permission(self) -> None:
        record = base_record()
        record["equivalent_execution_allowed"] = False
        with self.assertRaisesRegex(ExecutionEvidenceError, "EQUIVALENT_EXECUTION_NOT_EXPLICITLY_ALLOWED"):
            validate_execution_evidence(record)

    def test_equivalent_execution_requires_predicate_manifest(self) -> None:
        record = base_record()
        record["equivalent_predicates_complete"] = False
        with self.assertRaisesRegex(ExecutionEvidenceError, "EQUIVALENT_PREDICATE_MANIFEST_INCOMPLETE"):
            validate_execution_evidence(record)

    def test_post_freeze_executable_drift_invalidates_green_claim(self) -> None:
        record = base_record()
        record["post_freeze_executable_drift"] = True
        with self.assertRaisesRegex(ExecutionEvidenceError, "POST_FREEZE_EXECUTABLE_DRIFT_REQUIRES_REBIND_AND_REVERIFY"):
            validate_execution_evidence(record)

    def test_behavioral_failure_routes_to_repair(self) -> None:
        record = base_record()
        record["claims"]["behavioral_pass"] = False
        self.assertEqual(
            continuation_class(record, independent_role_required=False, checkpoint_accepted=False),
            "RETURN_TO_IMPLEMENTER_REPAIR_AND_REFREEZE",
        )

    def test_green_noncanonical_carrier_routes_to_carrier_repair(self) -> None:
        record = base_record()
        record["carrier_integrity"] = "TOP_LEVEL_EXACT_ONLY"
        record["claims"]["canonical_carrier_pass"] = False
        validate_execution_evidence(record)
        self.assertEqual(
            continuation_class(record, independent_role_required=False, checkpoint_accepted=False),
            "EVIDENCE_CARRIER_REPAIR_REQUIRED",
        )

    def test_accepted_checkpoint_only_follows_explicit_next_authorization(self) -> None:
        record = base_record()
        self.assertEqual(
            continuation_class(record, independent_role_required=False, checkpoint_accepted=True),
            "FOLLOW_EXPLICIT_NEXT_AUTHORIZATION_ONLY",
        )


if __name__ == "__main__":
    unittest.main()
