# ECO VIS2.2 — A Windows validation / B candidate checkpoint

Дата: 2026-08-17

Статус: **VIS2.2-A WINDOWS_RUNTIME_VALIDATED / VIS2.2-B IMPLEMENTED CANDIDATE / WINDOWS B GATE REQUIRED**

Не merge. Не self-accept. VIS2.2 как целый этап остаётся открытым.

## 1. Exact lineage

Repository:

`rootfabric/distributed-world-simulator`

Branch:

`feature/eco-vis2-2-replicated-causal-observatory`

Independently accepted VIS2.1-V base checkpoint:

`731f9d892e7747d391a79b88b24bae69769b3340`

Exact VIS2.2-A Windows-validated candidate:

`950bcdaa2463f1604865aec8580b418c9eb5c1bc`

Exact VIS2.2-B code-under-test before this documentation-only checkpoint:

`b0398c6120eebc536b2b2589571f8f5ffd43ba2a`

B is exactly 3 commits ahead / 0 behind A and adds exactly three files:

- `scripts/labs/ecology/eco_vis2_2_aggregate_effect_model.gd`;
- `tests/research/ecology/test_eco_vis2_2_aggregate_effect_model.gd`;
- `RUN_ECO_VIS2_2B_TESTS.ps1`.

No VIS2.2-A runtime file, accepted VIS2.1/VIS2.1-V file, renderer, scene, CONTROL/TREATMENT runner, CRN derivation or comparator was modified by VIS2.2-B.

## 2. VIS2.2-A exact Windows evidence

The user executed exact candidate:

`950bcdaa2463f1604865aec8580b418c9eb5c1bc`

with exact Windows engine:

`Godot 4.7.1.stable.double.custom_build.a13da4feb`

Observed gate sequence:

- VIS2.2-A shutdown matcher coverage: PASS;
- exact Godot identity: PASS;
- complete independently accepted VIS2.1-V regression gate: PASS;
- VIS2.1 CONTROL: PASS — 82 assertions;
- VIS2.1 TREATMENT: PASS — 96 assertions;
- VIS2.1 comparator: PASS — 82 assertions;
- VIS1.8B: PASS — 51 assertions;
- VIS1.9: PASS — 29 assertions;
- VIS2.0: PASS — 33 assertions;
- VIS2.1 integration long smoke G20..G220: PASS — 57 assertions;
- VIS2.1-V realtime LOD: PASS — 25 assertions;
- VIS2.2-A parser preflight: PASS;
- VIS2.2-A replicated causal runner set: PASS — 131 assertions;
- final VIS2.2-A automated gate: PASS;
- no ObjectDB/RID/resource/StringName shutdown diagnostics were reported.

This confirms the first VIS2.2 slice on Windows exact engine. It does not close VIS2.2 globally.

## 3. VIS2.2-B aggregate model

VIS2.2-B is a pure `RefCounted` observatory model. It does not simulate ecology and has no SceneTree/rendering ownership.

For each generation it consumes the canonical Control/Treatment trace point of every replicate and uses the already accepted VIS2.1 comparator to validate/pair each replicate.

Canonical aggregation order is numeric replicate index `0..N-1` regardless of input array order.

Implemented minimum aggregate fields include:

- replicate count and generation;
- mean / median / min / max population delta;
- mean / median / min / max fitness delta;
- mean unique-genome delta;
- mean birth/death/survivor deltas;
- mean represented-biomass delta;
- mean alpha-share delta;
- positive / zero / negative population counts;
- positive / zero / negative fitness counts;
- deterministic dominant direction and consensus fraction;
- exact per-replicate root and comparator pair hash;
- exact Control/Treatment field hashes and environment revisions;
- deterministic aggregate point hash and bounded series hash.

Floating hash serialization uses fixed `%.12f` formatting after canonicalizing numerical zero. Aggregate calculations use deterministic numeric replicate order.

Aggregate history is bounded to 64 points. Replacing/rebranching a cached future truncates only aggregate future; truncation before the aggregate cache floor is rejected fail-closed.

## 4. VIS2.2-B focused coverage

The focused B test contains both synthetic exact-statistics coverage and integration with the real VIS2.2-A PairSet.

Synthetic coverage verifies:

- exact mean/median/min/max calculations;
- sign counts and dominant direction;
- canonical ordering independent of input replicate order;
- byte-identical aggregate points/hash for reordered input;
- duplicate index rejection;
- invalid/duplicate root fencing;
- wrong branch rejection;
- generation mismatch rejection;
- mixed Treatment-profile rejection;
- invalid input cannot mutate prior aggregate history;
- true 64-point rolling eviction;
- truncate-before-cache-floor rejection without data loss.

Real PairSet coverage verifies:

- common real VIS2.0 fork;
- four real paired replicates;
- fork aggregate effects are exactly zero;
- post-fork aggregate effect appears under DROUGHT;
- aggregate processing cannot mutate roots, fork or canonical source environment;
- restart reproduces byte-identical aggregate points and series hash;
- cached rewind + FLOOD rebranch changes future aggregate identity;
- Control future remains unchanged by Treatment-only rebranch;
- all replicate roots remain unchanged.

## 5. Attached exact-engine preflight

Before publication, the new model and test were parser-checked using the project-provided Linux double build with the same exact engine identity:

`4.7.1.stable.double.custom_build.a13da4feb`

The pure aggregate synthetic runtime probe also passed:

`ECO.VIS2.2-B aggregate effect model: PASS (56 assertions)`

This attached-Linux evidence is supplementary only. Canonical VIS2.2-B acceptance still requires the real Windows B gate.

## 6. VIS2.2-B acceptance harness

`RUN_ECO_VIS2_2B_TESTS.ps1`:

1. verifies exact Godot identity;
2. self-tests the same strict shutdown matcher semantics carried from the accepted VIS2.1-V / Windows-green VIS2.2-A lineage;
3. runs the complete VIS2.2-A gate first;
4. creates an isolated ecology project;
5. runs parser preflight;
6. runs the B smoke with `--verbose`;
7. rejects non-zero exit, parser/runtime errors, missing PASS marker and zero-exit ObjectDB/RID/resource/StringName leak diagnostics.

## 7. Required next evidence

Run exact branch head containing B and execute:

```powershell
.\RUN_ECO_VIS2_2B_TESTS.ps1 -GodotPath $Godot
```

Required final markers:

```text
ECO.VIS2.2-A validated regression gate: PASS
ECO.VIS2.2-B isolated ecology dependency graph: PASS
ECO.VIS2.2-B parser preflight: PASS
ECO.VIS2.2-B aggregate effect model: PASS (... assertions)
ECO.VIS2.2-B automated gate: PASS
```

Only after that may VIS2.2-B be treated as Windows-runtime-validated and VIS2.2-C observatory-panel work proceed.
