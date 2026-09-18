# ACT0 — Fresh Independent Verifier R1

ROLE = VERIFIER. Read-only subject review. This is a request, not a completed role.

Repository: rootfabric/distributed-world-simulator.
Subject: `df1af401a11ef0c65ef442433f888f3a21963ac3`.
Tree: `b5a38ef76b0381ce773445791b0a1d40c58f455c`.
Canonical accepted-P7 base: `3d7672cba293d8e7bd72427b803f73fc8fcee5da`.
Implementation PR: #594. This carrier adds no implementation and must not replace the subject.

Read AGENTS.md, HARNESS_CONTROL.md, review-policy and the ACT0 Work Orders/PROCESS_CORRECTION_RU.md. Independently verify exact identity, no gameplay/P7/acceptance/policy mutation, generation/lease/mirrors, new epoch/Work Order, branch-only non-authority and actual post-adoption epoch resume. Verify the preserved negative controls and all final raw test logs, not just a green workflow icon.

Machine runs for the exact subject:
- ACT0 Exact Control Validation: `34341651463`.
- Project Control: `34341656160`.

Check their actual completed state, archive/member SHA-256, commands, expected negative exits, clean tracked before/after, full Harness discovery, canonical base PC0 and candidate consistency. Expected current test scope is 296 Harness tests including 18 ACT0 cases; counts are observations, not permission to skip discovered cases. Post-merge proof is still a later Integrator requirement and must not be invented by this pre-merge report.

The cause-specific predecessor case on `c5d3eed5532c9dbe61b3ca13a87242bf6f2ea73d` must fail because its epoch selector leaves `MAIN_MOVED_REVIEW_REQUIRED`; the identical scenario on the subject must reach `MAIN_MOVED_AUDIT_CONTINUE`, keep product predicates empty and keep CloseMission exit 8. Wrong actor/command/main/identity, uncommitted/dirty audit and RED PC0 must not authorize continuation.

Important process deviation: the Implementer temporarily used Actions for branch authoring contrary to the existing Harness prohibition. That workflow and helper scripts have been removed. All history and FAIL evidence is retained; this must be assessed, not silently rewritten as compliant. Final CI is read-only. No main/gameplay/old P7/acceptance write occurred during that helper operation.

Return an independently authored formal JSON object in the PR comment or a new result file on this carrier only. Required fields: schema, role=VERIFIER, independent_context, reviewed_head_sha, reviewed_tree_sha, verdict, required_fixes, rank_up_moves, evidence_gaps, risk_assessment, checked_runs, artifact digests, actual commands and limitations. Verdict vocabulary is only PASS / FAIL / INSUFFICIENT_EVIDENCE. Do not copy an Implementer PASS or treat a generic code-review acknowledgement as your verification.

If mandatory evidence is inaccessible or still running, return INSUFFICIENT_EVIDENCE with the exact gap. Do not loop indefinitely. You may run read-only tests in an isolated checkout, but must not alter subject runtime/tests/control/Work Order to make them pass. Do not merge, activate runtime, write acceptance, dismiss findings, or change policy. MVP acceptance is outside this task.
