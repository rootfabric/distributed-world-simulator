# Независимое заключение MVP1 — задание на документ

Роль исполнителя этого задания: FRESH_INDEPENDENT_REVIEWER. Это не исправление продукта. Проверяемый код и все прежние доказательства неизменны.

## Exact subjects

Repository: rootfabric/distributed-world-simulator.

- Runtime subject: `3973df7e53cbc9864c64448f26641a51f2a20465`.
- Runtime TREE: `8f5e14d8e4df84b6b9e0e8aa5846ba45af51976c`.
- Canonical main observed: `127c732a56cc5c25d5712f24a7627ed4bb877374`.
- Native evidence carrier: `827b03e553b8d37c64b7a98eb9fdb3a540e68931` (direct descendant; only nine raw evidence files added).
- Parent epoch: `E2026-09-09-V0-MVP-R1`.
- Parent WO: `V0-MVP-R1-WO-001`, still IN_PROGRESS; contains MVP1–MVP8.
- Scope of this result: ONLY `MVP_SHARED_GRAPHICAL_SCENE` plus R11/R12 corrections. Not the whole MVP checkpoint.

## Required read/check

Read AGENTS.md, review-policy.v1.json, the parent Work Order, R11/R12 bounded work orders and the existing `scripts/harness/evidence_provenance.py`.

Verify actual Git HEAD/TREE/ancestry and the full source diff. Original event4 (`1005fea2edbb49775690e2554e3e8372e9f2cec8`) is retained; event5 attributes responsibility to IMPLEMENTER without pretending a fresh independent code author. No runtime/scenes/tests/Harness implementation changed after b645a738; verify those object identities independently.

Actual CI:

```text
run_id 34534956529
job_id 103064304524
artifact_id 10175080440
archive SHA256 32a7a03b75872abfa9c0633109f6caf520374120c7f7686128f45e12bba941e8
archive size 42545
runner_id GitHub Actions 1000005656
```

Native manifest:

```text
config/control/harness/executions/E2026-09-09-V0-MVP-R1/evidence/MVP1-NATIVE-3973df7e53cb/manifest.v1.json
SHA256 afc38bfc41ec656a9b1e03bbe50d03f685126cddd2d475b1e0353eae377b98ea
Git blob 40be558cd5be7478340c7e3fbafa3f341c5db4f1
```

Read/re-hash every native artifact and check actual exit codes. In a separate clean carrier worktree, call the unmodified `validate_review_machine_evidence` with the final document's exact REUSED bindings. It must accept the published packet. A synthetic compatibility test is not an independent verdict.

Reported machine results to verify, not assume: Harness311 OK; strict PC0 standard/directional NON_RED; pinned Linux double Godot `bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7`; import exit0; existing structural smoke PASS16; actual headless scene lifecycle exit0. Drive and CloseMission complete logs remain supplementary in the CI archive: CONTINUE / completed predicates[] / expected CloseMission8.

Windows source report is an attributed user-supplied local observation at `MVP1-WINDOWS-REPORTED-OBSERVATION-R1.v1.json` within the epoch evidence directory, unchanged blob `2a5525fa44c66dd505f7fb8e1bf8abb1d6f41ef4`. The Windows verifier reported a rendered world, usable camera and controlled input/dig on b645a738. Raw Windows PNG/log bytes are NOT available in this carrier. Do not invent screenshot inspection, independent raw hashes, or graphical proof from headless execution. Decide explicitly whether the available evidence suffices for the scoped leaf; if not, use INSUFFICIENT_EVIDENCE and state the precise remaining requirement.

Prior P1s: PR597 comments3978614901 (role provenance) and3983787950 (native schema). Both have specific implemented repairs; independently confirm closure. A code-review macro on3973 completed with no major issues, comment5626115350, but that is not the requested full formal result.

## Output

Create only a NEW file on a NEW result branch from this evidence carrier:

```text
config/control/harness/executions/E2026-09-09-V0-MVP-R1/reviews/MVP1-INDEPENDENT-REVIEW-3973DF7E-R1.v1.json
```

Use schema `distributed_world_simulator.harness_review_result.v1` with review_id, review_type=POST_BUILD_EXACT_HEAD_REVIEW, work_order_id, risk_class=CRITICAL, reviewed_head_sha/tree matching runtime3973, reviewer identity, independently determined verdict (`PASS`, `FAIL` or `INSUFFICIENT_EVIDENCE`), required_fixes, rank_up_moves, evidence_gaps, risk_assessment, reviewed_at_utc, and explicit leaf-only scope.

For native REUSED machine_evidence use manifest_path above, exact manifest_sha256 above, runner_id above, run_id as string34534956529, and artifact_paths covering all eight paths listed in the actual manifest.

Do not copy an assumed PASS template. The conclusions must be yours. No changes to existing files, runtime, events, acceptance or policy; no merge/main write. Parent WO remains IN_PROGRESS. Do not emit an invalid PREDICATE_VERIFIED/IN_PROGRESS event or claim all MVP1–MVP8 implemented.

At completion give actual result branch/commit/path and verdict, or precise executor/environment failure if a runnable task could not start. Never replace the requested document with a generic no-findings reaction.
