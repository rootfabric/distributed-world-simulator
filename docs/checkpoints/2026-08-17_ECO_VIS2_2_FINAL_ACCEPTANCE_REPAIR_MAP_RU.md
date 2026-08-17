# ECO VIS2.2 — Final Acceptance Repair Map / Design Brief

Дата: 2026-08-17

Ветка:

`feature/eco-vis2-2-replicated-causal-observatory`

Fresh-review input HEAD:

`48e4700ef64b5ba233407cba46d2c076335eb87a`

Accepted VIS2.1-V base:

`731f9d892e7747d391a79b88b24bae69769b3340`

Статус:

`REPAIR_MAP_READY / IMPLEMENTATION NOT YET ACCEPTED`

## Risk

`MEDIUM`

Причина: bounded internal research runtime logic, local cache/rewind orchestration, presentation-only replicated observatory and acceptance harness. Production ecology authority, persistence, networking and canonical world ownership не меняются.

## Problem statement

Fresh independent review VIS2.2 на `48e4700e...` подтвердил causal/CRN architecture, canonical trace boundary, aggregate model, one-visible-Treatment rendering and Ubuntu graphical/runtime evidence, но вернул `FAIL` для формального закрытия этапа из-за acceptance-surface gaps:

1. D integrated lab не реализует rewind через Left;
2. PairSet reject'ит request ниже common cache floor вместо clamp;
3. aggregate rewind/truncate/panel/rerender не собраны в один integrated path;
4. действующий B R2 gate не доказывает aggregate rolling window >64;
5. D test не доказывает неизменность всех replicate traces/maps при presentation selection;
6. Ubuntu runner проверяет только D, а не полный accepted ancestry VIS2.1-V -> A -> B R2 -> C -> D;
7. Ubuntu runner не имеет timeout fail-closed semantics;
8. superseded red B/B-R1 tests и runners остаются в active test surface;
9. frozen VIS2.2 plan всё ещё требует Windows, хотя canonical validation platform для текущего этапа выбран Ubuntu/Linux exact-engine.

## Current behavior

- `PairSet.rewind_to_cached_generation()` возвращает `GENERATION_NOT_IN_COMMON_CACHE`, если request ниже common floor.
- `eco_vis2_2_integrated_observatory_lab_r1.gd` поглощает `KEY_LEFT` без rewind.
- D знает только forward `advance_replicated_to()` и restart-from-fork.
- AggregateModel уже имеет `truncate_after()` и bounded `SERIES_WINDOW=64`, но D rewind его не вызывает.
- Canonical B R2 adapter path исправлен и должен остаться единственным active B acceptance path.

## Desired behavior

### Integrated rewind

`Left` и публичный `rewind_replicated_to(target_generation)` должны:

- использовать common cache floor всех Control/Treatment runners;
- clamp request ниже floor к exact common floor;
- rewind/truncate только Treatment futures;
- сохранять Control futures;
- сохранять CRN roots;
- truncate aggregate history до effective generation;
- обновлять visible generation, panel и выбранный Treatment renderer;
- не replay from immutable fork, если effective generation доступно в cache.

После rewind новый Treatment profile/intensity должен начинаться с `effective_generation + 1` через существующий PairSet `set_treatment()` contract.

### Acceptance

Один canonical Ubuntu/Linux exact-engine runner должен выполнять fresh chain:

`VIS2.1 accepted regressions -> VIS2.2-A -> VIS2.2-B R2 -> VIS2.2-C -> VIS2.2-D`

и fail closed на:

- wrong exact Godot identity;
- parser/runtime errors;
- non-zero exit;
- timeout;
- missing PASS marker;
- ObjectDB/RID/resource/StringName leak diagnostics.

## Alternatives considered

1. Replay from fork on every Left — rejected: violates bounded-cache design and Control-future preservation.
2. Clamp only in D while PairSet keeps rejecting — rejected: common-floor semantics belong to the PairSet orchestration owner and sibling callers would remain inconsistent.
3. Rebuild aggregate from fork after rewind — rejected: unnecessary replay and violates bounded acceptance intent.
4. Keep old red B tests as normal tests with comments — rejected: active test tree would still contain known failing executable contracts.
5. Restore Windows as mandatory platform — rejected for this research stage by explicit project decision; exact Godot identity remains mandatory, platform is Ubuntu/Linux native.

## Selected design

- Canonical clamp location: `eco_vis2_2_replicate_pair_set.gd::rewind_to_cached_generation()`.
- Canonical integrated rewind location: `eco_vis2_2_integrated_observatory_lab_r1.gd::rewind_replicated_to()`.
- Aggregate truncation remains owned by `eco_vis2_2_aggregate_effect_model.gd`; no aggregate-model mutation is required.
- Canonical trace boundary remains `eco_vis2_2_pair_trace_adapter.gd -> eco_vis2_1_trace_adapter.gd`.
- B R2 becomes the only active VIS2.2-B test.
- New `RUN_ECO_VIS2_2_TESTS.sh` becomes canonical VIS2.2 Ubuntu acceptance entrypoint.

## Affected module

- VIS2.2 PairSet orchestration;
- VIS2.2-D integrated lab;
- VIS2.2 B R2 and D tests;
- VIS2.2 acceptance runners/docs.

## Canonical owner

Research/observer branch-local VIS2.2 implementation. No production foundation ownership change.

Permanent boundary remains:

`research ecology state != visual observer state != production/network authority`

## Entry points

- `PairSet.rewind_to_cached_generation()`
- `VIS2.2-D.rewind_replicated_to()`
- D `KEY_LEFT`
- `PairSet.set_treatment()` after rewind
- `AggregateModel.truncate_after()`
- `RUN_ECO_VIS2_2_TESTS.sh`

## Callers / callees

Callers:

- VIS2.2-D keyboard/UI;
- automated D acceptance test;
- B R2 canonical aggregate test.

Callees:

- TreatmentRunner cached rewind/truncation;
- AggregateModel truncation;
- ObservatoryPanel refresh;
- VIS2.1-V realtime LOD selected renderer.

## Sibling paths checked

- forward advance remains unchanged;
- restart-from-fork remains unchanged;
- presentation-only replicate selection remains simulation-free;
- treatment switch/rebranch keeps root and Control future semantics;
- VIS2.2-A root derivation and PairTraceAdapter canonicalization remain unchanged.

## Existing tests

- VIS2.2-A PairSet 131 assertions;
- VIS2.2-B R2 canonical real adapter path 218 assertions in previous Windows evidence;
- VIS2.2-C panel 42 assertions;
- VIS2.2-D Ubuntu 63 assertions;
- accepted VIS2.1-V regression chain.

## Missing tests to add

- PairSet/D request below common floor clamps exactly;
- D rewind truncates aggregate and Treatment future while preserving Control future/root;
- rebranch after rewind starts at effective+1;
- B R2 aggregate >64 true rolling eviction and fail-closed truncate below floor;
- R0/R3/R1 presentation selection leaves all Control/Treatment generation maps byte-identical;
- full Ubuntu ancestry runner with timeout.

## Public or internal contracts

Internal research contracts only. No production API/schema change.

## Expected shipped behavior

Research observatory supports bounded forward/rewind/rebranch replicated causal inspection with one visible Treatment world and deterministic aggregate evidence.

## Relevant history / evidence

- initial B real integration failure exposed raw Treatment trace boundary;
- B R2 canonical adapter repaired that defect;
- D Ubuntu parser/runtime passed on exact `4.7.1.stable.double.custom_build.a13da4feb`;
- D graphical run proved one visible field and active aggregate panel;
- fresh whole-VIS2.2 review found acceptance gaps listed above, not a new causal-simulation defect.

## Root cause hypothesis

VIS2.2 was built incrementally A->B->C->D. Lower-layer rewind/bounded capabilities existed, but final D composition and Linux acceptance harness did not yet close all frozen hard invariants. Superseded B artifacts remained active because repair history was preserved as executable files rather than Git-only history/evidence.

## Canonical fix location

Fix semantics at their owners:

- clamp in PairSet;
- integrated state composition in D;
- coverage in current R2/D tests;
- platform/ancestry policy in canonical Linux acceptance runner and plan.

## Why this is not symptom patching

The repair does not special-case a failing assertion. It closes the missing owner-level operation (bounded rewind), composes all dependent state transitions atomically at D, verifies sibling invariants, removes superseded executable surfaces, and creates one canonical acceptance path matching the declared platform policy.

## Validation plan

1. exact branch freshness check;
2. exact Godot `4.7.1.stable.double.custom_build.a13da4feb`;
3. parser preflight for changed GDScript tests/runtime;
4. focused B R2 and D tests;
5. full Ubuntu VIS2.2 ancestry gate;
6. strict shutdown diagnostics clean;
7. bounded post-build critique;
8. evidence checkpoint;
9. fresh independent review on exact tested HEAD.

Не merge. Не self-accept. Formal VIS2.2 closure requires a subsequent fresh independent PASS.
