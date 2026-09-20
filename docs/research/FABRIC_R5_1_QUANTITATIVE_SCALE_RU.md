# FABRIC R5.1 — Quantitative Scale 5k / 20k / 100k

## Цель

R5.1 использует закрытый R5.0 measurement contract и проверяет количественный масштаб, не переобъявляя старый COMPLEX3 как новый результат.

Главный вопрос:

> При росте canonical N остаётся ли локальная физическая детализация bounded, и какие именно стадии действительно растут с N?

## Матрица

```text
N = 5,000 / 20,000 / 100,000
fresh samples per N = 3
local FULL region = 20 parts
boundary probe = 64 calls before + 64 after
```

Всего authoritative campaign = 9 fresh Godot processes.

## Два класса работы

### Local causal path

```text
BAKED
  ↓ local guard
20 FULL
  ↓ canonical break
local ReBAKE
  ↓
2 reduced components
```

Обязательный deterministic contract для каждого N:

```text
FULL peak = 20
local reconstructed = 20
local rebake validations = 20
global physical rebuilds = 0
duplicate ownership = 0
```

### Explicit global control

R5.1 отдельно выполняет полный `aggregate_span(0,N)` после mutation. Это контрольная O(N) операция, чтобы сравнить полный derived rebuild с локальным physical path.

Она **не выдаётся за naturally propagating global physical event**. Естественно глобально распространяющиеся события должны проверяться более богатой физикой в R5.2/R5.4.

## Измеряемые стадии

R5.0 stages сохраняются и добавляется:

```text
global_control_full_aggregate
```

Collector строит min/median/max по трём fresh samples для каждого N и отношения к 5k:

- source create;
- full rehash;
- parent aggregate;
- explicit global control;
- local UNBAKE 20;
- local ReBAKE;
- baked boundary loop;
- RSS.

## Acceptance

R5.1 PASS определяется только deterministic predicates:

```text
N ∈ {5000,20000,100000}
parent scan = N
lifecycle scan = 2N - 20
global control scan = N
FULL peak = 20
local reconstructed = 20
rebake validations = 20
global physical rebuilds = 0
duplicate ownership = 0
3/3 samples at each N have identical deterministic identity
```

Wall time/RSS не являются absolute budgets.

## Запреты

- не менять закрытые COMPLEX3/R5.0 runtime bytes;
- не поднимать thresholds ради PASS;
- не называть explicit global control естественной physical propagation;
- не делать вывод о DAE/ROM solver scaling: это R5.2;
- не скрывать O(N) metadata/hash work под термином local scaling.


## Repair R1 — indexed local residual path

Первый exact measurement выявил, что old local lifecycle сохранял bounded FULL=20, но residual descriptor preparation повторно сканировал O(N) hidden parts. Это не соответствует цели R5.1.

Repair R1 добавляет one-time `range_index_build = O(N)`, после которого четыре residual span queries на local UNBAKE/ReBAKE выполняются без part scans. Подробности: `FABRIC_R5_1_REPAIR_R1_RANGE_INDEX_RU.md`.

Новый deterministic contract:

```text
index build scan = N once
online lifecycle full scans = 0
range queries = 4
prefix reads = 80
FULL peak = 20
global rebuilds = 0
```
