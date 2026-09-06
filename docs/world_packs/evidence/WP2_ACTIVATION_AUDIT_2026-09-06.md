# WP2 ACTIVATION AUDIT — 2026-09-06

Live-проверка шести gates перед любым WP2 runtime activation.
Все refs проверены `git fetch --all --prune` в день аудита; чат не использован как source of truth.

## Live refs (на момент аудита)

```text
origin/main                                          fa2b6024481ea5a796ec9c7b0e2f9885f1a82c91
origin/integration/world-packs-wp1-2-foundation-r1   c99bbd7233633f49ebd9fa1e2a74fcdb551c7b05
origin/control/world-packs-parallel-r1               2120e51a355a9e5b18f71449de59ab13b9cbbde3
```

Ветки актуальны и совпадают с последним наблюдавшимся состоянием (foundation
implementation d9822ac9, closure c99bbd72, controller R2 repair 2120e51a).

## GATE A — P7 formal acceptance: CLOSED

Live evidence на `origin/main@fa2b602`:

- `config/control/harness/v0-p7-7-formal-closure-frontier.v1.json`:
  `status = FULL_GATE_EXACT_VALIDATED_REVIEWER_NEXT`, `p7_7_complete_merged = false`,
  full gate 2032/2032 GREEN, но reviewer = NEXT, verifier = BLOCKED_UNTIL_REVIEWER_PASS,
  human merge = BLOCKED.
- `config/control/branches/control__v0-p7-7-activation-r1.v1.json`:
  «P7.7 runtime MERGED via PR #487 (merge dc5d4a4d)», но
  «COMPLETE_MERGED is not declared before that gate» и
  rotation-evidence: `P7.7 MERGED_BUT_NOT_CLOSED; COMPLETE_MERGED NOT DECLARED`.
- Registry: `control_checkpoint = V0 P7.7 GRAPHICAL_DIGGING_SLICE is active`,
  `p7_7.state = IN_PROGRESS`.

Вердикт: P7.7 runtime merged, но formal/canonical P7 acceptance ОТСУТСТВУЕТ.
WORLD_PACKS_ROADMAP WP2.0 dependency «Main-owned P7.7 COMPLETE_MERGED + formal P7
acceptance» НЕ выполнена. GATE A = CLOSED.

## GATE B — WORLDGEN executable activation: CLOSED

`docs/plans/WORLDGEN1_PROCEDURAL_MATTER_TERRAIN_ROADMAP_RU.md` на main:

```text
Status: PLANNED / DESIGN-ONLY UNTIL ACTIVATION GATE
Gate B — EXECUTABLE_WORLDGEN1: earliest activation =
  P7.7 COMPLETE_MERGED + V0_P7_BOUNDED_TERRAIN_MUTATION formally ACCEPTED +
  exact Matter generation/materialization/mutation/representation boundaries frozen
```

Ни одно из условий Gate B не выполнено (см. GATE A). Stable WORLDGEN contract
(seed / generator version / PlanetGenerationProfile / FeatureCatalog / body-fixed
frame как executable) отсутствует. GATE B = CLOSED → WP2 production integration
запрещена; допустима только contract preparation.

## GATE C — Matter catalog: OPEN (read-only input available)

Фактический canonical catalog на `origin/main`
(`scripts/simulation/matter/catalog/matter_material_catalog.gd`) содержит ровно:

```text
matter/regolith-loose
matter/regolith-compacted
matter/basalt
matter/fractured-basalt
matter/water-ice
matter/iron-nickel-ore
matter/silicate-waste
```

Ранее наблюдавшиеся ID подтверждены live; новые ID (iron-nickel-ore,
silicate-waste) включены. Read-only presentation input определён как:
material id + composition + surface state + revision (+ optional exposure
derived state). WORLD PACKS не пишет в Matter. GATE C = OPEN (для read-only).

## GATE D — Representation layer: OPEN (owner exists, WP2 подключается после boundary)

Representation ownership на main: `scripts/simulation/representation/**`
(matter multiresolution field builder, representation invalidation через P7.7
RL paths; RL0/RL1/RL3 contracts приняты ранее). WP2 не создаёт terrain mesh /
collision / chunk authority; adapter подключается ПОСЛЕ derived representation
surface sample. GATE D = OPEN (WP2 = post-boundary consumer).

## GATE E — Coordinate/surface frame: OPEN (contract-level)

Canonical body-fixed позиция/нормаль присутствуют в Matter/representation
контрактах; полный произвольный body frame (asteroid, cave, inward surface)
остаётся для Proof B/WP3.0. WP2 contract закладывает: normal != gravity,
передаются раздельно, gravity опционален, никаких global +Y / radial-only
ассумпций. GATE E = OPEN на contract level, закрыт для irregular-body runtime.

## GATE F — Runtime slot / project control: CLOSED

Canonical main держит active frontier V0 P7.7 closure train (reviewer →
verifier → human merge gate). WP-контроллер
(`control/world-packs-parallel-r1@2120e51a`) и foundation evidence явно
фиксируют: WORLD PACKS заморожен как parallel consumer-only lane до готовности
main/P7/WORLDGEN; runtime lease для WP2 не выдан. GATE F = CLOSED для runtime,
OPEN для non-runtime (contracts/fixtures/mocks/tests/docs).

## DECISION

```text
WP2_RUNTIME_AUTHORIZED           — НЕТ
WP2_CONTRACT_ONLY_AUTHORIZED     — ДА (как safe parallel work при заблокированном runtime)
WP2_BLOCKED                      — ДА, для runtime activation
```

Итоговый вердикт: **WP2 RUNTIME ACTIVATION = BLOCKED**;
**contract-only preparation = AUTHORIZED** (без runtime lease, без Godot runtime
integration, без смены ownership). Машиночитаемое состояние:
`config/world_packs/wp2_activation_state.v1.json`.

## Resume condition

WP2 runtime activation возможна только после live-перепроверки:

```text
P7.7 COMPLETE_MERGED объявлён на main
+ formal P7 acceptance зафиксирован
+ WORLDGEN1 EXECUTABLE activation gate открыт
+ main-owned scheduler slot для WP2 runtime train
```
