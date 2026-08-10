# TS0 — Large Structural Visual Lab

**Global revision:** `GLOBAL-P0-2026-08-10-R2`  
**Branch family:** `T / Construction`  
**Historical TS0 branch:** `feature/ts0-large-structural-visual-lab`  
**Historical bootstrap base:** `T1A.3 SOURCE_ACCEPTED @ 5e051f67bf6987a354de5b565da1448be6b0b4db`  
**Current status:** `TS0.0–TS0.3 EVIDENCE COMPLETE / C22 PRODUCTION CONVERGENCE SOURCE_ACCEPTED / TS0.4 NEXT RESEARCH STAGE`

**Canonical future handoff:** `docs/plans/TS_C22_TO_T2_SCALE_CONVERGENCE_RU.md` in `main`.

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

Фактическая линия развития к текущему моменту:

```text
TS0.0 deterministic fixtures
        ↓
TS0.1 10k graphical proof
        ↓
TS0.2 100k hierarchical visual scale
        ↓
TS0.3 local mutation / dirty rebuild evidence
        ↓
C22 production incremental convergence
        ↓
merge/main integration
        ↓
TS0.4 1M research ceiling
```

## 2. Почему TS0 идёт параллельно T composition/runtime

TS0 изначально стартовал от accepted T1A.3 и не должен был наследовать незавершённые gameplay candidates.

Историческая схема:

```text
T1A.3 ACCEPTED
      │
      ├── T1A.4 -> T1A.5 -> T1A.6 -> T1A.7 -> ...
      │
      └── TS0.0 -> TS0.1 -> TS0.2 -> TS0.3 -> TS0.4
```

Актуальная схема после TS0.3/C22 convergence:

```text
T runtime line
T1A.7 selective replication
        ↓
T1A.7.4 Scale / Soak

        || independent parallel work

TS representation line
C22 production convergence integrated in main
        ↓
TS0.4 1M Research Ceiling

        ↓ both evidence lines converge via PC0
T2.0 real heterogeneous station scale
```

## 3. Branch policy

Старую `feature/ts0-large-structural-visual-lab` использовать как historical evidence lineage, а не как вечную рабочую ветку.

После integration C22 в `main` TS0.4 должен начинаться от свежего `main` в новой ветке, рекомендуемое имя:

```text
feature/ts0-4-1m-research-ceiling
```

Перед началом:

```powershell
git fetch origin --prune
git switch main
git pull --ff-only
git switch -c feature/ts0-4-1m-research-ceiling
```

Обязательное состояние:

```text
C22 production incremental convergence MAIN_INTEGRATED
GLOBAL revision == GLOBAL-P0-2026-08-10-R2
PC0 has no TS ownership conflict
working tree clean
```

## 4. Что переиспользовать прежде всего

Перед созданием нового runtime backend провести inventory существующих contracts:

```text
C21 large-scale construct acceptance
C22 compiled construct proxy / HLOD
production C22 incremental local rebuild
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

TS0.4 не должен возвращать экспериментальный replacement C22 после того, как local dirty rebuild уже перенесён в production.

## 5. TS0.0 — Deterministic Large Structural Fixtures

Один тип блока:

```text
structural cube
```

**Фактически принятый structural cell size:**

```text
block_size_m = 1.0
```

Это важно для C22 `C22_UNIT_AXIS_GRID` fast-path: 1m unit-axis box участвует в occupancy/internal-face culling и greedy grid compile. Старый proposal `2.0 m` считается устаревшим и не должен использоваться для accepted TS fixtures.

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

Для stepped pyramid использовать deterministic level formula и зафиксированный expected count/checksum.

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

Graphical lab должен доказывать near/mid/far derived representation поверх одного canonical construct.

Минимальный visual proof:

```text
near:
local structure readable

mid:
compiled sections / hierarchical representation

far:
full root shell / coarse proxy represents whole object cheaply
```

Representation mode не меняет canonical checksum.

## 8. Debug presentation modes

Presentation-only режимы:

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
draw_calls / draw-call proxy
mesh_build_ms
presentation/materialize_ms
estimated CPU bytes
estimated GPU/resource bytes
current representation mode
observer distance
last dirty section count
last rebuild section count
last reused section count
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

Это основной production-scale evidence TS0.

Проверить минимум:

```text
CUBE_100K
PYRAMID_100K
```

Acceptance не должен задавать случайный жёсткий FPS, зависящий от GPU машины. Вместо этого фиксируются структурные и измеримые условия:

```text
canonical_part_count >= 90 000
runtime node count bounded and far below part count
compiled/hierarchical representation used
complete visual coverage at every representation mode
near/mid/far transition observable
canonical checksum invariant across representation modes
headless canonical build/query does not require mesh assets
no unbounded artifact/cache growth during repeated mode switches
```

Performance report сохраняет реальные FPS/frame time/draw calls как evidence, но hardware-dependent значения сначала не превращаются в universal contract.

## 11. TS0.3 — Local Mutation / Dirty Rebuild

Primary deterministic evidence использует локальное изменение большого construct, например:

```text
CUBE_100K
remove 10 x 10 x 10 corner volume
= 1000 blocks
```

Проверить:

```text
construct revision changes
removed identities disappear
unaffected identities remain stable
bounded dirty/rebuild scope
whole construct not rebuilt
far proxy invalidated/rebuilt correctly
near state after return matches canonical state
```

После TS0.3 экспериментальный алгоритм обязан пройти отдельный production convergence gate перед изменением C22.

Фактический handoff:

```text
TS0.3 evidence
        ↓
feature/c22-incremental-local-rebuild
        ↓
production ConstructionProxyStreamingController.recompile_incremental
        ↓
focused equivalence vs independent full C22 compile
        ↓
full world regression
        ↓
SOURCE_ACCEPTED
```

## 12. TS0.4 — 1M Research Ceiling Probe

TS0.4 запускается **после MAIN_INTEGRATED production C22 convergence** в новой ветке от свежего `main`.

Профиль:

```text
CUBE_1M_RESEARCH
100 x 100 x 100
1 000 000 parts
```

Это не acceptance blocker для уже доказанного 100k production path.

Результат классифицировать:

```text
PASSABLE
DEGRADED
CURRENT_CEILING_EXCEEDED
```

Независимо от результата 1M, accepted 100k + local incremental path остаются валидными, если TS0.4 не обнаруживает correctness defect.

### TS0.4 должен измерять фазы, а не только общий startup

Обязательные cost centers:

```text
canonical fixture/materialization time
canonical memory footprint
section count
C22 topology build time
C22 exposed-surface extraction time
section artifact compilation time
FAR shell compilation time
C24 mesh materialization/upload time
artifact-cache entries/bytes
mesh-cache entries/GPU bytes
peak process memory where available
MID/FAR nodes/triangles/surfaces
local mutation dirty-section count
local mutation rebuild time
unchanged section reuse count
```

Нельзя уменьшать fixture только для того, чтобы скрыть медленный startup.

Если `CURRENT_CEILING_EXCEEDED`, зафиксировать dominant bottleneck и возможное направление отдельной future optimization branch:

```text
canonical build/materialization bottleneck
C22 topology/surface bottleneck
section/HLOD compilation bottleneck
C24 upload/cache residency bottleneck
```

Ни одно такое исследование не получает ownership глобального Work/Budget scheduler.

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
network interest != renderer visibility identity
```

## 14. Локальные lab budgets

Если async build требует throttling, допустимы только clearly-local knobs:

```text
max_mesh_builds_per_frame
max_upload_bytes_per_frame
max_active_build_jobs
```

Они не получают global identity/API ownership и позднее заменяются adapter-ом к общему Work/Budget Fabric, если такой global foundation будет отдельно принят.

## 15. Current / future file layout

Historical/current evidence:

```text
config/construction/ts0-*.json
docs/plans/TS0_LARGE_STRUCTURAL_VISUAL_LAB_RU.md
tests/construction/ts0/**
scripts/labs/t1/ts0/**
scenes/labs/construction/ts0_*.tscn
RUN_TS0_*.ps1
validation/ts0-*.json
```

Production convergence:

```text
scripts/construction/proxies/construction_proxy_incremental_local_rebuilder.gd
scripts/construction/proxies/construction_proxy_artifact_merger.gd
scripts/construction/proxies/construction_proxy_streaming_controller.gd
tests/construction/test_c22_incremental_local_rebuild.gd
```

TS0.4 должен использовать отдельные research config/test/lab files и не смешивать 1M experiment с production C22 contracts без отдельного convergence review.

## 16. TS0.4 first implementation slice

Первый commit новой TS0.4 branch должен быть measurement-first:

```text
1M fixture opt-in contract
phase timing telemetry
memory/cache telemetry
headless ceiling probe
```

Не начинать с красивой graphical scene.

После deterministic/headless evidence можно добавить limited graphical FAR/MID proof, если машина выдерживает материализацию без неконтролируемого resource growth.

## 17. Acceptance / evidence ladder

```text
TS0.0 fixture contracts PASS
        ↓
TS0.1 10k graphical proof PASS
        ↓
TS0.2 100k visual scale evidence PASS
        ↓
TS0.3 local mutation / dirty rebuild evidence PASS
        ↓
C22 production convergence SOURCE_ACCEPTED
        ↓
C22 MAIN_INTEGRATED
        │
        ├── production path available for T2.0
        │
        └── TS0.4 1M research continues independently
                 ↓
          PASSABLE / DEGRADED / CURRENT_CEILING_EXCEEDED
```

TS0.4 classification is research evidence, not a retroactive requirement to invalidate the 100k path.

## 18. Handoff в T2

После C22 main integration TS0.4 и T runtime-scale branch могут идти параллельно:

```text
T1A.7.4 runtime/network Scale / Soak
                ||
TS0.4 1M structural/representation ceiling
```

Перед T2.0 требуется explicit PC0 convergence review:

```text
C22 MAIN_INTEGRATED
        +
accepted relevant T runtime/recovery/interest/scale evidence
        +
TS0 100k + dirty rebuild evidence
        +
TS0.4 ceiling classification recorded
        ↓
T2.0 uses the same production representation path
on a real heterogeneous 100k-class base/station
```

Ключевой T2.0 proof обязан выполнить локальную структурную mutation на настоящей неоднородной станции и доказать, что production C22 перестраивает только bounded affected sections, переиспользуя остальные artifacts.

TS0 никогда не заменяет T2.0 real-construct acceptance.

Подробнее: `docs/plans/TS_C22_TO_T2_SCALE_CONVERGENCE_RU.md` в `main`.
