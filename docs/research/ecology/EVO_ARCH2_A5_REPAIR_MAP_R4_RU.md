# EVO ARCH2 A5 — Repair Map R4

Дата: 2026-09-07  
Work Order: `EVO-ARCH2-A5-20260906-R1`  
Scope: research-only; production/main/network/Matter authority не изменяются.

## RM-A5-06 — absolute reproduction schedule range

Final fresh review exact `10b5ef73...` нашёл P2 в согласованности policy/state.

### Проблема

Допустимый life-history contract разрешает:

```text
maturity_ticks <= 1_000_000
interval_ticks <= 1_000_000
```

`age_ticks` организма ограничен 1_000_000 — это lifetime execution bound. Но `next_reproduction_tick` является **absolute schedule marker**, а не текущим возрастом. После успешного размножения runtime пишет:

```text
next_reproduction_tick = age_ticks + interval_ticks
```

Следовательно корректное значение расписания может доходить до `2_000_000`. Старый `OrganismLifeStateV1.validate()` ошибочно ограничивал его 1_000_000 и отвергал валидный lifecycle state.

### Исправление

В `OrganismLifeStateV1` явно разделяются два диапазона:

```text
MAX_AGE_TICK = 1_000_000
MAX_REPRODUCTION_SCHEDULE_TICK = 2_000_000
```

- `age_ticks` остаётся ограниченным `MAX_AGE_TICK`;
- `next_reproduction_tick` валиден до `MAX_REPRODUCTION_SCHEDULE_TICK`;
- значение не saturate-ится: если следующий event лежит за lifetime, оно так и хранится, поэтому размножение не происходит раньше inherited interval;
- текущий runtime при `age_ticks >= MAX_AGE_TICK` по-прежнему не исполняет новый lifecycle tick.

### Acceptance witness

Reviewer-repair oracle создаёт valid policy с `interval_ticks = 1_000_000`, выполняет оплаченный reproduction transition на `age_ticks = 1` и доказывает:

```text
next_reproduction_tick == 1_000_001
OrganismLifeStateV1.validate(...) == PASS
```

Это значение намеренно больше lifetime age cap и корректно представляет событие, которое не наступит в пределах жизни организма.

После публикации RM-A5-06 все прежние Reviewer/Verifier verdicts считаются stale. Требуются fresh exact Verifier и fresh independent Reviewer нового exact HEAD.
