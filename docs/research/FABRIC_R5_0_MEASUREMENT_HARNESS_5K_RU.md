# FABRIC R5.0 — Measurement Harness + 5k Baseline

## Статус

```text
STAGE = R5.0
SUBJECT = research/fabric-r5-0-measurement-harness-5k-r1
PREDECESSOR_R4_2_ACCEPTED_HEAD = 33b06f9658fe3373d18893ab2292471a13d61894
BASE_RESEARCH_HEAD = 618786e5b472fc968d83300c8ceb62864476b1c1
STATUS = EXACT BASELINE PASS / FRESH REVIEW + VERIFIER PENDING
```

R5.0 не создаёт новый физический capability claim. Его задача — зафиксировать измерительный контракт, на котором затем сравниваются R5.1 quantitative scaling и R5.2/R5.3 qualitative complexity compression.

## Почему нельзя использовать только wall time

Wall-clock зависит от runner, scheduler, thermal state и фоновой нагрузки. Поэтому R5.0 разделяет:

```text
DETERMINISTIC CORRECTNESS
  - canonical part count
  - active FULL peak
  - local reconstruction count
  - metadata scan work
  - rebake local validation count
  - global rebuild count
  - ownership/event/hash identity

OBSERVATIONAL PERFORMANCE
  - duration per stage
  - Godot MEMORY_STATIC
  - Godot object-count proxy
  - process max RSS
  - user/system CPU time
  - page faults
  - context switches
```

Timings/RSS в R5.0 являются baseline observations, а не safety/fidelity gate.

## 5k workload

Переиспользуется уже закрытый COMPLEX3 deterministic 5,000-part canonical source и sparse lifecycle, но с новой разбивкой измерений.

```text
5000 canonical parts
        ↓
source digest build
        ↓
independent full rehash validation
        ↓
aggregate compile
        ↓
one baked body
        ↓
cheap baked boundary execution loop (64 calls)
        ↓
local guard
        ↓
20 FULL parts + 2 residual baked bodies
        ↓
capsule capture/restore
        ↓
external canonical bond break
        ↓
writer invalidation/fence
        ↓
local rebake
        ↓
2 baked components
        ↓
cheap baked boundary execution loop
        ↓
final capsule capture/restore
```

Ключевой deterministic predicate:

```text
canonical parts             = 5000
FULL peak                   = 20
local reconstructed parts   = 20
rebake local validations    = 20
global physical rebuilds    = 0
duplicate ownership         = 0
baked boundary calls        = 128
```

## Measurement stages

R5.0 фиксирует как минимум:

```text
source_create_with_expanded_digests
source_full_rehash_validation
parent_aggregate_compile
bake_start
baked_boundary_hot_loop_before
local_unbake_20
local_capsule_capture
local_capsule_restore
canonical_successor_create
canonical_mutation_fence
fenced_capsule_capture
fenced_capsule_restore
local_rebake_after_settle
baked_boundary_hot_loop_after
final_capsule_capture
final_capsule_restore
```

Для каждой стадии записываются duration, Godot static-memory before/after и object-count delta.

## Process-level evidence

CI запускает baseline минимум три раза в отдельных Godot-процессах. Внешний GNU `time -v` фиксирует:

- max RSS;
- user/system CPU;
- elapsed wall time;
- minor/major page faults;
- voluntary/involuntary context switches.

Collector требует одинаковую deterministic identity во всех повторах и строит min/median/max observation baseline.

## Честные ограничения R5.0

### Active solver

COMPLEX3 5k — structural BAKE/local-refinement baseline. Он не содержит активного DAE/ROM solve на каждом tick, поэтому R5.0 **не выдаёт boundary gate timing за solver timing**.

Solver cost будет отдельной обязательной метрикой в R5.2 fixtures: Filter, Motor, Power Stage, Servo и Laser assembly.

### Allocations

Текущий Godot contract здесь не выдаёт точное число allocator events. Поэтому:

```text
MEMORY_STATIC
object-count delta
process RSS
page faults
```

являются явно помеченными proxies. Точные allocator counters не выдумываются.

## Acceptance

R5.0 закрывается, когда:

1. fresh import проходит на canonical Linux-double Godot;
2. три fresh-process 5k повтора проходят без физического regression;
3. deterministic hash одинаков во всех повторах;
4. FULL peak = 20 и global rebuilds = 0;
5. per-stage measurements присутствуют и машинно парсятся;
6. GNU process evidence присутствует;
7. baseline evidence artifact сохраняется;
8. никаких новых абсолютных performance thresholds не вводится по одному noisy runner;
9. current R4.2 accepted/frozen code не переписывается.

Следующий этап после R5.0 — R5.1 quantitative scale, после первого 5k baseline параллельно разрешается открывать R5.2 complexity-compilation fixtures.


## Exact 5k baseline — run 35509335947

```text
subject HEAD = 5ad976be94b9aba847dfa0845c0b6e489439379c
subject TREE = d0ff00b282f16619fc34427e8cd35ee84a2a1ea8
run          = 35509335947
samples      = 3/3 PASS
aggregate    = PASS
artifact     = 10604504327
digest       = sha256:288c24212196866795cdffe48da9152e1cfc54445af5c667b0ffcbf08ebb9557
evidence hash       = 13e40d7be2c318088fb533c8235411a0fac3343534e2f6b8d02623c93c4f75ef
deterministic hash  = 1c549d536b4077c686dea9e25ca5e08935afd240f3b070ca49da153b7bee883b
```

Deterministic predicates:

```text
canonical parts           = 5000
FULL peak                 = 20
local reconstructed       = 20
local rebake validations  = 20
global physical rebuilds  = 0
duplicate ownership       = 0
boundary calls            = 128
```

Observational median on this GitHub-hosted Ubuntu runner:

```text
whole process            ≈ 2.12 s
max RSS                  ≈ 127416 KiB
Godot MEMORY_STATIC peak = 28,825,994 bytes
source create            ≈ 540.7 ms
full source rehash       ≈ 570.5 ms
parent aggregate         ≈ 10.7 ms
local UNBAKE 20          ≈ 22.5 ms
local ReBAKE             ≈ 15.1 ms
64-call baked boundary   ≈ 25.6 ms before / 25.6 ms after
```

Эти времена являются baseline observations, а не absolute acceptance budgets. Основной ранний вывод R5.0: на данном fixture стоимость metadata/source hashing (~0.5 s на проход) заметно выше локального physical refinement (~15–23 ms); это кандидат на измеряемую ось R5.1, но не основание ослаблять correctness/fidelity.
