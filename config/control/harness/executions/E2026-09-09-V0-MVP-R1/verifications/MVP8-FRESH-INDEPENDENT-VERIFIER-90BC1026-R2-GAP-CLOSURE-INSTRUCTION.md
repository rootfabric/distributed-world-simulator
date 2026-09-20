# MVP8 Fresh Independent Windows Verifier R2 — Evidence Gap Closure

Role: **FRESH INDEPENDENT VERIFIER R2**. This is a new fresh context. Do not repair source, merge, self-accept, or reuse the prior verifier verdict without independently re-checking it.

## Frozen product

- HEAD: `90bc1026f0f5749492107191233330f87c8c70df`
- TREE: `4b6f2d48f7ef8d9c441ae89d2cbb02c730ef7f71`
- freeze: `freeze/v0-mvp8-review-90bc1026-r1`
- Reviewer PASS: `b8daebf27e11938a3c4432a127f384290e3255dc`
- Prior verifier R1: `502f5ea8d12f97b89577bc28d57f473918fe8f16`, verdict `EVIDENCE_GAP`.

R1 found no product defect. It independently passed the exact Windows MVP8 runtime gate, but Windows full world/core was not executed because the shared host entered documented machine-level multi-process ENet degradation.

Linux closure is now complete:
- full world/core run `35515256366` = SUCCESS
- job `106089996971`
- artifact `10607661947`
- digest `sha256:9ed20f0d75f2809070e10f6247b4458309ed966de16b871104153a89be0be3a4`
- 349 declared = 349 discovered
- 354 steps
- 0 failed.

PC0 remains exact non-RED:
- run `35513137221`
- standard YELLOW
- directional YELLOW.

## Goal

Close only `MVP8-VER-GAP-001` on a healthy Windows host and independently re-confirm the exact MVP8 runtime gate. Do not change product source.

## Canonical Windows Godot

`C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe`

Expected:
- version `4.7.1.stable.double.custom_build.a13da4feb`
- SHA256 `3633C3E609C8CE2F9BAE334A9C7E75C7F974DE3AF0415AB4A8050A625A15A7A5`.

## Host preflight

Before starting:
1. Stop unrelated local LLM/VM/Godot workloads that materially pressure RAM/network.
2. Confirm no other automation can execute machine-wide `Stop-Process -Name *godot*`.
3. Confirm at least ~10 GB free physical RAM if possible.
4. Confirm no active Hyper-V VM churn.
5. Confirm no existing Godot processes from unrelated tasks.
6. Create a fresh detached runtime worktree at exact frozen HEAD.
7. Verify tracked source clean.

If the host is visibly degraded before the run, stop with `EVIDENCE_GAP`; do not produce a false product FAIL.

## A. Fresh exact Windows MVP8 run

Run:

`python tests/integration/test_v0_mvp_8_bounded_workload.py --engine <GodotBin> --output <fresh-output>`

Immediately after PASS, before any other task:
- copy the entire output directory to a separate evidence snapshot directory;
- compute SHA256 for every file;
- preserve all 11 per-role JSONs;
- preserve manifest.json;
- preserve all logs.

Verify from raw evidence:
- manifest passed=true, failed_checks=[], fatal_logs=[];
- exact subject head/tree;
- 20/20 checks;
- 14/14 negatives;
- 6 distinct phase1 PIDs;
- original A PID != reconnect A PID and original_peer != reconnect_peer;
- 5 distinct phase2 PIDs, disjoint from phase1;
- rounds 0..11 contiguous;
- DIG=4 ITEM=4 BUILD_ADD=2 BUILD_REMOVE=2;
- fixed_receipts actual value;
- seam_crossings actual value;
- four dig coordinates, pairwise >=1.0 m;
- matter_resynced a/b=true;
- item_count == unique_item_count, duplicate=false;
- construct id stable, parts=100, collision=100;
- every configured bound <= cap;
- exact Windows authority/a phase1 backend sequence recorded.

## B. Independent Windows full world/core

Use the same frozen runtime worktree and pinned Godot.

Before `RUN_WORLD_REGRESSION_TESTS.ps1`, set bounded standalone env for process-managed MVP7 tests:

- `MVP7_NATIVE_MODE=produce`
- `MVP7_NATIVE_ROOT=<fresh temp root>`
- `MVP7_NATIVE_RESULT=<fresh result path>`
- `MVP7_WORLD_MODE=produce`
- `MVP7_WORLD_ROOT=<fresh temp root>`
- `MVP7_WORLD_RESULT=<fresh result path>`
- `MVP7_CONSTRUCTION_MODE=produce`
- `MVP7_CONSTRUCTION_ROOT=<fresh temp root>`
- `MVP7_CONSTRUCTION_RESULT=<fresh result path>`.

Run:

`.\RUN_WORLD_REGRESSION_TESTS.ps1`

Required:
- exit 0;
- world-regression-summary passed=true;
- declared_test_count == discovered_test_count;
- all steps green;
- record step_count and duration;
- preserve summary/log and SHA256.

The bounded env only makes auto-discovered process-managed tests valid as standalone produce tests. It does not replace the already-proven multi-process recovery gates.

## Verdict

`VERIFIED` only if:
- Reviewer PASS still exact;
- frozen HEAD/TREE/freeze exact;
- canonical Windows Godot exact;
- fresh Windows MVP8 gate PASS with preserved raw evidence;
- Windows full world/core PASS;
- Linux full world/core SUCCESS corroborated;
- PC0 non-RED corroborated;
- tracked source clean;
- no blocking evidence gap.

If host interference recurs: `EVIDENCE_GAP`.
If a reproducible frozen-product failure occurs on a healthy host: `FIX_REQUIRED`.

## Durable result

Write:
`config/control/harness/executions/E2026-09-09-V0-MVP-R1/verifications/MVP8-INDEPENDENT-VERIFICATION-90BC1026-R2.v1.json`

Commit only this result on:
`verify/v0-mvp8-90bc1026-r2`

Required final report:
- verdict;
- branch/commit/tree;
- exact product identity;
- Reviewer consumed;
- Windows/Godot identity;
- MVP8 runtime raw facts and file hashes;
- Windows world/core result/declared/discovered/steps/duration;
- Linux world/core corroboration;
- PC0 corroboration;
- source clean before/after;
- blocking findings/evidence gaps;
- merge_performed=false;
- predicate_verified=false;
- human_acceptance=false.

Stop after publishing the verifier result. Director closes MVP8.
