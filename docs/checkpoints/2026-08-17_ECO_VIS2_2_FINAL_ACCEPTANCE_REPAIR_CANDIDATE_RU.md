# ECO VIS2.2 — Final Acceptance Repair Candidate

Дата: 2026-08-17

Ветка:

`feature/eco-vis2-2-replicated-causal-observatory`

Fresh-review FAIL input HEAD:

`48e4700ef64b5ba233407cba46d2c076335eb87a`

Final-repair code-under-test HEAD:

`f22cffc27e3aee9833837d42849db6ce9650232c`

Accepted VIS2.1-V base:

`731f9d892e7747d391a79b88b24bae69769b3340`

Статус:

`IMPLEMENTED / LOCAL_EXACT_ENGINE_FOCUSED_PASS / FULL UBUNTU ECOLOGY GATE REQUIRED / NOT ACCEPTED`

Не merge. Не self-accept. Formal VIS2.2 closure требует полного Ubuntu gate, graphical rewind confirmation и затем fresh independent review на exact tested evidence HEAD.

## 1. Repair map

До production mutation был зафиксирован Design Brief / Repair Map:

`docs/checkpoints/2026-08-17_ECO_VIS2_2_FINAL_ACCEPTANCE_REPAIR_MAP_RU.md`

Risk class: `MEDIUM`.

Repair закрывает только bounded research runtime/presentation/acceptance surface. Production ecology authority, persistence, networking и canonical world ownership не менялись.

## 2. Implemented repair

### PairSet common-floor clamp

`scripts/labs/ecology/eco_vis2_2_replicate_pair_set.gd`

Blob:

`a4451246307e4b11b4fd37a59ab6f1023753bd44`

`rewind_to_cached_generation()` теперь:

- reject'ит только forward rewind / unavailable cache;
- вычисляет common oldest cached generation;
- clamp'ит request ниже общего floor к exact common floor;
- rewind/truncate выполняет только для Treatment runners;
- Control future не rewind'ится;
- CRN roots проверяются на неизменность;
- возвращает `requested_generation`, effective `generation`, `clamped`, common floor.

### Integrated D bounded rewind

`scripts/labs/ecology/eco_vis2_2_integrated_observatory_lab_r1.gd`

Blob:

`6f337c5d6c97bfa60733ebd684eb365a56d0b30a`

Добавлен `rewind_replicated_to()` и `Left` routing:

```text
PairSet common-floor rewind
    -> AggregateModel.truncate_after(effective generation)
    -> visible generation update
    -> panel refresh
    -> selected Treatment realtime rerender
```

Перед mutation D fail-closed проверяет равенство PairSet common floor и aggregate oldest floor.

После rewind сохраняются:

- all replicate roots;
- selected replicate;
- one-visible-Treatment rendering boundary;
- Control futures;
- canonical VIS source state.

### B R2 rolling aggregate acceptance

`tests/research/ecology/test_eco_vis2_2_aggregate_effect_model_r2.gd`

Blob:

`be0730fc71701fb14657bf312a2e1afbc2a95257`

Добавлен deterministic 71-generation aggregate probe:

- true rolling eviction to exactly 64 points;
- expected oldest `fork + 7`;
- latest retained;
- truncate below aggregate floor rejected;
- invalid truncate cannot mutate points/hash;
- truncate exactly at floor succeeds.

Canonical real PairTraceAdapter path сохранён; in-cache rewind дополнительно обязан вернуть `clamped=false`.

### D integrated acceptance expansion

`tests/research/ecology/test_eco_vis2_2_integrated_observatory_lab.gd`

Blob:

`35eb4542ed7d476b620645b8795ccc494ac103c9`

Теперь test покрывает:

- R0 -> R3 -> R1 selection purity для **всех** Control/Treatment generation maps;
- FLOOD effective generation = current+1;
- long advance to G88;
- branch caches <=64;
- aggregate history ==64;
- PairSet common floor == aggregate floor == G25;
- request rewind to fork G20 clamp'ится к G25;
- aggregate future truncates to G25;
- Treatment G88 future erased;
- Control G88 future remains byte-identical;
- roots remain unchanged;
- canonical VIS2.0 source remains unchanged;
- NUTRIENT rebranch after rewind begins at G26;
- Control G39 future is reused, not recomputed;
- at least one Treatment G39 future changes;
- restart/lifecycle invariants remain.

### Superseded red surface removed

Removed from active tree:

- `RUN_ECO_VIS2_2B_TESTS.ps1`;
- `RUN_ECO_VIS2_2B_R1_TESTS.ps1`;
- `tests/research/ecology/test_eco_vis2_2_aggregate_effect_model.gd`;
- `tests/research/ecology/test_eco_vis2_2_aggregate_effect_model_r1.gd`.

Their failure history remains in Git/checkpoint evidence. Active B acceptance path is only R2.

### Canonical Ubuntu full gate

Added:

`RUN_ECO_VIS2_2_TESTS.sh`

Blob:

`7eb608c6e93576e31f2018c43df3256bcd2fd2bb`

It requires exact:

`4.7.1.stable.double.custom_build.a13da4feb`

and in one isolated project executes parser + verbose runtime for:

1. VIS2.1 Control;
2. VIS2.1 Treatment;
3. VIS2.1 Comparator;
4. VIS1.8B;
5. VIS1.9;
6. VIS2.0;
7. VIS2.1 integrated long smoke;
8. independently accepted VIS2.1-V LOD;
9. VIS2.2-A;
10. VIS2.2-B R2;
11. VIS2.2-C;
12. VIS2.2-D.

Every process is bounded by GNU `timeout` and fails closed on non-zero exit, parser/runtime ERROR, missing PASS marker or shutdown leak diagnostics.

The runner self-tests its own shutdown matcher against ObjectDB, singular/plural RID, RID allocations, framebuffer/uniform cache, generic leaked instance, resource still in use and StringName fixtures, plus benign-warning negative control.

### D focused Ubuntu gate

`RUN_ECO_VIS2_2D_UBUNTU_TEST.sh`

Blob:

`0bc15728924fc2cb95c5bcb41ff03255ba1342c6`

Standalone D gate now has the same timeout semantics and matcher self-coverage.

### Graphical Ubuntu launcher

Added:

`RUN_ECO_VIS2_2D_LAB_UBUNTU.sh`

Blob:

`e75ea50bccc8c330721cbaf885e3ed9a7990ee9d`

It launches an isolated D graphical lab and prints the final-repair rewind checklist.

## 3. Contract update

`docs/plans/ECO_VIS2_2_REPLICATED_CAUSAL_OBSERVATORY_RU.md` now records the explicit project decision:

- canonical VIS2.2 acceptance platform = native Ubuntu/Linux;
- exact Godot identity remains mandatory;
- previous Windows evidence remains historical/supplementary but not a hard closure requirement;
- `RUN_ECO_VIS2_2_TESTS.sh` is the canonical full acceptance entrypoint;
- Left is bounded rewind with common-floor clamp;
- aggregate true rolling eviction and graphical rewind are hard invariants.

Permanent boundary is unchanged:

`research ecology state != visual observer state != production/network authority`

## 4. Local exact-engine focused evidence

Available exact local binary:

`/mnt/data/godot471/tools/godot/linux-x86_64/godot.linuxbsd.editor.double.x86_64`

Version:

`4.7.1.stable.double.custom_build.a13da4feb`

The remote changed files were reconstructed locally byte-for-byte and verified by `git hash-object` against GitHub blobs before parser/runtime checks.

### PairSet

Exact blob hash matched:

`a4451246307e4b11b4fd37a59ab6f1023753bd44`

Exact Godot parser: PASS.

Focused exact-engine runtime with deterministic stub runners:

`PAIRSET_FINAL_REPAIR: PASS`

It exercised G20 -> G88, common floor G25, request rewind G20 -> clamp G25, stable roots, preserved Control G88 future and erased Treatment G88 future.

### D integrated script

Exact blob hash matched:

`6f337c5d6c97bfa60733ebd684eb365a56d0b30a`

Exact Godot parser: PASS.

Focused exact-engine D composition runtime:

`D_FINAL_REPAIR_REWIND: PASS`

It exercised D-level common-floor check, PairSet rewind, aggregate truncation and effective visible generation update.

### B R2 test script

Exact blob hash matched:

`be0730fc71701fb14657bf312a2e1afbc2a95257`

Exact Godot parser: PASS.

### D integration test script

Exact blob hash matched:

`35eb4542ed7d476b620645b8795ccc494ac103c9`

Exact Godot parser: PASS.

### Linux runners

`RUN_ECO_VIS2_2_TESTS.sh` exact blob hash matched `7eb608c6...` and `bash -n` passed.

Local self-start against the exact Godot binary reached:

- exact Godot identity: PASS;
- `ECO.VIS2.2 shutdown leak matcher coverage: PASS`;
- superseded red test surface: ABSENT.

The sandbox intentionally lacked the full repository ecology tree, so the full runner then stopped at its fail-closed `Required test missing` check. This is not counted as a full ecology gate pass.

`RUN_ECO_VIS2_2D_UBUNTU_TEST.sh` exact blob hash matched `0bc157...`, `bash -n` passed, exact identity passed and `ECO.VIS2.2-D shutdown leak matcher coverage: PASS` was observed before the expected missing-repository-test stop.

`RUN_ECO_VIS2_2D_LAB_UBUNTU.sh` exact blob hash matched `e75ea50...`; `bash -n` passed.

## 5. Post-build critique

Diff from fresh-review input `48e4700e...` to code-under-test `f22cffc2...` is forward-only and limited to research VIS2.2 code/tests/docs/runners.

No production ecology file, authority owner, persistence schema, networking contract or save format changed.

Architecture critique:

- common-floor clamp is located at PairSet, the canonical orchestration owner;
- D does not invent a second rewind/cache implementation;
- aggregate truncation remains owned by AggregateModel;
- canonical B trace boundary remains PairTraceAdapter -> accepted VIS2.1 TraceAdapter;
- presentation selection remains separate from simulation;
- no second rendered replicated world was introduced;
- stale red tests were removed rather than weakened or ignored;
- no material refactor is required beyond this repair.

Post-build critique result:

`NO_MATERIAL_REFACTOR_REQUIRED`

## 6. Evidence still required before fresh review

The implementation is **not yet formally accepted**.

Required on a real Ubuntu repository worktree at the exact evidence HEAD:

1. full `RUN_ECO_VIS2_2_TESTS.sh` PASS on exact Godot;
2. no strict shutdown diagnostics;
3. graphical D run confirming bounded Left rewind/clamp and one-visible-field invariant;
4. docs-only validation evidence checkpoint;
5. fresh independent review on the exact tested evidence HEAD.

Only after that review returns PASS may VIS2.2 be marked formally closed.
