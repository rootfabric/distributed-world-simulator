# V0-P2 — reconnectable shared state / Design Brief

**Branch:** `feature/v0-p2-reconnectable-shared-state`  
**Provisional base:** `bf24bb7cbea6fcf3aa48e341ce634f7be4146bef`  
**Runtime implementation provenance entering P2:** `e754d2258451e605d25932c5dc00207f736a3348`  
**P1 real-UDP validation provenance:** `782b57cba36a74c94dded283de4c030057f5559b` — 41 assertions, 0 failures  
**Risk:** HIGH  
**Status:** PROVISIONAL IMPLEMENTATION CANDIDATE / NOT PROMOTABLE BEFORE P1 INDEPENDENT PASS + CANONICAL V0 CONTROL ACTIVATION

## Goal of this first slice

Remove hidden canonical Item Graph mutation from snapshot/persistence reads and make durable slot migration explicit, revisioned and testable. At the same time replace the stage-specific P1 product composition root with a generic V0 bootstrap without changing launch semantics.

This is deliberately smaller than the complete P2 checkpoint. Composite cross-domain fingerprint and full Construction+Item Graph reconnect acceptance remain later P2 slices after this first runtime candidate is locally verified.

## Finding P2-R1 — snapshot/export is impure

Current derived M4 service calls `_normalize_slot_locations()` inside `create_snapshot()`.

Consequences:

- a canonical read may mutate `location.slot_index`;
- checksum can change without an explicit command;
- `revision/tick` can remain unchanged while representation changes;
- `export_durable_state()` inherits the same side effect because it calls `create_snapshot()`.

## Finding P2-R2 — migration has no explicit restore boundary

Base durable restore installs validated collections and restores stored revision/tick. Legacy slotless inventory/container state is then normalized only when a later snapshot/read occurs.

Required correction:

1. `create_snapshot()` becomes a pure delegation to the base serializer.
2. `export_durable_state()` becomes pure as a consequence.
3. Derived `restore_durable_state()` calls base validation/restore first.
4. Capture a pure pre-migration snapshot using `super.create_snapshot()`.
5. Run deterministic `_normalize_slot_locations()` exactly once as restore migration.
6. Capture a pure normalized snapshot.
7. If checksum changed, advance canonical `_revision` and `_tick` exactly once.
8. If checksum did not change, preserve stored revision/tick exactly.
9. Return migration diagnostics (`migrated`, before/after revision/tick, changed item/owner counts, checksums).
10. Any subsequent snapshot/export must be idempotent and must not advance revision/tick.

## Finding P2-R3 — stage-specific product bootstrap

`main.tscn` currently points to `v0_p1_simulator_app.gd`.

Correction:

- add `scripts/app/v0_simulator_app.gd` as the generic product bootstrap;
- preserve current validated `--network-mvp` -> inherited playable-sandbox capability bridge;
- keep launch-option validation distinct from legacy `--network-playground`;
- point `main.tscn` to the generic bootstrap;
- retain the P1 wrapper as historical compatibility source for now;
- no protocol, authority, Item Graph command, Construction or presentation behavior change.

## Focused regression contract

The first candidate must prove:

- repeated `create_snapshot()` returns the same checksum and preserves revision/tick;
- repeated `export_durable_state()` returns the same checksum and preserves revision/tick;
- a slotless legacy durable fixture validates, restores and migrates exactly once;
- migration advances revision/tick exactly once;
- deterministic inventory/container `slot_index` values exist after migration;
- immediate second snapshot/export does not mutate or advance state;
- a current slot-aware durable fixture restores with `migrated=false` and preserves stored revision/tick;
- generic V0 bootstrap is the `main.tscn` owner;
- product bootstrap still enables inherited playable sandbox only after successful launch-option validation;
- mixed `--network-mvp + --network-playground` remains rejected by LaunchOptions;
- all existing P1 regressions remain GREEN.

## First local operator gate

After the first runtime-affecting exact SHA is frozen:

1. focused P2 purity/migration test;
2. complete `RUN_V0_P1_TESTS.ps1` regression;
3. dedicated server + graphical A/B startup via the normal V0 launcher;
4. operator confirms movement, second-player visibility, inventory, pickup and external container still work;
5. focused real UDP reconnect gate;
6. checkout remains clean and logs contain no parser/startup/runtime failure markers.

No further P2 gameplay/runtime slice should be stacked before this gate is observed.

## Non-goals of this slice

- no resource/mining commands;
- no Construction economy;
- no equipment/tool presentation;
- no terrain mutation;
- no network authority/protocol redesign;
- no new canonical owner or second Item Graph;
- no promotion into product frontier before the missing independent/control gates are resolved.
