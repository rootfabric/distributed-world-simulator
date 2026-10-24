# CONTROL MVP8 PR #845 — Fresh machine Verifier R1

**Scoped verdict: EXACT_HEAD_TEST_EVIDENCE_VERIFIED / CODE_REVIEW_FAIL / MERGE_READY=false.**

Subject PR #845: `3a8f858f85c5ff018676557650f34179d6d5f86b`, TREE `f03f89297f1cb97ed4df9b4b8ecedfc1fef2aec3`, unchanged Draft PR. This report was prepared and checked in the current assistant session using separate new Windows and Linux machine runs and independently recomputed archive hashes. It does **not** claim a separate authenticated Verifier agent's signature or independent acceptance of code despite the fresh Reviewer FAIL.

## Fresh exact checkout

A new verifier-only Git branch contains only workflow `.github/workflows/verify-control-pr845-fresh-crossplatform-exact.yml` over frozen product commit, never changes the tested subject. GitHub Actions workflow first enforces product HEAD/TREE and verifier-only scope, then makes separate clean **named Git worktrees** at exact product SHA on both Windows and Linux.

[Fresh complete CI run #40066637305](https://github.com/rootfabric/distributed-world-simulator/actions/runs/40066637305): **scope SUCCESS, Linux SUCCESS, Windows SUCCESS.**

- Windows: R2 4/4 PASS, old Reviewer Git witness 6/6 PASS; native `CONTROL_DEVELOPMENT.ps1 -Status` exit0/ok=true, `-CheckConsistency -Candidate` exit0/ok=true. Exact HEAD/TREE match.
- Linux: R2 4/4 PASS, R1 6/6 PASS, evidence-map 5/5 PASS, full Harness **397/397 PASS**. Native CLI `status` and `check-consistency --candidate` exit0/ok=true. Exact HEAD/TREE match.
- Project Control PC0 **overall YELLOW**, Directional PC0 **overall YELLOW**, both non-RED according to raw JSON, not just a suppressed process return code.
- CheckConsistency reports three `BRANCH_ADVANCED_SINCE_SNAPSHOT` warnings: `ECO/integration`, `ECO/visual_repair`, `FABRIC/bake`. No product-blocking ERROR.
- Source code, witness manifest, original historical event/review receipt, PR #834/#839/#845 heads and canonical main were not changed during validation.

## Independent raw integrity check (not text-only)

[Fresh run's Linux artifact 12549731765](https://github.com/rootfabric/distributed-world-simulator/actions/runs/40066637305/artifacts/12549731765) ZIP SHA256 independently downloaded and verified:
`dc756ea1e410a8661de6d35dfe3c4723c3ab89f41bf76ce4bbb7d7f8fdd9a206`, exact match GitHub Actions digest.

Inside archive `SHA256SUMS` independently recomputed **10/10 MATCH**. Verified raw
`IDENTITY` (exact product HEAD/TREE), `full-harness.log` (397 PASS),
`test_mvp8_committed_witness_binding_r2.py.log` (4 PASS),
`test_mvp8_external_reviewer_event_witness_r1.py.log` (6 PASS),
`test_mvp8_immutable_evidence_reconciliation_r1.py.log` (5 PASS),
`status.jsonl` / `consistency.jsonl` and two PC0 logs plus `pc0-health.json`.

An earlier separate fresh CI run #40066335457 independently reached Linux 397 PASS, but its Windows verifier workflow had a syntactic invocation error in the dynamic PowerShell CheckConsistency call. That was a **verifier workflow defect**, fixed by using literal `-CheckConsistency -Candidate` on verifier-only branch. The original product subject was not changed; complete run #40066637305 is the accepted **fresh verifier machine evidence**.

## Why overall acceptance remains blocked

[Fresh adversarial review run #40065997560](https://github.com/rootfabric/distributed-world-simulator/actions/runs/40065997560) proves two new RED failures on the exact same product: a locally altered event #0050 and locally altered reviewer receipt are accepted despite their live bytes differing from committed HEAD blobs. [Reviewer FAIL report](https://github.com/rootfabric/distributed-world-simulator/pull/845#issuecomment-6380356062), [R3 repair issue #848](https://github.com/rootfabric/distributed-world-simulator/issues/848).

Verifier confirms the published exact tested source and the listed machine outputs, **not** completeness of the test matrix or correctness of the entire Git-provenance rule. Successful regression evidence cannot override Reviewer FAIL. No R3 repair, no merge to main, no FABRIC promotion in this verification.

**Role outcome:** `EXACT_MACHINE_EVIDENCE_VERIFIED`. **Release outcome:** `BLOCKED_REQUIRED_FIX`. **Formal independent signatures:** not asserted by this same-session report.
