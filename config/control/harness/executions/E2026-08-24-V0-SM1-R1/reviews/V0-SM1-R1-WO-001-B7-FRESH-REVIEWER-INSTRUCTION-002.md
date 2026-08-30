# V0 SM1 / B7 R9 — Fresh Exact-Head Reviewer Instruction

Repository: rootfabric/distributed-world-simulator

Role: FRESH INDEPENDENT READ-ONLY REVIEWER
Risk: CRITICAL
Work Order: V0-SM1-R1-WO-001
Checkpoint: V0_SM1_SEAMLESS_PRODUCT_INTEGRATION

Historical review:
config/control/harness/executions/E2026-08-24-V0-SM1-R1/reviews/V0-SM1-R1-WO-001-FINAL-REVIEW-001.v1.json

Fresh B6 verification:
config/control/harness/executions/E2026-08-24-V0-SM1-R1/verifications/V0-SM1-R1-WO-001-VERIFICATION-003.v1.json

Required new review record:
config/control/harness/executions/E2026-08-24-V0-SM1-R1/reviews/V0-SM1-R1-WO-001-FINAL-REVIEW-002.v1.json

## 0. Role boundary

You are not the Implementer, prior Reviewer, Verifier, Director, Windows validator, or Human approver.

Use a brand-new checkout. Do not reuse any prior worktree.

Do not modify runtime, tests, fixtures, contracts, harness implementation, production docs, PR metadata, or branch metadata.
Do not repair findings.
Do not merge.
Do not accept SM1.
Do not propose or accept the checkpoint.
Do not activate P7.
Do not satisfy the human RUNTIME_FEATURE_MERGE gate.

Your verdict is exactly one of:
PASS | FAIL | INSUFFICIENT_EVIDENCE

## 1. Exact subject

SUBJECT_BRANCH = repair/m7-camera-basis-sync-r9
SUBJECT_HEAD = b760a6cd8bf1f8b5c00d5f2430edd84853d1fa5f
SUBJECT_TREE = 7af1fe08e1f92e3b77a4b12dbccbb96c48e93a68

Historical reviewed subject:
OLD_REVIEW_HEAD = 6fdfc047f54e727e6b398370e576c746c7949441
OLD_REVIEW_TREE = b9b1202d959b3da4a0c73840091c7bf56070429e

R7_HEAD = baa0e192209e72aba5ae9d04663eea85b1099e82
R8_HEAD = 25f5ddf6280a39a44ddfc3bbec5245873021c0a1

Expected composition:
- OLD_REVIEW_HEAD -> R9 = 48 commits, 13 changed files.
- R7 -> R9 = 9 commits, 8 changed files.
- R8 -> R9 = 2 commits, exactly 2 changed files.

R8 -> R9 exact files:
- tests/runtime/test_m7_playable_networked_processes.gd
- tools/runtime/m7_playable_network_client.gd

OLD_REVIEW_HEAD -> R9 exact changed paths:
- RUN_M5_GRAPHICAL_STABILITY_TESTS.ps1
- RUN_NETWORK_CONTRACT_TESTS.ps1
- scripts/runtime/networked_gameplay/m5/m5_convergence_barrier.gd
- scripts/runtime/networked_gameplay/m5/m5_graphical_acceptance_driver.gd
- scripts/runtime/networked_gameplay/m5/m5_graphical_acceptance_support.gd
- scripts/runtime/networked_gameplay/m5/m5_process_environment.gd
- scripts/testing/process_harness/atomic_json_file.gd
- tests/runtime/support/m5_control_read_consistency_regression.gd
- tests/runtime/support/m5_convergence_release_guard_regression.gd
- tests/runtime/test_m5_graphical_acceptance_contracts.gd
- tests/runtime/test_m5_graphical_multiplayer_acceptance.gd
- tests/runtime/test_m7_playable_networked_processes.gd
- tools/runtime/m7_playable_network_client.gd

## 2. Fresh materialization

Example:
git clone https://github.com/rootfabric/distributed-world-simulator.git C:\dws-sm1-b7-r9-reviewer
cd C:\dws-sm1-b7-r9-reviewer
git fetch origin --prune
git checkout --detach b760a6cd8bf1f8b5c00d5f2430edd84853d1fa5f

Verify exact identity:
$Head = (git rev-parse HEAD).Trim()
$Tree = (git rev-parse 'HEAD^{tree}').Trim()
$Status = @(git status --porcelain)
if ($Head -ne 'b760a6cd8bf1f8b5c00d5f2430edd84853d1fa5f') { throw 'SUBJECT_HEAD_MISMATCH' }
if ($Tree -ne '7af1fe08e1f92e3b77a4b12dbccbb96c48e93a68') { throw 'SUBJECT_TREE_MISMATCH' }
if ($Status.Count -ne 0) { throw 'SUBJECT_NOT_CLEAN' }

Prove composition independently:
git rev-list --count 6fdfc047f54e727e6b398370e576c746c7949441..HEAD
git rev-list --count baa0e192209e72aba5ae9d04663eea85b1099e82..HEAD
git rev-list --count 25f5ddf6280a39a44ddfc3bbec5245873021c0a1..HEAD
git diff --name-only 6fdfc047f54e727e6b398370e576c746c7949441..HEAD
git diff --name-only 25f5ddf6280a39a44ddfc3bbec5245873021c0a1..HEAD

Expected counts: 48, 9, 2.

## 2.1 Deterministic reviewer preflight

A control-only helper is provided:

`config/control/harness/executions/E2026-08-24-V0-SM1-R1/reviews/V0-SM1-R1-WO-001-B7-REVIEWER-PREFLIGHT-002.ps1`

Run it from the exact detached R9 checkout:

```powershell
& .\config\control\harness\executions\E2026-08-24-V0-SM1-R1\reviews\V0-SM1-R1-WO-001-B7-REVIEWER-PREFLIGHT-002.ps1 `
  -GodotPath "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"
```

Required marker:

`B7_R9_REVIEWER_PREFLIGHT_PASS`

It writes:

`artifacts/control/v0-sm1-b7-r9-reviewer-preflight.json`

This helper checks exact identity, ancestry/counts, exact path sets, R7 barrier byte identity, R9 camera-basis source guards, VERIFICATION-003 integrity, exact Godot identity when supplied, current PC0 capture, and final freshness.

Important: this helper is deterministic evidence only. It is NOT your Reviewer verdict and does not replace the independent semantic review required below.

## 3. Review historical B5 result but do not inherit it

Read FINAL-REVIEW-001. It is evidence about OLD_REVIEW_HEAD only.

Independently determine whether its core SM1 conclusions remain valid at exact R9:
- exactly one canonical writer;
- WARM target remains zero-write;
- linearization boundary remains unique;
- authority epoch remains monotonic;
- stale source cannot resurrect;
- target cannot authorize before commit/retire/activate;
- logical player/entity identity remains stable;
- input sequence and OperationId continuity remain intact;
- gateway remains routing-only;
- no direct client-to-authority product route is introduced;
- Item Graph / Construction / persistence owners remain canonical and singular;
- no wholesale SM0/research merge or second private truth is introduced.

Do not simply copy the old review text. Re-prove unchanged semantics from exact bytes and exact diff boundaries.

## 4. Review the entire repair delta OLD_REVIEW_HEAD -> R9

Classify all 13 changed paths and every semantic change.

Required conclusions to test, not assume:

### R7 layer
- convergence barrier is fail-closed;
- release generation never regresses silently;
- CONTROL_GENERATION_REGRESSED_AFTER_RELEASE remains a hard failure;
- no timeout or predicate weakening hides convergence defects;
- Windows process-environment fixes do not alter product authority semantics.

### R8 layer
- atomic JSON read continuity uses typed bounded retries only for NOT_FOUND / OPEN_FAILED / EMPTY / INCOMPLETE;
- valid JSON {} is success, not retry;
- empty path is non-transient;
- retry horizon is bounded (25 attempts, 5ms delay);
- no stale .bak is accepted as current control truth;
- exhaustion produces M5_CONTROL_READ_UNAVAILABLE;
- no convergence-generation retry was introduced;
- convergence timeout was not increased;
- R7 convergence barrier bytes are unchanged by R8/R9.

### R9 layer
- automated camera yaw uses _set_automated_camera_yaw;
- yaw delta is wrapped from current scalar yaw;
- update goes through playground.player.adjust_view(yaw_delta, 0.0);
- direct automated playground.player.camera_yaw assignment is absent;
- process test guards the helper/public API/direct-assignment ban;
- no network protocol, server authority, interaction range, visibility threshold, M5, SM1, P6, or P7 semantic surface is changed by R9.

## 5. Review machine evidence integrity

Read VERIFICATION-003 and the B6 closure receipt.

Confirm:
- verifier record is on exact R9 HEAD/TREE;
- verifier carrier is one control-only commit ahead of the dispatch;
- VERIFICATION-001 and VERIFICATION-002 remain unchanged;
- governed R9 M7 = 10/10 at 54/0 each;
- governed M5 decisive = 10/10;
- focused SM1 = 13/13;
- impaired = 5/5 at 69/0 each;
- canonical first and only attempt = passed true, 304/304, 307 steps, zero bad exits;
- semantic audits and freshness are recorded;
- the disclosed PowerShell $args incident is an invalid invocation where no governed test executed, not a hidden candidate rerun;
- no governed failure was replaced by a later pass.

Reviewer may run read-only targeted checks if needed, but must not create a substitute machine-verification series.

## 6. PC0 and control truth

Run:
git fetch origin --prune
.\CONTROL_PROJECT.ps1 -NoFailOnRed

Capture exact standard and directional states. Known fresh Verifier observation is standard YELLOW / directional YELLOW, zero cross-branch overlaps, zero candidate-specific critical hits.

Do not relabel YELLOW as GREEN.

Explicitly assess these Work Order predicates:
- REVIEW_HEAD_EXACT_AND_FRESH
- STANDARD_PC0_NON_RED
- DIRECTIONAL_PC0_NON_RED_FOR_CRITICAL_HITS
- CRITICAL_CROSS_BRANCH_OVERLAP_ZERO
- HUMAN_ATTENTION_QUEUE_EMPTY_OR_RESOLVED

If policy/evidence does not justify a predicate, leave it pending and say why.

## 7. Freshness

After all review actions:
$FinalHead = (git rev-parse HEAD).Trim()
$FinalTree = (git rev-parse 'HEAD^{tree}').Trim()
git diff --exit-code
$TrackedExit = $LASTEXITCODE
git diff --cached --exit-code
$StagedExit = $LASTEXITCODE
git status --short

Required:
- final HEAD = b760a6cd8bf1f8b5c00d5f2430edd84853d1fa5f;
- final TREE = 7af1fe08e1f92e3b77a4b12dbccbb96c48e93a68;
- tracked/staged clean.

Generated/ignored artifacts may exist; list but do not commit them.

## 8. Required review record

Create exactly one new control-only record:
config/control/harness/executions/E2026-08-24-V0-SM1-R1/reviews/V0-SM1-R1-WO-001-FINAL-REVIEW-002.v1.json

Do not modify FINAL-REVIEW-001.

Minimum fields:
- schema = distributed_world_simulator.harness_review_result.v1
- review_id = V0-SM1-R1-WO-001-FINAL-REVIEW-002
- review_type = POST_BUILD_EXACT_HEAD_REVIEW
- reviewed_head_sha = b760a6cd8bf1f8b5c00d5f2430edd84853d1fa5f
- reviewed_tree_sha = 7af1fe08e1f92e3b77a4b12dbccbb96c48e93a68
- reviewer = INDEPENDENT_REVIEWER_B7_FRESH_SESSION_R2
- verdict = PASS | FAIL | INSUFFICIENT_EVIDENCE
- required_fixes = [] or exact blockers
- evidence_gaps = [] or exact remaining gaps
- repair_classification
- semantic_review
- verifier_evidence_assessment
- pc0_observed
- subject_identity_proof
- forbidden_conclusions_respected
- next

Commit the review record only on a dedicated control-only review-record branch descended from control/v0-sm1-b7-r9-reviewer-dispatch-r1.

## 9. PASS threshold

PASS requires:
- exact R9 subject identity and freshness;
- complete classification of the 48-commit / 13-file post-B5 delta;
- no hidden runtime owner/protocol/scope expansion;
- old core SM1 invariants remain valid at R9;
- R7/R8 convergence/read repairs do not weaken correctness;
- R9 camera-basis repair is bounded and semantically correct;
- VERIFICATION-003 evidence is internally consistent and not masking governed failures;
- no candidate-specific critical PC0/control defect invalidates exact R9.

A PASS review may still leave control predicates pending. PASS does not itself accept SM1 or authorize merge.

## 10. STOP rules

If a semantic defect is found: record FAIL and STOP. Do not repair.
If evidence is insufficient to establish exact-head review: record INSUFFICIENT_EVIDENCE and STOP.
Do not start P7.
Do not merge.

Expected state after PASS:
B6 = CLOSED
R9 = VERIFIED + REVIEWED / NOT MERGED
B7 = eligible for Director control reconciliation
checkpoint = NOT YET ACCEPTED
human RUNTIME_FEATURE_MERGE = untouched
P7 = BLOCKED
