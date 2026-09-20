# FABRIC R5.1 Repair R1 — Range Aggregate Index

## Найденный blocker

Первый exact R5.1 run `35510772849` прошёл correctness 9/9, но measurement contract показал скрытую O(N) работу внутри local transition.

При N 5k → 100k:

```text
N                         ×20
baked boundary loop       ≈ ×0.95
source create             ≈ ×19.24
full rehash               ≈ ×19.58
local UNBAKE 20           ≈ ×10.56
local ReBAKE              ≈ ×15.01
RSS                       ≈ ×0.99
```

FULL peak при этом оставался ровно 20.

## Root cause

Closed COMPLEX3 lifecycle строит left/right residual aggregates через `Source.aggregate_span()`, который делает два прохода по каждой скрытой part. Поэтому локальный physical reveal bounded, но подготовка residual representation скрыто O(N).

## Repair

Closed COMPLEX3/R5.0 bytes не изменяются.

R5.1 добавляет derived `R5RangeAggregateIndex`:

```text
one O(N) build
    ↓
prefix physical moments
  mass
  mass*position
  inertia-about-origin
    ↓
arbitrary contiguous span
    ↓
O(1) prefix differences
```

R5.1 indexed lifecycle наследует closed lifecycle и заменяет только получение residual aggregates.

Index:
- derived/discardable;
- привязан к `expanded_part_digest`;
- не является canonical truth;
- может переиспользоваться после topology-only successor, если part identity неизменна.

## Repair acceptance

```text
range index build scan       = N (one-time)
online residual full scans   = 0
range queries per lifecycle  = 4
prefix reads                 = 80
FULL peak                    = 20
local reconstructed          = 20
local rebake validations     = 20
global physical rebuilds     = 0
```

Whole-span indexed descriptor дополнительно сравнивается с frozen streaming aggregate по mass/COM/inertia.

Timings остаются observational: repair не получает искусственный budget PASS. Его эффект оценивается по новой exact 5k/20k/100k матрице.
