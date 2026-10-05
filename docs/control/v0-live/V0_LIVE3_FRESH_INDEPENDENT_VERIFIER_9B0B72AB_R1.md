# V0-LIVE.3 R1 — Fresh Independent Verifier R1

Role: **FRESH INDEPENDENT VERIFIER**. Do not repair product source, merge PR #735, or self-accept a drifted subject.

## Frozen product subject

- HEAD: `9b0b72aba4ecdfb8d50c3d4b3cd0119b55134075`
- TREE: `a40047ce0ee07bddbe9831afcab55d97d0e2b15f`
- BASE_MAIN: `c25a6b26d83b937acd1eb4cd4d92e2b44b40c678`
- freeze: `freeze/v0-live3-r1-9b0b72ab-windows-r1`
- PR: #735
- branch: `feature/v0-live3-recovery-product-r1`

Stop on product HEAD/TREE drift.

## Reviewer prerequisite

Consume only:

- branch: `review/v0-live3-9b0b72ab-r1`
- commit: `821ec4dbb5b36e86fc005a1aa320baebe3c0eeb2`
- tree: `011e36732954a387e66e357f2453e8798c7cd0bd`
- result: `docs/control/v0-live/V0_LIVE3_FRESH_REVIEW_9B0B72AB_R1.json`
- required verdict: `PASS`

Reviewer HEAD/TREE must exactly equal the frozen product subject.

## Independent Windows verification

Use canonical Godot:

`C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe`

Expected:
- version: `4.7.1.stable.double.custom_build.a13da4feb`
- SHA256: `3633C3E609C8CE2F9BAE334A9C7E75C7F974DE3AF0415AB4A8050A625A15A7A5`

Required on a fresh exact checkout:
1. no foreign Godot processes and >=10 GB free RAM;
2. cold import succeeds with no parse/script/compile errors;
3. launch-options contract succeeds;
4. M6, ResourceMining, P4 reconnect and MVP7 native/Construction recovery regressions succeed;
5. LIVE2 focused compatibility succeeds, including the same-M0 Construction bootstrap regression;
6. run `tools/live3/run_live3_product_recovery.ps1` from a fresh verifier evidence directory;
7. require report `outcome=PASS`, exact product HEAD/TREE, stable Item Graph/Resource/Construction fingerprints across planned server restart, stable player entity IDs, reconnect epoch advance, and post-restart gameplay/remote stream continuation;
8. require final tracked source clean, no Godot process leak, and UDP 24580 free.

Do not use implementer PASS as a substitute for rerunning these gates. Existing run 37254326876 is corroboration only.

## Verdict

- all independent gates pass on exact frozen subject: `VERIFIED`
- reproducible product failure: `FIX_REQUIRED`
- host/evidence/identity gap: `EVIDENCE_GAP`

Publish only verifier control evidence on the verify branch. Do not modify product source or PR merge state.
