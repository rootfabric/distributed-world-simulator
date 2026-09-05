from __future__ import annotations

import json
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def load(relative: str) -> dict:
    return json.loads((ROOT / relative).read_text(encoding="utf-8"))


class AutonomousExecutionPolicyTests(unittest.TestCase):
    def test_self_execution_is_default_and_preferred_vm_is_optional(self) -> None:
        policy = load("config/control/harness/continuation-policy.v1.json")
        self.assertEqual("H0-AUTONOMY-2026-09-05-R2", policy["autonomous_execution_revision"])
        execution = policy["autonomous_execution"]
        self.assertEqual("SELF_EXECUTE_AUTOMATABLE_WORK", execution["default_mode"])
        self.assertFalse(execution["human_confirmation_for_routine_execution_required"])
        self.assertTrue(execution["agent_must_run_available_local_validation_before_role_handoff"])
        self.assertTrue(execution["agent_may_trigger_repository_owned_ci"])
        self.assertTrue(execution["agent_may_collect_and_publish_exact_head_evidence"])
        self.assertTrue(execution["preferred_external_agent_environment_is_optional"])
        self.assertTrue(execution["preferred_executor_unavailable_is_not_hard_block"])

    def test_executor_fallback_ladder_prefers_available_project_owned_execution(self) -> None:
        execution = load("config/control/harness/continuation-policy.v1.json")["autonomous_execution"]
        self.assertEqual(
            [
                "CURRENT_AGENT_VM_OR_CONTAINER",
                "CLEAN_LOCAL_WORKTREE_OR_DETACHED_CHECKOUT",
                "REPOSITORY_OWNED_CI",
                "FRESH_ISOLATED_ROLE_CONTEXT_WITH_AVAILABLE_TOOLS",
                "OPTIONAL_EXTERNAL_AGENT_ENVIRONMENT",
            ],
            execution["executor_fallback_order"],
        )
        self.assertIn("ALL_ALLOWED_AUTOMATABLE_EXECUTOR_FALLBACKS_EXHAUSTED", execution["hard_block_requires"])
        self.assertIn("NO_SCOPE_PRESERVING_REPAIR_OR_REPLAN_EXISTS", execution["hard_block_requires"])
        requirements = execution["hard_block_proof_requirements"]
        self.assertEqual(set(execution["hard_block_requires"]), set(requirements))
        durable = requirements["DURABLE_BLOCK_PROOF_WITH_EXACT_RESUME_CONDITION"]
        self.assertIn({"field": "proof_evidence_path", "predicate": "NON_EMPTY_STRING"}, durable)
        self.assertIn({"field": "resume_condition", "predicate": "NON_EMPTY_STRING"}, durable)

    def test_independent_verdict_does_not_require_separate_cloud_vm_by_default(self) -> None:
        continuation = load("config/control/harness/continuation-policy.v1.json")
        review = load("config/control/harness/review-policy.v1.json")
        risk = load("config/control/harness/risk-policy.v1.json")
        self.assertTrue(continuation["driver"]["fresh_verifier_context_required"])
        self.assertFalse(continuation["driver"]["fresh_verifier_machine_required_by_default"])
        verifier = review["verifier_execution"]
        self.assertTrue(verifier["implementer_may_run_and_publish_mechanical_validation"])
        self.assertTrue(verifier["independent_verifier_may_validate_exact_head_durable_evidence_without_reexecuting_every_command"])
        self.assertFalse(verifier["fresh_verifier_machine_required_by_default"])
        self.assertFalse(verifier["specific_external_agent_environment_required_by_default"])
        self.assertTrue(risk["rules"]["required_role_is_a_responsibility_boundary_not_a_vm_vendor_requirement"])
        self.assertTrue(risk["rules"]["implementer_cannot_convert_its_own_machine_evidence_into_an_independent_verdict"])

    def test_reused_machine_evidence_requires_hash_bound_manifest(self) -> None:
        verifier = load("config/control/harness/review-policy.v1.json")["verifier_execution"]
        required = verifier["trusted_machine_evidence_requires"]
        self.assertIn("SHA256_OR_STRONGER_DIGEST_FOR_EVERY_REUSED_LOG_OR_ARTIFACT", required)
        self.assertIn("DIGEST_MANIFEST_BINDS_EXACT_HEAD_TREE_RUNNER_AND_ARTIFACT_IDENTITY", required)
        reuse = verifier["reused_machine_evidence"]
        self.assertEqual("SHA256", reuse["minimum_digest_algorithm"])
        self.assertTrue(reuse["digest_manifest_required"])
        self.assertTrue(reuse["every_reused_log_or_artifact_requires_digest"])
        self.assertEqual(
            ["EXACT_HEAD", "EXACT_TREE", "RUNNER_OR_WORKFLOW_RUN_ID", "ARTIFACT_ID_OR_PATH"],
            reuse["manifest_must_bind"],
        )
        self.assertEqual("INSUFFICIENT_EVIDENCE", reuse["missing_or_unbound_digest_verdict"])

    def test_doctrine_preserves_human_and_acceptance_gates(self) -> None:
        text = (ROOT / "docs/control/HARNESS_AUTONOMOUS_EXECUTION_RU.md").read_text(encoding="utf-8")
        self.assertIn("SELF-EXECUTE AUTOMATABLE WORK FIRST", text)
        self.assertIn("NOT HARD BLOCKED", text)
        self.assertIn("Implementer может создать полное machine evidence", text)
        self.assertIn("не может превратить собственный результат", text)
        self.assertIn("SHA-256", text)
        self.assertIn("merge в canonical main", text)
        self.assertIn("force-push / history rewrite", text)


if __name__ == "__main__":
    unittest.main()
