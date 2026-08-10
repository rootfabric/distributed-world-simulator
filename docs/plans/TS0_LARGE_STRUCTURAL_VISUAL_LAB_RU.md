# TS0 — Large Structural Visual Lab

**Global revision:** `GLOBAL-P0-2026-08-10-R2`  
**Branch family:** `T / Construction`  
**Planned branch:** `feature/ts0-large-structural-visual-lab`  
**Preferred base:** `T1A.3 SOURCE_ACCEPTED @ 5e051f67bf6987a354de5b565da1448be6b0b4db`  
**Status:** `IMPLEMENTATION READY / PRE-T2 EXPERIMENTAL`

## 1. Зачем нужен TS0

TS0 проверяет отдельно от gameplay composition, как существующая Construction representation architecture ведёт себя на больших простых объектах:

```text
10k blocks
100k blocks
1M blocks research probe
```

Контрольные формы:

```text
cube
stepped pyramid
```

TS0 не добавляет приборы, контейнеры, utilities или сложный gameplay. Это visual/scale evidence для C21/C22/C24 и будущего T2.0.

## 2. Почему ветка идёт параллельно T1A.4

Текущий T frontier:

```text
T1A.4 Interactive Fixture Binding
```

TS0 не использует T1A.4 interactive semantics, поэтому не должен наследовать незавершённый candidate.

Правильная схема:

```text
T1A.3 ACCEPTED
      │
      ├── T1A.4 -> T1A.5 -> ...
      │
      └── TS0.0 -> TS0.1 -> TS0.2 -> TS0.3 -> TS0.4
```

## 3. Создание ветки

После получения актуального repository checkout:

```powershell
git fetch origin --prune

git switch --detach 5e051f67bf6987a354de5b565da1448be6b0b4db
git switch -c feature/ts0-large-structural-visual-lab
```

Затем перенести **только global P0 R2 sync**, не T1A.4 gameplay commits:

```powershell
git cherry-pick 3a0d2ecb56da26b980a04ed44992e10335626e52
git cherry-pick a926c71fa9e048f876a4256c541bdfee1fbe2e4d
```

После появления TS0 plan/config commits в `main` их также можно cherry-pick как documentation-only bootstrap.

Проверить:

```powershell
git status --short
git log --oneline -5
```

Обязательное состояние перед implementation:

```text
base ancestry contains T1A.3 accepted commit
GLOBAL revision == GLOBAL-P0-2026-08-10-R2
no T1A.4 implementation dependency
working tree clean
```

## 4. Что переиспользовать прежде всего

Перед созданием нового runtime backend провести inventory существующих contracts:

```text
C21 large-scale construct acceptance
C22 compiled construct proxy / HLOD
C24 GPU-ready proxy mesh backend
ConstructSnapshot / ConstructAggregate
existing section/dirty invalidation
existing visual profile / representation adapters where applicable
```

Правило:

```text
reuse first
adapter second
new backend only after a documented gap
```

## 5. TS0.0 — Deterministic Large Structural Fixtures

Сначала никаких красивых assets.

Один тип блока:

```text
structural cube
```

Предлагаемый визуальный размер:

```text
block_size_m = 2.0
```

Это даёт хорошо воспринимаемый масштаб:

```text
46 blocks = 92 m
100 blocks = 200 m
```

Минимальные fixture profiles:

```text
CUBE_10K
PYRAMID_10K
CUBE_100K
PYRAMID_100K
CUBE_1M_RESEARCH
```

Контрольные значения:

```text
CUBE_10K:
22 x 22 x 22 = 10 648 blocks

CUBE_100K:
46 x 46 x 46 = 97 336 blocks

CUBE_1M_RESEARCH:
100 x 100 x 100 = 1 000 000 blocks
```

Для stepped pyramid использовать deterministic level formula и зафиксировать expected count в config/tests.

Каждый block имеет stable canonical part identity.

Не допускается представлять весь canonical construct только одним demo mesh без part identities.

## 6. Fixture contract

Machine-readable fixture должен содержать минимум:

```text
fixture_id
shape
seed/version
block_size_m
dimensions or levels
expected_part_count
construct_id
part_identity_policy
section_policy_reference
expected canonical checksum
```

Важно:

```text
fixture definition != runtime mesh
```

## 7. TS0.1 — 10k Visual Proof

Собрать graphical lab:

```text
scenes/labs/construction/ts0_large_structural_visual_lab.tscn
```

Нужны два observer mode:

```text
walk / character-like camera
free-flight / orbit camera
```

Минимальный visual proof:

```text
near:
individual block structure readable

mid:
compiled sections replace unnecessary individual detail

far:
HLOD/proxy represents whole object cheaply
```

Полезные переключатели:

```text
1 CUBE_10K
2 PYRAMID_10K
3 CUBE_100K
4 PYRAMID_100K
5 CUBE_1M_RESEARCH
```

## 8. Debug presentation modes

Добавить presentation-only режимы:

```text
SOLID
BLOCK_BOUNDARIES
SECTION_BOUNDARIES
HLOD_LEVELS
DIRTY_REBUILD_REGIONS
STATISTICS
```

Они не входят в canonical checksum.

`BLOCK_BOUNDARIES` особенно нужен, потому что greedy/compiled mesh большого куба иначе визуально выглядит как один гладкий короб и скрывает semantic block structure.

## 9. Telemetry

На экране и в machine-readable report:

```text
fixture_id
construct_id
canonical_revision
canonical_checksum
canonical_part_count
active_runtime_nodes
visible_sections
compiled_mesh_artifacts
triangles
draw_calls
mesh_build_ms
upload_ms
estimated CPU bytes
estimated GPU/resource bytes
current representation mode
observer distance
last dirty section count
last rebuild section count
```

Главное доказательство:

```text
100k canonical parts
    !=
100k runtime nodes
    !=
100k draw calls
```

## 10. TS0.2 — 100k Visual Scale Gate

Это основной acceptance TS0.

Проверить минимум:

```text
CUBE_100K
PYRAMID_100K
```

Acceptance не должен задавать случайный жёсткий FPS, зависящий от GPU машины. Вместо этого фиксируются структурные и измеримые условия:

```text
canonical_part_count >= 90 000
runtime node count bounded and far below part count
compiled representation used
near/mid/far transition observable
canonical checksum invariant across representation modes
headless canonical build/query does not require mesh assets
no unbounded artifact/cache growth during repeated mode switches
```

Performance report сохраняет реальные FPS/frame time/draw calls как evidence, но hardware-dependent значения сначала не превращаются в universal contract.

## 11. TS0.3 — Local Mutation / Dirty Rebuild

На `CUBE_100K` сделать deterministic mutation fixture:

```text
remove 10 x 10 x 10 corner volume
= 1000 blocks
```

Проверить:

```text
construct revision changes
removed identities disappear
unaffected identities remain stable
only intersecting sections dirty
whole construct not rebuilt
far proxy invalidated/rebuilt correctly
near state after return matches canonical state
```

Сохранить telemetry before/after.

## 12. TS0.4 — 1M Research Ceiling Probe

Профиль:

```text
CUBE_1M_RESEARCH
100 x 100 x 100
1 000 000 parts
```

Это не acceptance blocker.

Результат классифицировать:

```text
PASSABLE
DEGRADED
CURRENT_CEILING_EXCEEDED
```

Независимо от результата TS0.2 может быть SOURCE_ACCEPTED при хорошем 100k proof.

## 13. P0 non-ownership

TS0 категорически не создаёт:

```text
WorldAddress
Spatial Domain Fabric
AuthorityRegionId
InterestRegionId
MaterialDefinitionId
WorldOperation / WorldTransactionPlan
network replication owner
persistence model
global work scheduler
```

Инварианты:

```text
section_id != WorldAddress
section_id != AuthorityRegionId
section_id != InterestRegionId
part identity != mesh identity
HLOD != canonical state
visual block material != MaterialDefinitionId
lab build budget != World Work / Budget Fabric
```

## 14. Локальные lab budgets

Если async build требует throttling, допустимы только clearly-local knobs:

```text
max_mesh_builds_per_frame
max_upload_bytes_per_frame
max_active_build_jobs
```

Они не получают global identity/API ownership и позднее заменяются adapter-ом к общему Work/Budget Fabric.

## 15. Proposed file layout

```text
config/construction/ts0-large-structural-visual-lab.v1.json

docs/plans/TS0_LARGE_STRUCTURAL_VISUAL_LAB_RU.md

tests/construction/ts0/
  ts0_fixture_contract_acceptance.gd
  ts0_representation_invariance_acceptance.gd
  ts0_dirty_section_acceptance.gd

scripts/labs/t1/ts0/
  ts0_large_structural_fixture_builder.gd
  ts0_large_structural_visual_lab.gd
  ts0_runtime_telemetry.gd
  ts0_debug_overlay.gd

scenes/labs/construction/
  ts0_large_structural_visual_lab.tscn

RUN_TS0_FIXTURE_TESTS.ps1
RUN_TS0_100K_VISUAL_GATE.ps1
PLAY_TS0_LARGE_STRUCTURAL_VISUAL_LAB.ps1
```

Имена implementation files можно скорректировать под существующую layout проекта, но domain/presentation separation сохраняется.

## 16. Первый implementation slice

Первый commit после bootstrap должен быть маленьким:

```text
TS0.0 fixture contract only
```

Он должен:

1. создать config с профилями;
2. deterministic builder для cube/pyramid;
3. создать canonical identities без renderer;
4. проверить counts/checksums;
5. не добавлять graphical backend.

Только после focused PASS переходить к TS0.1 graphical presenter.

## 17. Acceptance ladder

```text
TS0.0 fixture contracts PASS
        ↓
TS0.1 10k graphical proof PASS
        ↓
TS0.2 100k visual scale gate PASS
        ↓
TS0.3 local mutation / dirty rebuild PASS
        ↓
TS0 SOURCE_ACCEPTED
        │
        └── TS0.4 1M research may continue independently
```

## 18. Handoff в T2

После TS0:

```text
synthetic scale risk reduced
        ↓
T2.0 uses same representation path
on a real heterogeneous large base/station
```

TS0 никогда не заменяет T2.0 real-construct acceptance.
