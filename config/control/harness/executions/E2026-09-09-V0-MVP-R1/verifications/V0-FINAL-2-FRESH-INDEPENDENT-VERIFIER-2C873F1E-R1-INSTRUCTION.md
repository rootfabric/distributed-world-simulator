# V0-FINAL.2 — Fresh Independent Verifier R1

Role: **FRESH INDEPENDENT VERIFIER**. New context, separate from Implementer/Reviewer/Director. Do not repair or merge.

## Start gate

Require Fresh Reviewer result:
- branch `review/v0-final-2-2c873f1e-r1`;
- exact reviewed HEAD/TREE `2c873f1e/9b17c689`;
- verdict `PASS`.

Otherwise `EVIDENCE_GAP`.

## Exact subject and main-race fence

- product HEAD: `2c873f1e75f4e519c68fc6a80faddce3345362eb`
- product TREE: `9b17c68992dbfc36b6999c56e5b8b15aca593593`
- freeze: `freeze/v0-final-1-main-catchup-2c873f1e-r1`
- integrated main: `e200a61cb55930378d11c39dcc5950cf49db603c`
- accepted V0: `a1db0c66762bee887f0bf2643f7c000961e64520`

Fetch origin immediately before verification. If `origin/main` is no longer exactly `e200a61c...`, return `EVIDENCE_GAP: MAIN_MOVED_AFTER_FINAL1`.

## Independent Windows gate

Use canonical Windows double Godot:
`C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe`

Expected SHA256:
`3633C3E609C8CE2F9BAE334A9C7E75C7F974DE3AF0415AB4A8050A625A15A7A5`.

Use a fresh detached worktree at exact product HEAD, quiet host, >=10 GB free RAM, no unrelated Godot process.

1. Delete `.godot`.
2. Run exact MVP8:
   `python tests/integration/test_v0_mvp_8_bounded_workload.py --engine <Godot> --output <fresh-output>`
3. Require exit 0, 20/20, 14/14, fatal_logs=[], project import PASS/non-empty class cache, 11/11 raw role JSON, reconnect/restart facts, identity uniqueness, caps respected.
4. Snapshot and hash evidence.
5. Run exact Windows full world/core with canonical MVP6 result variables and bounded MVP7 produce variables.
6. Require exit 0, summary passed=true, declared==discovered, every step PASS/exit0, zero fatal parse/script/compile markers.
7. Run exact standard and directional PC0 on this same candidate; both must be non-RED.
8. Confirm source clean and HEAD/TREE unchanged.

Independently corroborate:
- FINAL.1 run `35736300717` SUCCESS;
- FINAL.2 machine run `36000334692` SUCCESS and exact identity;
- no critical V0 product drift from accepted V0;
- main ancestry exact.

## Verdict

`VERIFIED` only if every gate passes and main has not moved.
Healthy reproducible product failure => `FIX_REQUIRED`.
Host interference, stale main, missing evidence or identity gap => `EVIDENCE_GAP`.

Publish one file:

`config/control/harness/executions/E2026-09-09-V0-MVP-R1/verifications/V0-FINAL-2-INDEPENDENT-VERIFICATION-2C873F1E-R1.v1.json`

on branch:

`verify/v0-final-2-2c873f1e-r1`

Branch starts directly at product HEAD and adds only result JSON.

Required flags: `merge_performed=false`, `predicate_verified=false`, `human_acceptance=false`.

Stop after publishing. Director performs final checkpoint closure separately.
