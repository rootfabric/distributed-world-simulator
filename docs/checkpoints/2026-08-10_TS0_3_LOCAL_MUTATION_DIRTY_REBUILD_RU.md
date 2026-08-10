# TS0.3 — Local Mutation / Dirty Section Rebuild Candidate

**Дата:** 2026-08-10  
**Ветка:** `feature/ts0-large-structural-visual-lab`  
**Control plane:** `PC0-2026-08-10-R1`  
**Architecture:** `GLOBAL-P0-2026-08-10-R2`

## Решение

Реализован TS-owned candidate локального rebuild для фиксированного TS0.3 mutation probe:

```text
CUBE_100K = 46×46×46 = 97 336 canonical cells
mutation  = remove max-corner 10×10×10 = 1 000 cells
```

Цель — доказать, что presentation rebuild после локальной мутации не обязан повторно обходить все ~100k частей и не обязан запускать полный C22 compile.

## PC0

Перед реализацией проверен `origin/main` Project Control registry generation 5.

Main всё ещё формально объявляет TS frontier как `TS0.1 10k Visual Proof` с YELLOW health. Поэтому TS0.3 фиксируется как pre-stage candidate и не объявляется `SOURCE_ACCEPTED`.

TS не забирает ownership `scripts/construction/proxies/**`: production C22/C24 остаются watched/critical dependency. Новый алгоритм находится только в TS-owned lab paths. Перенос доказанного алгоритма в production `ConstructionProxyStreamingController.recompile_incremental()` требует отдельного C22/Construction convergence решения.

## Алгоритм

```text
removed 10×10×10 corner
        ↓
8 base dirty source sections
        ↓
+ 1 section rebuild halo
        ↓
27 rebuild sections
        ↓
+ context ring only for occupancy lookup
        ↓
local exposed-face extraction
        ↓
local greedy GRID_QUAD rebuild
        ↓
1 affected 3×3×3 HLOD cluster
```

Не требуется:

```text
full snapshot part scan after mutation
full C22 compile after mutation
rebuild all 216 sections
rebuild all HLOD clusters
```

## Deterministic acceptance facts

Для `CUBE_100K`, section size 8 m:

```text
initial parts             97 336
removed parts              1 000
remaining parts           96 336

total sections               216
base dirty sections             8
rebuild sections               27
non-empty rebuilt              26
removed empty section            1
reused sections                189
affected ratio               12.5%

dirty HLOD clusters              1
scanned rebuild cells        10 648
context occupancy cells      26 000
```

Один corner section `5/5/5` становится пустым и исчезает. Соседний `4/4/4` перестраивается и получает новые exposed surfaces.

## C24 compatibility

Локальный extractor выдаёт тот же grid payload shape, который принимает C24:

```text
kind = GRID_QUAD
axis = X/Y/Z
direction = -1/+1
plane_q2
u / v
width / height >= 1
```

То есть локальный rebuild не вводит новый mesh format.

## Локальная проверка на прикреплённом Godot

Использован архив проекта:

```text
godot-4.7.1-linux-double-x86_64-a13da4f.tar(1).gz
```

Engine:

```text
Godot 4.7.1.stable.double.custom_build.a13da4feb
```

Результат:

```text
editor import                                  PASS
TS0.3 local dirty rebuild focused              PASS 24 assertions
observed local rebuild                         ~28 ms
rebuild sections                               27
reused sections                                189
dirty clusters                                 1
```

Это isolated exact-engine focused validation нового TS-owned алгоритма. Full repository regression и production C22 integration этим harness не заявляются.

## Статус

```text
TS0.3 implementation                           IMPLEMENTED_CANDIDATE
local rebuild algorithm                        PASS
100k full rescan required after mutation       NO
full C22 compile required after mutation       NO
production C22 integration                     PENDING_OWNERSHIP_CONVERGENCE
SOURCE_ACCEPTED                                 false
MAIN_INTEGRATED                                 false
COMPOSITION_VERIFIED                            false
PRODUCTION_READY                                false
```

## Следующий шаг внутри TS0.3

Подключить доказанный локальный rebuild к C22 incremental execution path через корректного владельца Construction/C22, сохранив:

- content-addressed reuse неизменённых section artifacts;
- invalidation только dirty sections/clusters;
- полное HLOD coverage;
- отдельный background shell compaction вместо полного synchronous 100k recompilation.
