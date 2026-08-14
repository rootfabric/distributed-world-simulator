# ECO P4.7 — Production Integration Soak — PRE-ACCEPTANCE CANDIDATE

Статус: `PREACCEPTANCE_CANDIDATE_COMMITTED_RUN_PENDING_P4_6_ACCEPTANCE_PENDING`.

P4.7 здесь — не новый scheduler и не новая authority layer. Это ускоренный deterministic integration harness для уже существующих P4.1–P4.6 контрактов.

## Scenario

```text
8 regions
× 12 deterministic cycles
= 96 per-region save/load + client-update operations
```

В каждом цикле harness:

- восстанавливает P4.3 Catch-up из текущего P4.4 snapshot;
- добавляет deterministic elapsed world time;
- обрабатывает backlog bounded batch'ом 1..4 шага;
- создаёт P4.4 production snapshot;
- делает serialize → deserialize;
- CAS-коммитит snapshot через текущего P4.5 owner;
- по deterministic правилу выполняет handoff между `server-a/b/c`;
- на циклах 3/7/11 реконструирует ownership после persistence restart;
- строит P4.6 summary и обновляет monotonic client cache;
- строит canonical interest projection по всем регионам плюс двум отсутствующим.

Сценарий выполняется в двух порядках обработки регионов — forward и reverse. Итоговые `soak_hash` и `final_interest_hash` обязаны совпасть.

## Bounds

- region cardinality остаётся ровно 8;
- save/load count = 96;
- client update count = 96;
- interest projection count = 12;
- remaining catch-up debt не должен превышать 8;
- global RNG не потребляется;
- каждый Godot process ограничен timeout 600 секунд.

## Lifecycle boundary

`RUN_ECO_P4_7_PREACCEPTANCE_TESTS.ps1` можно запускать до P4.6 acceptance только как non-canonical evidence. Первый exact committed A/B PASS даст candidate soak identities, но freeze/acceptance P4.7 разрешены только после P4.6 lifecycle acceptance.

P4.8 остаётся CLOSED.
