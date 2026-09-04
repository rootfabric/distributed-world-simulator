# COMPLEX2-PERF — 500 / 1000 / 2000 Scaling

**Статус:** ✅ EXACT VERIFIED

Exact executable subject:

```text
HEAD 4cf6d45f35b16db0cead220768b399f0ea5c75ef
TREE 923f9f59730da43f8be6d738b7e1dc4a23ec7764
```

PERF здесь не является пустым микробенчмарком. Для каждого масштаба реально материализуются canonical parts и выполняются:

```text
scaled modular construction
        ↓
D independent structural failure
        ↓
E settle + physical re-impact
        ↓
16 mixed/FULL reference steps
        ↓
local DYNAMIC_ROM rebake
```

Размеры:

```text
500  = 25 modules × 20 parts
1000 = 25 modules × 40 parts
2000 = 25 modules × 80 parts
```

Распределение representation regions масштабируется пропорционально, но ownership topology остаётся прежней: пять BRIDGE-2 kinds, один active owner на регион, один canonical source owner.

## Exact результаты

```text
500:
  total 6.027 s
  canonical scan 1.315 ms
  local DYNAMIC rebake 86.552 ms

1000:
  total 6.130 s
  canonical scan 2.503 ms
  local DYNAMIC rebake 88.082 ms

2000:
  total 5.993 s
  canonical scan 4.952 ms
  local DYNAMIC rebake 85.493 ms
```

Общее время почти не растёт с 500 до 2000, потому что доминирует фиксированный physical/mixed lifecycle. При этом canonical scan показывает ожидаемый рост с количеством parts, а local rebake остаётся bounded и затрагивает только:

```text
region/complex2-dynamic
```

Hard budgets:

```text
total per case <= 12 s
local rebake    <= 250 ms
mixed/FULL delta <= 1e-12
state handoff error = 0
```

Deterministic identity исключает wall-clock timings:

```text
COMPLEX2PERF_MATRIX_HASH=
698486abd097e6ee12731b0afb1c6e28ed24bf72b52d8d940c9f5b7336498607
```

Acceptance:

```text
FABRIC COMPLEX2-PERF Scaling Acceptance: PASS (62 assertions) 500/1000/2000
```

Evidence:

```text
validation/FABRIC_COMPLEX2_PERF_EXACT_EVIDENCE.md
validation/FABRIC_COMPLEX2_CLOSURE.md
```
