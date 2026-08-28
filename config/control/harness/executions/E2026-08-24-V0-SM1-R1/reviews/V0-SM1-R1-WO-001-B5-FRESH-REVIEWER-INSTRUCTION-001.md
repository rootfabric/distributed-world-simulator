# V0 SM1 / B5 — Fresh Exact-Head Reviewer Instruction

Repository: `rootfabric/distributed-world-simulator`

Role: **FRESH INDEPENDENT READ-ONLY REVIEWER**

Risk: **CRITICAL**

Work Order: `V0-SM1-R1-WO-001`

Checkpoint: `V0_SM1_SEAMLESS_PRODUCT_INTEGRATION`

## 0. Non-negotiable role boundary

You are not the Implementer, Verifier, Director or Human approver.

Do not modify runtime, tests, fixtures, contracts, docs, control policy, PR metadata or branch metadata.

Do not repair findings.

Do not merge any PR.

Do not accept SM1.

Do not begin P7.

Do not reinterpret missing evidence as PASS.

Allowed mutation after the review is complete: **one control-only review result record on a dedicated review/control branch**, with `reviewed_head_sha` still pinned to the immutable runtime subject below. That control-only record must not modify runtime scope.

Reviewer verdict is exactly one of:

`PASS | FAIL | INSUFFICIENT_EVIDENCE`

## 1. Exact immutable identities

Runtime/evidence/test subject:

```text
SUBJECT_HEAD = 6fdfc047f54e727e6b398370e576c746c7949441
SUBJECT_TREE = b9b1202d959b3da4a0c73840091c7bf56070429e
```

Source-only SM1.7.12 implementation ancestor:

```text
SOURCE_HEAD = b270fb806038333c97fa1ed49655961adddd6a21
SOURCE_TREE = 45c4a684642abaeea23a7b2bd0bbc9a8f507628a
```

B4 control/evidence carrier:

```text
B4_CONTROL_HEAD = 1325812152944385c49af2ffe4f6afe6548d3b22
B4_CONTROL_TREE = 5361a0b39df871d1c899a067647c276faa258abb
```

B3 critique carrier:

```text
B3_CONTROL_HEAD = a73caa74b96c508db6f623acc2ff50ea456a49c0
```

Non-acceptance graphical demo lineage, read only as supporting UX evidence:

```text
DEMO_HEAD = b0445e08c56e090279ab21a210169df01ff3bd73
DEMO_CLEANUP_HEAD = c7674578d0b411778bda88a65fefb733368617c3
```

### Exact-head law

For runtime checkpoint review:

```text
reviewed HEAD == evidence HEAD == tested runtime HEAD == SUBJECT_HEAD
```

The B3/B4 control carrier is evidence storage, **not** the runtime review subject.

## 2. Required two-checkout protocol

Use two independent directories/worktrees.

### Checkout A — immutable runtime subject

Fresh clone/worktree, detached at exactly `SUBJECT_HEAD`.

Required identity proof:

```bash
git fetch origin --prune
git checkout --detach 6fdfc047f54e727e6b398370e576c746c7949441
git status --short
git rev-parse HEAD
git rev-parse HEAD^{tree}
git cat-file -p 6fdfc047f54e727e6b398370e576c746c7949441
```

Expected:

```text
HEAD = 6fdfc047f54e727e6b398370e576c746c7949441
TREE = b9b1202d959b3da4a0c73840091c7bf56070429e
working tree = clean
```

PowerShell-safe tree command:

```powershell
git rev-parse 'HEAD^{tree}'
```

Do not commit anything in Checkout A.

### Checkout B — evidence/control carrier

Checkout exactly `B4_CONTROL_HEAD` read-only, or read files directly with `git show`.

Required ancestry proof:

```bash
git merge-base --is-ancestor 6fdfc047f54e727e6b398370e576c746c7949441 1325812152944385c49af2ffe4f6afe6548d3b22
```

Expected exit code: `0`.

Read:

```text
config/control/harness/executions/E2026-08-24-V0-SM1-R1/work-orders/V0-SM1-R1-WO-001.v1.json
config/control/harness/executions/E2026-08-24-V0-SM1-R1/evidence/V0-SM1-R1-WO-001-POST-BUILD-CRITIQUE-001.v1.json
config/control/harness/executions/E2026-08-24-V0-SM1-R1/evidence/V0-SM1-R1-WO-001-EVIDENCE-MAP-001.v1.json
config/control/harness/executions/E2026-08-24-V0-SM1-R1/events/V0-SM1-R1-WO-001/0001-work-order-created.v1.json
.../0002-director-dispatched.v1.json
.../0003-predicate-post-build-critique-completed.v1.json
.../0004-predicate-evidence-map-complete.v1.json
```

## 3. Candidate topology and bounded repair classification

Prove:

```bash
git merge-base --is-ancestor b270fb806038333c97fa1ed49655961adddd6a21 6fdfc047f54e727e6b398370e576c746c7949441
git log --oneline b270fb806038333c97fa1ed49655961adddd6a21..6fdfc047f54e727e6b398370e576c746c7949441
git diff --name-status b270fb806038333c97fa1ed49655961adddd6a21..6fdfc047f54e727e6b398370e576c746c7949441
```

Expected repair chain:

```text
a17f8f37 fix(eco): strip inherited BOM from evo4/evo5 lab scenes
68eeaf13 fix(eg1): sequence movement after reliable operation results
e22a1ea1 fix(m7): fence item pickup on authoritative interaction pose
6fdfc047 fix(sm1): spawn detached harness workers cross-platform on windows
```

Expected delta: exactly 10 files.

Reviewer must independently classify:

- R1: six ECO scene BOM removals only; no ecology semantics.
- R2: EG1 process-driver sequencing only; no Gateway/transport production change.
- R3: M7 client-driver authoritative interaction readiness fence; server interaction thresholds unchanged.
- R4: Windows detached-spawn mechanism in two SM1 process tests; Unix path unchanged.
- no hidden production owner or protocol change in R1-R4.

If this classification is false, verdict cannot be PASS.

## 4. Source SM1 Work Order scope review

Read the Work Order and inspect source diff from its declared product base lineage through `SOURCE_HEAD`.

Required questions:

1. Are all SM1 runtime mutations within allowed scope?
2. Are forbidden paths untouched?
3. Was any second Item Graph, Construction truth, persistence owner or private world truth created?
4. Does Gateway remain routing-only?
5. Is there any direct client-to-Authority simulation connection?
6. Was NX transport/reconciliation foundation modified rather than consumed?
7. Was historical SM0/research lineage wholesale merged?

Any violation of Work Order stop conditions is a blocking finding.

## 5. Semantic review checklist

Reviewer must attempt to falsify each item.

### Authority / one-writer

- exactly one active canonical writer at every mutation point;
- WARM target is zero-write before ownership transfer;
- ownership transition has a clear linearization boundary;
- stale source cannot resurrect as writer after commit/restart/partition;
- target cannot authorize before ownership is committed.

### Identity and time

- logical player id stable;
- player entity id stable;
- spawn generation does not reset on ordinary handoff;
- authority epoch monotonic;
- input sequence continuity preserved;
- OperationId continuity and replay/exactly-once semantics preserved.

### Routing

- client-facing Gateway endpoint remains unchanged across A↔B;
- Gateway does not become ownership/canonical truth;
- route pivot does not disclose/rehome the client directly to A/B.

### Canonical gameplay state

- Item Graph remains canonical M4/P5 truth;
- Construction remains P4 canonical truth;
- P6 persistence/outpost composition remains owner;
- mutations around handoff are fenced during transfer gap;
- no duplicate canonical state appears across A/B.

### Recovery/fault behavior

Review evidence and implementation for:

- pre-commit source/target death;
- post-commit response loss;
- retry/replay;
- stale source return;
- target failure;
- duplicate/reordered traffic;
- concurrent crossings;
- reconnect after handoff;
- Gateway restart;
- Authority recovery;
- repeated crossings under impaired network.

### Manual/UX evidence boundary

Manual demo is supporting evidence only.

It proves a stable Gateway connection and user-visible seamless crossing, including Windows repeated route:

```text
A -> B -> A -> B -> A -> B
epochs 1 -> 2 -> 3 -> 4 -> 5 -> 6
connect_count=1
reconnect_count=0
respawn_count=0
```

Do not treat demo PR #284/#286 as part of production acceptance merge unless separately authorized.

## 6. Evidence honesty checks

Confirm the Evidence Map does not overclaim:

- `focused_validation = PASS` backed by exact prior evidence;
- `full_regression = PASS` backed by exact Windows double-Godot B2 run:
  - 304/304 standalone;
  - editor/import PASS;
  - manifest coverage PASS;
  - `main_scene_cli_all` PASS;
  - 307/307 total steps;
- B2 M7 repair: 10 consecutive 51/51 focused passes;
- B3 critique has no hidden required fix;
- PC0 fields are `NOT_RUN`, not fabricated PASS;
- Reviewer/Verifier/checkpoint/human merge predicates remain pending.

Known residual observation that must be discussed, not ignored:

`M5 WAIT_CONVERGENCE_PEER` hit one 150 s wall-clock timeout during B2 exploration, then passed on rerun and in final full suite.

Reviewer must decide whether this is acceptable as a non-deterministic timing observation, a required fix, or insufficient evidence.

## 7. Project Control / PC0 capture

From **Checkout A at exact SUBJECT_HEAD**, fetch refs and run Project Control read-only.

Windows:

```powershell
git fetch origin --prune
.\CONTROL_PROJECT.ps1 -NoFailOnRed
```

Equivalent lower-level checks if needed:

```text
python scripts/control/project_control.py --no-fetch --no-fail-on-red
python scripts/control/project_control_directional_watch.py --no-fail-on-red
```

Record exactly:

- standard overall health;
- standard gate NON_RED/RED;
- directional overall health;
- directional gate NON_RED/RED;
- critical SM1/V0 directional hits;
- cross-branch overlaps;
- open human-attention items.

Rules:

- do not repair RED;
- do not convert unrelated RED into PASS by prose;
- a critical SM1/V0 directional hit or critical runtime overlap blocks Reviewer PASS;
- if project-wide RED is unrelated to the reviewed SM1 candidate, Reviewer may still issue an implementation review verdict only if policy supports that separation, but `STANDARD_PC0_NON_RED` / `DIRECTIONAL_PC0_NON_RED_FOR_CRITICAL_HITS` must remain explicitly unproven until actual NON_RED evidence exists.

## 8. Optional focused execution by Reviewer

Reviewer is primarily semantic/evidence review; B6 Verifier owns fresh independent execution.

If exact double Godot is available, Reviewer may run selected focused gates for confidence, but must not substitute them for B6.

Available subject runners:

```text
RUN_V0_SM1_L0.sh
RUN_V0_SM1_GRAPHICAL.sh
RUN_V0_SM1_FAULT_MATRIX.sh
RUN_V0_SM1_CONCURRENT_CROSSINGS.sh
RUN_V0_SM1_RECONNECT_AFTER_HANDOFF.sh
RUN_V0_SM1_GATEWAY_FAILURE_RESTART.sh
RUN_V0_SM1_AUTHORITY_RECOVERY.sh
RUN_V0_SM1_WORLD_MUTATIONS_AROUND_HANDOFF.sh
RUN_V0_SM1_REPEATED_CROSSINGS_IMPAIRED_NETWORK.sh
RUN_WORLD_REGRESSION_TESTS.ps1
```

Do not edit a failing test or production file. A failure becomes a finding.

## 9. Freshness / no-self-staling check

Immediately before writing verdict:

```bash
git rev-parse HEAD
git status --short
git rev-parse HEAD^{tree}
```

Checkout A must still equal:

```text
HEAD  6fdfc047f54e727e6b398370e576c746c7949441
TREE  b9b1202d959b3da4a0c73840091c7bf56070429e
clean working tree
```

Any runtime mutation after review start makes the review stale.

## 10. Required review output

Write exactly one review result after the review is complete.

Recommended path on a dedicated control-only branch descended from B4 carrier:

```text
config/control/harness/executions/E2026-08-24-V0-SM1-R1/reviews/V0-SM1-R1-WO-001-FINAL-REVIEW-001.v1.json
```

Required fields:

```json
{
  "schema": "distributed_world_simulator.harness_review_result.v1",
  "review_id": "V0-SM1-R1-WO-001-FINAL-REVIEW-001",
  "review_type": "POST_BUILD_EXACT_HEAD_REVIEW",
  "work_order_id": "V0-SM1-R1-WO-001",
  "risk_class": "CRITICAL",
  "reviewed_head_sha": "6fdfc047f54e727e6b398370e576c746c7949441",
  "reviewer": "INDEPENDENT_REVIEWER_<IDENTITY>",
  "verdict": "PASS | FAIL | INSUFFICIENT_EVIDENCE",
  "reviewed_at_utc": "<UTC>",
  "required_fixes": [],
  "rank_up_moves": [],
  "evidence_gaps": [],
  "risk_assessment": "<concise evidence-grounded assessment>"
}
```

A richer `harness_review.v1` result with findings/checked_items is also acceptable if it preserves the same immutable `reviewed_head_sha`.

### PASS requirements

PASS is allowed only if:

- exact subject identity is proven;
- Work Order scope/stop conditions pass;
- R1-R4 repair classification passes;
- no blocking one-writer/identity/epoch/route/canonical-state/recovery defect is found;
- evidence claims are internally consistent;
- M5 timing observation is explicitly assessed;
- no critical SM1/V0 PC0 directional hit or runtime overlap invalidates the candidate;
- missing evidence is not guessed.

### FAIL

Use FAIL for a demonstrated defect or violated invariant/contract.

### INSUFFICIENT_EVIDENCE

Use when a required claim cannot be proven or contradicted from available evidence.

## 11. Forbidden conclusions

Reviewer must not write:

- SM1 ACCEPTED;
- checkpoint accepted;
- merge authorized;
- P7 activated;
- Verifier PASS;
- PC0 NON_RED unless actually observed;
- human gate satisfied.

## 12. Next actor after Reviewer

If Reviewer PASS:

```text
next_actor  = VERIFIER
next_action = FRESH_EXACT_HEAD_MACHINE_VERIFICATION
subject     = 6fdfc047f54e727e6b398370e576c746c7949441
```

If FAIL or INSUFFICIENT_EVIDENCE:

```text
B6 = BLOCKED
checkpoint proposal = BLOCKED
runtime repair may start only after Director/Repair Map authorization
```
