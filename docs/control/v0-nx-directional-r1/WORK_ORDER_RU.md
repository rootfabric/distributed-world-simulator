# V0→NX — bounded dependency revalidation R1

Work Order: `V0-NX-MVP6-DIRECTIONAL-20260916-R1`.
Risk: HIGH (canonical dependency/authority boundary); no runtime or architecture ownership change is authorized.
State: IN_PROGRESS. User requested investigation and closure of the V0→NX directional drift. Merge into canonical main remains a separate human gate.

## Exact inputs

- main: `6982a563dd0c88c81449566131852c601ae89868`, tree `97c61acc96f507d71b6883fbdeef486c08b1113d` (A9 merge).
- producer V0: `feature/v0-mvp-playable-seamless-planet-r1` at `9a4d4257f177af16c0a4274be357717c45c169fe`.
- consumer NX: `feature/h0-2-nx-c1-owner-authority-r3` at `1a56fe0e845c941f14ce7b9296ee939e9d0ca8bc`.
- NX passport: `config/control/branches/feature__h0-2-nx-c1-owner-authority-r3.v1.json`, blob `c3af1974228c9ee5c34bf4d54c72896c99fc4d1a`.
- critical watched dependency: `scripts/runtime/networked_gameplay/m4/canonical_multiplayer_item_graph_service.gd`, producer blob `44841fb3719b1cf36fd5afdfc0f8a0e4d0eacb30`.
- failed main PC: run `35087316274`, job `104765092138`; diagnostic run `35087498993` proves V0→NX CRITICAL_WATCH_HIT/UNRESOLVED.

## Design / Repair Map

Problem: the active V0 producer added opt-in native actor item carrying to the stable M4 facade at 1698d4ea and repaired replay attribution/epoch admission at a54521f2. Existing main-owned clearances bind historical P4 producer/consumer identities and cannot authorize this new dependency.
Canonical owners stay M4 Item Graph for items, SM1 for authority decisions, NX for locomotion/prediction/rollback presentation. A9 does not own this dependency and must not be rewritten.

Selected route: inspect the exact changed facade and its unchanged P5/P4/P3 parents, then revalidate the exact NX runtime leaves and focused suite in a current-main composition both without and with the single V0 facade replacement. Separately rerun V0 native item/security and inherited player/material tests. Only verified compatibility plus independent review can support a new narrowly fenced clearance proposal.

Rejected routes: suppress NX globally; remove critical_watched_paths; weaken RED; reuse P4 approval as MVP6 review; declare diagnostic --no-fail-on-red a PASS; modify active V0/NX branches; accept a new producer blob without fresh evidence.

## Scope

A control candidate may add this Work Order, a compatibility verifier/test and evidence under `docs/control/v0-nx-directional-r1/` and `validation/control/v0_nx_directional_r1/`, a validation-only workflow, and append one exact record to `config/control/directional-watch-clearances.v1.json` after independent review. Existing clearances must remain unchanged. No registry/scheduler/risk-policy change, source rebase, force push, runtime mutation or branch deletion.

## Required predicates

1. Exact input identity and complete V0→NX watched hit set verified.
2. Matched current-main+NX baseline/treatment Godot tests use pinned Linux double SHA bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7; source manifests differ only at the watched facade.
3. Exact V0 native tests pass; evidence does not imply MVP6 whole-product acceptance, NX.C1 acceptance or network production readiness.
4. Existing clearance resolver passes positive identity case and rejects stale ancestry, producer blob, consumer head/passport and expanded hit sets. Unmerged checkout cannot self-clear canonical main.
5. Full Harness and standard/directional auditors exercised at an explicitly NON_AUTHORIZING candidate-main projection; baseline RED retained as evidence, no policy bypass.
6. Independent fresh review and evidence verification on frozen candidate; later evidence published separately.
7. Human merge gate, then canonical-main full Project Control SUCCESS. Until that last step global drift is NOT CLOSED.

## Resume anchor

Last completed: exact main/V0/NX identities read; root cause and existing fail-closed clearance contract inspected.
Next: publish and execute bounded compatibility verifier; inspect artifact bytes; create clearance proposal only if evidence supports it; independent review; human merge gate.
Recovery: GitHub connector by repository/ref/path/run/artifact. No ad-hoc clone or transport export workaround. Never reuse a historical PASS for changed source.
