# FABRIC R5.6.2 R1.3 — Linux exact / clean Git-bundle replay

**Status:** Linux exact PASS (this execution is within the implementation session, NOT an independent actor sign-off).
**Product HEAD** `d8e8361419b1fbcf0138c4deea18d19accc297f6` / **TREE** `7c5c0a4e6546b4f3f444c8a17582518c099b951e`.
**Product branch:** `repair/fabric-r562-r13-genesis-admission-r1` / Draft PR #818.
**Parent** R1.2 frozen HEAD `c9966b4f51dd623ddc6ec335b67452ccf96f7090`.

## Source and engine identity
- GitHub-generated source artifact `fabric-r562-r13-source-d8e836...`, Actions [39773841137](https://github.com/rootfabric/distributed-world-simulator/actions/runs/39773841137).
- Both Git source-carrier SHA256SUMS entries verified. Fresh `git clone ... .bundle`, detached exact subject, `git rev-parse HEAD` = product SHA; TREE verified; tracked-clean before/after.
- Godot `4.7.1.stable.double.custom_build.a13da4feb`, Linux binary SHA256 `bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7`.
- Unmodified `RUN_FABRIC_R5_6_2_R1_TESTS.sh`: exit 0. Full isolated XDG user profile and fresh cache.
- Both `import-recovery` and ordinary `import` strict PASS; `parse-lifecycle` PASS.
- New acceptance **3 × 628 assertions / 0 failures**, byte-identical raw logs; each SHA256 `7f84bf2b88996c0d24f1c0c5d7c191410ccdb4ba2d192dfb8a67529f1a60b732`.
- 10 external owner commits, 30 cold derived restarts, 42 binary receipts, 14 independent FULL oracles, 76 negative cases.
- Legacy R2 `626/0`, COM Recovery `18/0`, R1 `203/0`, BRIDGE-4 `49 PASS`.
- Evidence collector v2 PASS; identity before/after MATCH; original manifest `13/13` hashes MATCH; tracked clean / diff-check clean.
- Deterministic acceptance RESULT_SHA256 `0804d1dbd4b0c6f0111ed964e5c0a5ceb6d054b699ae9dd2580964742fc587a5`.

## Reviewer falsifier — fixed on same exact source
The original [frozen RED falsifier](https://github.com/rootfabric/distributed-world-simulator/blob/review/fabric-r562-r12-genesis-event-budget-falsifier-r1/tests/research/fabric_bake0/review_r562_genesis_budget_falsifier.gd) was run against exact R1.3 (script copied into an UNTRACKED path on a **separate fresh bundle clone**). `4/4 GREEN`:
```text
REVIEW_OVERSIZE_BOOTSTRAP=REJECTED_CODE=R562_EVENT_BUDGET_EXCEEDED
REVIEW_FALSIFIER_RESULT={"checks":4,"failures":[],"schema":"fabric.r562.review.initial_event_budget.v1"}
```
The original R1.2 subject stays red: 17-event genesis accepted but its journal cannot recover.
No code was edited after the new frozen HEAD. The change is admission-only.

## Archive and remaining work
Complete local raw evidence ZIP: `FABRIC_R562_R13_LINUX_EXACT_EVIDENCE.zip`,
SHA256 `d1316b9b0551165178031572a5cd82b7232ed1a334bab833ff52020223b5e1fa`, 70 contained paths including Linux raw logs, 42 binary receipts, reviewer RED/GREEN logs, exact identity and package SHA manifest. Available as a generated conversation artifact, not assumed to be an uploaded GitHub Release asset.

CI source-contracts `success`; self-hosted Linux exact in workflow may still be queued and must not be called green until the job actually returns success. This implementer execution does not satisfy a separate Verifier role.

**Blocking gates:** fresh Windows exact on R1.3 HEAD/TREE; two separate fresh Reviewer/Verifier sign-offs; PR #784 acceptance and human research-merge decision. PR #818/800 remain Draft; main unchanged. No claims of general atomic persistent exactly-once.
