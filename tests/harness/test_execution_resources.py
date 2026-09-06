from __future__ import annotations

import json
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))

from harness.execution_resources import (
    build_execution_resource_plan,
    load_execution_resources,
)


class ExecutionResourceContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.resources = load_execution_resources(ROOT)

    def test_dws_linux_exact_is_declared_without_pinning_physical_runner_identity(self) -> None:
        exact = self.resources["resources"]["DWS_LINUX_EXACT"]
        self.assertEqual("GITHUB_ACTIONS_SELF_HOSTED", exact["provider"])
        self.assertEqual(1, exact["capacity"])
        self.assertTrue(
            {"self-hosted", "Linux", "X64", "dws-linux", "dws-godot-double"}.issubset(
                set(exact["runner_selector"])
            )
        )
        text = json.dumps(self.resources, sort_keys=True)
        self.assertNotIn("dws-linux-outenemy", text)
        self.assertNotIn('"runner_id"', text)

    def test_self_hosted_trust_is_rootfabric_internal_push_or_dispatch_only(self) -> None:
        trust = self.resources["resources"]["DWS_LINUX_EXACT"]["trust"]
        self.assertEqual(["rootfabric"], trust["trusted_actors"])
        self.assertEqual(
            ["rootfabric/distributed-world-simulator"],
            trust["trusted_head_repositories"],
        )
        self.assertEqual(["push", "workflow_dispatch"], trust["allowed_events"])
        self.assertFalse(trust["pull_request_execution"])
        self.assertFalse(trust["external_fork_execution"])

    def test_verifier_is_routed_to_linux_exact_but_resource_does_not_replace_role(self) -> None:
        continuation = {"next_actor": "VERIFIER"}
        state = {"repository": {"implementation_head_sha": "a" * 40}}
        plan = build_execution_resource_plan(continuation, state, self.resources)
        self.assertTrue(plan["required"])
        self.assertEqual("DWS_LINUX_EXACT", plan["resource"])
        self.assertTrue(plan["resource_is_not_role"])
        self.assertTrue(plan["independent_verifier_environment"])
        self.assertEqual("a" * 40, plan["subject_head"])
        self.assertEqual({"contents": "read"}, plan["github_permissions"])

    def test_implementer_stays_local_and_runner_unavailability_does_not_block_implementation(self) -> None:
        continuation = {"next_actor": "IMPLEMENTER"}
        state = {"repository": {"implementation_head_sha": "b" * 40}}
        plan = build_execution_resource_plan(continuation, state, self.resources)
        self.assertFalse(plan["required"])
        self.assertEqual("LOCAL", plan["resource"])
        self.assertFalse(plan["independent_verifier_environment"])
        self.assertTrue(
            self.resources["fallback_policy"][
                "runner_unavailable_does_not_block_implementation"
            ]
        )

    def test_exact_queue_policy_supersedes_stale_queued_subject(self) -> None:
        queue = self.resources["queue_policy"]
        self.assertEqual(1, queue["max_dispatched_heavyweight_jobs_per_resource"])
        self.assertEqual(
            "SUPERSEDE_AND_CANCEL_OLDER_QUEUED_EXACT_JOB",
            queue["on_subject_head_change"],
        )
        self.assertTrue(queue["queued_job_is_not_pass"])
        self.assertTrue(queue["in_progress_job_is_not_pass"])

    def test_agent_router_and_harness_control_expose_resource_contract(self) -> None:
        router = (ROOT / "AGENTS.md").read_text(encoding="utf-8")
        control = (ROOT / "HARNESS_CONTROL.md").read_text(encoding="utf-8")
        for text in (router, control):
            self.assertIn("DWS_LINUX_EXACT", text)
            self.assertIn("execution-resources.v1.json", text)
        self.assertIn("next.execution_resource", router)


if __name__ == "__main__":
    unittest.main()
