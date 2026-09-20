# MVP8 Fresh Independent Verifier — 90BC1026 R1

Role: **FRESH INDEPENDENT VERIFIER** in a context independent from Implementer and Reviewer. No source repair, merge, self-acceptance, or predicate publication.

## Exact subject

- HEAD `90bc1026f0f5749492107191233330f87c8c70df`
- TREE `4b6f2d48f7ef8d9c441ae89d2cbb02c730ef7f71`
- freeze `freeze/v0-mvp8-review-90bc1026-r1`
- Work Order `V0-MVP-R1-WO-001`.

First require a fresh Reviewer result with exact subject and verdict PASS.

## Independent runtime verification

Use canonical double Godot for the platform. For Windows the expected binary is:
- version `4.7.1.stable.double.custom_build.a13da4feb`
- SHA-256 `3633C3E609C8CE2F9BAE334A9C7E75C7F974DE3AF0415AB4A8050A625A15A7A5`.

Run the exact MVP8 integration gate:
`tests/integration/test_v0_mvp_8_bounded_workload.py`

Verify from raw outputs, not only exit code:
- phase1 and phase2 are both PASS;
- six distinct phase1 processes including fresh reconnect A;
- five distinct phase2 processes, disjoint from phase1;
- reconnect peer differs from original;
- quiescent restart receipt exact;
- 12 ordered rounds in one lineage;
- action counts DIG=4, ITEM=4, BUILD_ADD=2, BUILD_REMOVE=2;
- 4 spatially distinct dig hits, minimum pair distance >=1 m;
- Matter current resync A/B after restart;
- fixed receipts >=24 and actual post-reconnect/post-restart control;
- seam crossings >=4;
- Construction identity stable and final collision part count 100;
- Item count equals unique item count; duplicate_item_identity=false;
- all fixed bounds stay within configured caps;
- all 14 negative controls rejected;
- no fatal logs;
- tracked source clean before/after.

Corroborate repository-owned Linux evidence:
- run `35510920506`, attempts 1/2/3 SUCCESS;
- attempt 3 job `106080669992`;
- artifact `10606091961`, digest `sha256:0d4eab2d5034a01f02395e10d5e158bcdb8cea458f08935a4402ebda7f7181c5`.

Corroborate PC0:
- run `35513137221`, job `106084467438`
- artifact `10606027418`, digest `sha256:8ab3a60fdde12ccf377771b71564e5483ea4e30d7553c9d5e341264256cae72b`
- standard/directional non-RED.

Also inspect the latest exact full world/core evidence for this frozen product when available. If it is not available, report a concrete EVIDENCE_GAP rather than inventing PASS.

## Verdict

Only:
- `VERIFIED`
- `FIX_REQUIRED`
- `EVIDENCE_GAP`

Write durable result:
`config/control/harness/executions/E2026-09-09-V0-MVP-R1/verifications/MVP8-INDEPENDENT-VERIFICATION-90BC1026-R1.v1.json`

Record platform, Godot version/hash, exact subject, Reviewer result consumed, commands/exits, process IDs, round/action counts, queue/replay bounds, dig distances, reconnect/restart facts, negative controls, full world/core status, source cleanliness, evidence gaps and verdict.

Commit only verifier evidence on a branch such as `verify/v0-mvp8-90bc1026-r1`. Do not create `MVP_BOUNDED_INTERACTIVE_WORKLOAD = PREDICATE_VERIFIED`; Director publishes the leaf after all closure gates.
