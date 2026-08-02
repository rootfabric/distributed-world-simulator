# C21 — Large-Scale Construction Acceptance

**Статус:** IMPLEMENTED CANDIDATE
**База:** принятый C20
**Рекомендуемая ветка:** `feature/c21-large-scale-construction-acceptance`

## Цель

Доказать, что строительная вертикаль C1–C20 сохраняет authority, replay, item identity, материальный баланс и streaming budgets не только на единичных fixtures, но и при массовой синтетической нагрузке, близкой к целевому распределённому миру.

C21 не создаёт новый mutation path. Это acceptance harness, который моделирует массовые C3/C8/C17/C18/C19/C20 workloads и проверяет общие инварианты.

## Focused world

```text
20 000 constructs
1 280 000 item-backed parts modeled
1 000 BuildPlan
256 construction agents
3 000 fabrication jobs
4 000 procurement orders
4 000 multi-leg shipments
32 warehouses
16 authority servers
2 000 damage events / 500 collapses / 1 500 repairs
1 000 authority migrations
32 reconnect waves
2 048 soak ticks
>= 50 000 operation attempts
```

## Extended soak

```text
30 000 constructs
2 880 000 item-backed parts modeled
2 000 BuildPlan
512 agents
6 000 fabrication jobs
8 000 procurement orders
8 000 shipments
64 warehouses
32 servers
5 000 damage events / 1 500 collapses / 3 500 repairs
2 000 authority migrations
64 reconnect waves
8 192 ticks
>= 100 000 operation attempts
```

## Проверяемые инварианты

1. На один operation ID приходится не более одного authoritative commit.
2. Exact retry возвращает replay, изменённый payload — conflict.
3. После authority migration старый epoch fenced.
4. Reconnect storms не создают повторные commits.
5. Item identities не теряются при fabrication/procurement/shipment.
6. Материальный ledger сходится после production, delivery и consumption.
7. C18 presentation/simulation/summary budgets не превышаются.
8. Все BuildPlan и agent goals завершаются.
9. Persistence checkpoint восстанавливается без изменения determinism checksum.
10. Повреждённый snapshot отклоняется до загрузки и не переподписывается.

## Acceptance report

Harness выдаёт строгий JSON-safe `ConstructionScaleReport`:

- profile checksum;
- counters workload;
- replay/conflict/commit metrics;
- migration/reconnect metrics;
- material conservation;
- peak streaming levels;
- wall-time budget;
- state checksum;
- determinism checksum;
- список invariant failures.

## Focused results

```text
C21 contracts:    PASS — 26 assertions
C21 integration:  PASS — 52 assertions
C21 soak:         PASS — 26 assertions
C21 total:        PASS — 104 assertions
Local C1–C21:     PASS — 3305 assertions, 41 profiles
Excluded locally: C2B, C9, Network N0–M4, full world/main-scene
```

Локальная Godot 4.7.1 double нагрузка:

```text
focused integration: ~10 s, peak RSS ~428 MiB
extended soak:       ~12 s, peak RSS ~721 MiB
```

Значения времени и RSS являются характеристикой локального validation host, а не универсальным production SLA.

## Ожидаемый полный gate

```text
C21 focused:      PASS — 104 assertions
C2B regression:   PASS — 258 assertions
C9 regression:    PASS — 204 assertions
C17–C20:          PASS
Network N0–M4:    PASS
World regression: PASS — 144/144 tests, 147 steps
Main-scene CLI:   PASS — 6/6
git diff --check: PASS
```
