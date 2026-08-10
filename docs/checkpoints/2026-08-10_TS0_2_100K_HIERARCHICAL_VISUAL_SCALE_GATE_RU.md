# TS0.2 — 100k Hierarchical Visual Scale Gate Candidate

**Дата:** 2026-08-10  
**Ветка:** `feature/ts0-large-structural-visual-lab`  
**Control plane:** `PC0-2026-08-10-R1`  
**Architecture:** `GLOBAL-P0-2026-08-10-R2`  
**Формальный frontier:** `TS0.1 10k Visual Proof`  
**Pre-stage candidate:** `TS0.2 100k Hierarchical Visual Scale Gate`  
**Статус:** `IMPLEMENTED_CANDIDATE_BLOCKED_BY_TS0_1_ACCEPTANCE`

## PC0 preflight

Перед началом реализации проверены main-owned:

```text
PROJECT_CONTROL.md
config/control/project-program-registry.v1.json
config/control/project-control-policy.v1.json
config/control/architecture-ownership.v1.json
```

Результат:

```text
control_plane_revision = PC0-2026-08-10-R1
registry_generation    = 2
architecture_revision  = GLOBAL-P0-2026-08-10-R2

TS declared health      = YELLOW
TS RED blocker          = none
formal frontier         = TS0.1
allowed ownership       = DERIVED_PRESENTATION
```

По PC0 YELLOW позволяет продолжать разработку, но запрещает объявлять следующий major acceptance без convergence/revalidation. Поэтому TS0.2 реализован как pre-stage candidate, а `SOURCE_ACCEPTED` для TS0.1/TS0.2 не подменяется.

Также исправлен branch passport: C22/C24 реально находятся в `scripts/construction/proxies/**`, поэтому этот path теперь watched, а ключевые compiler/planner/C24 contracts перечислены как critical watched dependencies.

## Архитектурная цель

TS0.1 доказал complete visual coverage на 10k через flat all-sections representation. Это нельзя переносить на 100k простым повышением лимита.

TS0.2 вводит экспериментальную иерархию только в TS-owned paths:

```text
Canonical ConstructSnapshot ~100k parts
              ↓
        existing C22 compile
              ↓
      C22 section artifacts
              ↓
 TS0 hierarchical cluster compiler
        3×3×3 sections / cluster
              ↓
     second-pass greedy merge
              ↓
      C24 ArrayMesh materialize
```

Production C22/C24 код TS0.2 этим этапом не меняет.

## Представления

### FAR

```text
C22 FULL ROOT SHELL
→ 1 mesh
→ полное покрытие конструкции
```

### MID

```text
все C22 sections
    ↓ grouped by 3×3×3 section coordinates
coarse cluster artifacts
    ↓
все clusters одновременно
→ полное покрытие конструкции
→ node/draw-call count ниже flat section count
```

### NEAR

```text
nearest coarse cluster
    ↓ replace by its source section artifacts

all other clusters
    ↓ remain coarse cluster meshes

result:
local refinement + coarse remainder
→ полная конструкция остаётся видимой
```

Главный invariant:

```text
COMPLETE_VISUAL_COVERAGE_REQUIRED

coverage_sections == source_section_count
```

LOD не имеет права удалять невыбранную часть конструкции.

## 100k fixtures

```text
CUBE_100K
parts    = 97 336
checksum = 4aebed994f09f578ae241a9c8adb677eb5cf81d1581aea99491921c6f685e084

PYRAMID_100K
parts    = 102 510
checksum = 4a721061894d65b7bee1d9502a331e0879e4ce5a8047cfe53650460e07b636e6
```

Оба профиля обязаны иметь больше 64 C22 sections, иначе TS0.2 не доказал бы переход от TS0.1 flat ceiling к hierarchy.

## Cluster policy

```text
section size            8 m
cluster edge            3 sections
cluster spatial edge    up to ~24 m
max TS0.2 clusters      64
near refined clusters   1
```

Cluster artifact создаётся из уже принятых C22 section artifacts. GRID_QUAD rectangles разворачиваются в surface cells и повторно greedy-merge внутри cluster. Это позволяет объединять поверхности через границы исходных 8m sections внутри coarse cluster.

Cluster artifacts:

- не являются canonical truth;
- не публикуются в C22 artifact cache;
- не создают новый persistence/network owner;
- материализуются существующим C24 mesh cache;
- являются disposable derived presentation.

## Новые файлы

```text
config/construction/ts0-100k-hierarchical-scale-gate.v1.json

scripts/labs/t1/ts0/ts0_hierarchical_cluster_compiler.gd
scripts/labs/t1/ts0/ts0_hierarchical_runtime_node.gd
scripts/labs/t1/ts0/ts0_100k_hierarchical_visual_lab.gd

scenes/labs/construction/ts0_100k_hierarchical_visual_lab.tscn

tests/construction/ts0/ts0_100k_hierarchical_proxy_acceptance.gd

RUN_TS0_100K_TESTS.ps1
RUN_TS0_100K_TESTS.sh
RUN_TS0_100K_LAB.ps1
RUN_TS0_100K_LAB.sh
```

## Focused acceptance

Для каждого 100k profile тест требует:

1. exact canonical part count/checksum;
2. C22 source section count > 64;
3. deterministic hierarchical coverage checksum;
4. cluster count > 1, <= 64 и меньше source section count;
5. TS cluster compiler не публикует cluster artifacts в C22 artifact cache;
6. MID покрывает все source sections только coarse clusters;
7. NEAR заменяет ровно один cluster source sections и сохраняет coarse remainder;
8. FAR использует ровно один C22 root-shell mesh;
9. canonical checksum invariant across NEAR/MID/FAR;
10. runtime nodes far below semantic parts;
11. C24 ArrayMesh используется для hierarchical meshes;
12. repeat MID даёт C24 cache hits;
13. C24 entry/GPU-byte budgets соблюдаются;
14. mode switches не раздувают C22 artifact cache.

## Что пока не является acceptance

TS0.2 не может получить `SOURCE_ACCEPTED`, пока:

```text
TS0.1 complete-coverage focused revalidation PASS
TS0.1 manual graphical review PASS
TS0.1 full world regression PASS
Project Control convergence after TS0.1 acceptance
TS0.2 Windows focused PASS
TS0.2 manual 100k visual observation PASS
TS0.2 full world regression PASS
```

Main Project Registry остаётся владельцем формального frontier.

## Локальная parse/smoke validation

На exact engine:

```text
Godot 4.7.1.stable.double.custom_build.a13da4feb
```

изолированный harness подтверждает:

```text
new scripts/scenes parse                 PASS
hierarchy deterministic cluster smoke    PASS
3 source sections → 1 greedy cluster     PASS
MID complete cluster coverage            PASS
NEAR local cluster replacement           PASS
```

Это не заменяет real Windows branch run с production C22/C24.

## Запуск Windows worktree

```powershell
cd C:\Godot\lunar-world-double-godot-ts0
git pull --ff-only

$Godot = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"
$env:GODOT_BIN = $Godot

.\CONTROL_PROJECT.ps1 -NoFailOnRed

.\RUN_TS0_100K_TESTS.ps1 -GodotPath $Godot
.\RUN_TS0_100K_LAB.ps1 -GodotPath $Godot -Profile CUBE_100K -Mode FAR
```

В graphical lab:

```text
1 — CUBE_100K
2 — PYRAMID_100K
3 — NEAR
4 — MID
5 — FAR
```

На всех режимах форма обязана оставаться целой. Меняться должны representation cardinality/triangle/draw-call metrics, а не существование удалённых частей конструкции.
