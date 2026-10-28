# EVO ARCH2 A5 — Repair Map R5

Дата: 2026-09-07  
Work Order: `EVO-ARCH2-A5-20260906-R1`  
Scope: research-only; production/main/network/Matter authority не изменяются.

## RM-A5-07 — offspring counters must cover lifetime × offspring/event

Fresh review exact `9b6dc14d...` выявил P2: `reproduction_count` и `propagule_seq` являются счётчиками созданных offspring, но старый validator ограничивал их 1,000,000 как будто они были tick counters.

Допустимый inherited policy разрешает:

```text
interval_ticks = 1
offspring_per_event = 4
```

При lifetime bound 1,000,000 ticks корректный верхний предел offspring counters равен:

```text
MAX_AGE_TICK * MAX_OFFSPRING_PER_EVENT = 4,000,000
```

Исправление в `OrganismLifeStateV1`:

```text
MAX_OFFSPRING_PER_EVENT = 4
MAX_OFFSPRING_COUNTER = MAX_AGE_TICK * MAX_OFFSPRING_PER_EVENT
```

`reproduction_count` и `propagule_seq` валидируются до 4,000,000 включительно. Age bound и schedule bound не меняются.

Acceptance witness не выполняет сотни тысяч ticks: он создаёт канонический zero-cost reproduction policy, подготавливает всё ещё валидный state на границе 1,000,000 offspring и выполняет один 4-offspring transition. После него:

```text
reproduction_count == 1,000,004
propagule_seq == 1,000,004
OrganismLifeStateV1.validate(...) == PASS
```

Это напрямую воспроизводит arithmetic boundary Reviewer-а без искусственного ускорения runtime semantics.

После публикации RM-A5-07 все прежние Reviewer/Verifier verdicts считаются stale. Требуются fresh exact Verifier и fresh independent Reviewer нового exact HEAD.
