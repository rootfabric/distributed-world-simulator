# EVO ARCH2 A5 — Repair Map R6

Дата: 2026-09-07  
Work Order: `EVO-ARCH2-A5-20260906-R1`  
Scope: bounded self-review hardening внутри заявленных restart/replay и offspring identity predicates.

## RM-A5-08 — persistent propagule identity continuity

После RM-A5-07 два persistent counters (`reproduction_count`, `propagule_seq`) имели корректный числовой диапазон, но validator ещё не выражал причинную связь между ними. Runtime всегда создаёт ровно один sequence number на каждого offspring и увеличивает оба counters на одинаковое `offspring_per_event`.

Без semantic invariant канонически закодированный, но изменённый snapshot мог уменьшить `propagule_seq` при сохранённом `reproduction_count`; после restore это позволяло бы повторно выпустить ранее использованный seed ID.

Исправление:

```text
propagule_seq == reproduction_count
reproduction_count <= age_ticks * MAX_OFFSPRING_PER_EVENT
```

Второй invariant является безопасной верхней причинной границей: за один lifecycle tick A5 может создать максимум 4 offspring.

Дополнительно parent component seed ID теперь использует полный SHA-256 `individual_id`, а не 16-hex prefix:

```text
seed/<64-hex parent digest>/<sequence>
```

Даже при максимальном sequence длина остаётся значительно меньше `C.identifier` limit 128.

Acceptance witness:

- canonical state с рассинхронизированными `propagule_seq`/`reproduction_count` отклоняется;
- counter boundary witness использует `age_ticks=250001`, `reproduction_count=propagule_seq=1000000`, выполняет 4-offspring transition и получает 1,000,004 в обоих counters;
- resulting state проходит causal bound и semantic validation.

После публикации нужен fresh exact Verifier и fresh independent Reviewer финального exact HEAD.
