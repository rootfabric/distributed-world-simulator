# MVP8 Repair R2 — Fresh Independent Verifier R1

Role: **FRESH INDEPENDENT VERIFIER**. New context separate from Implementer and Reviewer. Do not repair source, merge, or self-accept.

## Gate to start

Do **not** begin final verification until a Fresh Reviewer result exists at:

`config/control/harness/executions/E2026-09-09-V0-MVP-R1/verifications/MVP8-INDEPENDENT-REVIEW-DC6E7FFF-R1.v1.json`

on branch `review/v0-mvp8-dc6e7fff-r1`, with verdict `PASS`, and its reviewed HEAD/TREE exactly match the subject below. Otherwise stop with `EVIDENCE_GAP`.

## Exact frozen subject

- HEAD: `dc6e7fffa27d764ea09ded949d50b99a32fa4d9b`
- TREE: `8fc0044ff42ad502e6457593a185465af7d2a825`
- freeze: `freeze/v0-mvp8-repair-dc6e7fff-r1`
- base: `6779af78c8cde642abf8bdfc868e905dc48a763f`
- PR: `#680`

Stop on drift.

## Canonical Windows Godot

`C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe`

Expected:
- version `4.7.1.stable.double.custom_build.a13da4feb`
- SHA256 `3633C3E609C8CE2F9BAE334A9C7E75C7F974DE3AF0415AB4A8050A625A15A7A5`.

Use a quiet healthy window: no unrelated Godot processes, >=10 GB free RAM where possible, no automation killing Godot globally. If the host is degraded, return `EVIDENCE_GAP`; do not misclassify host interference as product failure.

## A. Independent cold-start import check

Use a fresh clean worktree at exact subject. Remove/avoid any pre-existing project `.godot` state.

Run the same deterministic import path used by the harness, then independently verify:
- import exit 0;
- `.godot/global_script_class_cache.cfg` exists and is non-empty;
- import log contains no fatal parse/script/compile errors.

Then start the actual exact MVP8 harness from a fresh output directory. Do not manually pre-seed a cache in a way the harness would not normally receive on a clean run.

## B. Independent exact Windows MVP8

Run:

`python tests/integration/test_v0_mvp_8_bounded_workload.py --engine <GodotBin> --output <fresh-output>`

Immediately snapshot and hash all output before other work.

Required:
- exit 0;
- manifest passed=true;
- failed_checks=[];
- fatal_logs=[];
- 20/20 checks;
- 14/14 negative controls;
- six distinct phase1 PIDs;
- original A PID != reconnect A PID;
- original_peer != reconnect_peer;
- five distinct phase2 PIDs;
- phase1/phase2 PID sets disjoint;
- rounds 0..11;
- DIG=4, ITEM=4, BUILD_ADD=2, BUILD_REMOVE=2;
- four dig hits pairwise >=1m;
- matter_resynced a/b=true;
- unique Item identities;
- stable Construction identity;
- final collision part count 100;
- all configured bounds within caps;
- record exact fixed_receipts, seam_crossings, and phase1 authority/a backend sequence;
- preserve all 11 raw role JSONs and SHA256 every evidence file.

## C. Independent Windows full world/core

Use the repository's **canonical validator environment**, including all required MVP6 seam prerequisite result variables used by the official validators, plus bounded MVP7 produce variables. Do not use the known incomplete "MVP7-only" bare environment as a product gate.

Run `RUN_WORLD_REGRESSION_TESTS.ps1`.

Required:
- exit 0;
- summary passed=true;
- declared=349;
- discovered=349;
- steps=354;
- failed steps=0;
- no fatal parse/script/compile markers;
- exact source HEAD/TREE unchanged and tracked source clean after.

## D. Corroboration

Independently check:
- Linux exact final-subject run `35604596753` = SUCCESS;
- existing Linux full world/core run `35515256366` = SUCCESS, 349/349, 354 steps, 0 failed;
- PC0 run `35513137221` = standard YELLOW, directional YELLOW, non-RED;
- Fresh Reviewer PASS exact.

## Verdict

`VERIFIED` only if every gate above passes with exact identity and preserved evidence.

Otherwise:
- reproducible subject failure on healthy host → `FIX_REQUIRED`;
- host interference, missing canonical env/evidence, identity drift, or inability to independently establish a gate → `EVIDENCE_GAP`.

Durable result:

`config/control/harness/executions/E2026-09-09-V0-MVP-R1/verifications/MVP8-INDEPENDENT-VERIFICATION-DC6E7FFF-R1.v1.json`

Commit **only** the verifier result on:

`verify/v0-mvp8-dc6e7fff-r1`

Include:
- verdict;
- verifier branch/commit/tree;
- exact product HEAD/TREE/freeze/base/PR;
- exact Reviewer result consumed;
- Windows/Godot identity;
- cold-start import evidence;
- all MVP8 raw facts + hashes;
- Windows world/core declared/discovered/steps/duration;
- Linux corroboration;
- PC0 corroboration;
- source clean before/after;
- findings/evidence gaps;
- `merge_performed=false`;
- `predicate_verified=false`;
- `human_acceptance=false`.

Stop after publishing the Verifier result. Director performs closure separately.
