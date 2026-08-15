# ECO P4.7 — Production Integration Soak — CANONICAL CANDIDATE

Статус: `CANONICAL_RUNNER_READY_AFTER_TIMEOUT_REPAIR / EXACT_COMMITTED_A_B_PENDING`.

Parent P4.6 уже принят как `ACCEPTED_EXACT_WINDOWS_FULL_COMMITTED_REAL_INTEGRATION`. P4.7 не вводит новый scheduler или authority layer: это ускоренный deterministic integration harness для существующих P4.1–P4.6 контрактов.

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
- cycle count = 12;
- handoff count = 32;
- save/load count = 96;
- client update count = 96;
- interest projection count = 12;
- real deep ecology generation steps = 8 на каждый processing order;
- remaining catch-up debt не должен превышать 8;
- global RNG не потребляется;
- каждый Godot process ограничен timeout 600 секунд.

## R5 GDScript type repair

Exact Windows parser run на Godot `4.7.1.stable.double.custom_build.a13da4feb` обнаружил parse failure в server rotation. `SERVERS` был untyped Array, поэтому индексирование возвращало Variant и `target_server` нельзя было вывести статически.

Исправление ограничено acceptance test: `SERVERS` стал `Array[String]`, а `current_server_index` и `target_server` получили явные типы. Production runtime kernels не изменялись.

## R6 timeout repair

Следующий exact Windows run прошёл parser/preload preflight, но `canonical production soak A` непрерывно работал до hard timeout 600 секунд и был принудительно завершён.

Причина в структуре старого soak: production clock имел interval `1.0`. Каждый due generation проходит через:

```text
OfflineCatchup.advance_batch
→ EcologyClock.advance_to
→ Persistence.advance
→ Coexistence.step
```

Поэтому 8×12 циклов с elapsed `1.0/1.5/2.0`, затем forward/reverse и fresh-process A/B создавали слишком много полных P3.8 evolution steps. Увеличивать timeout запрещено как маскировка test-design дефекта.

Ремонт сохраняет integration workload:

```text
8 regions
12 cycles
32 handoffs
96 save/load
96 client updates
12 interest projections
forward/reverse convergence
fresh-process A/B
```

Но ecology clock interval теперь `10.0`. Это ограничивает дорогую глубокую эволюцию и одновременно test fail-closed требует:

```text
ecology_generation_steps = 8
```

То есть каждый из восьми регионов обязан реально пройти ровно один полный ecology generation на processing order; soak не превращён в no-op.

Candidate pins после R6:

```text
soak test blob = 09437267571cbb2b323c1ca37cd7209b9362bd7f
runner blob    = 6f83d416777d914873011adb2a84dbebcd6639a8
```

## Lifecycle boundary

`RUN_ECO_P4_7_PREACCEPTANCE_TESTS.ps1` сохраняет legacy filename, но его текущая семантика canonical. P4.7 нельзя принять до exact committed A/B PASS с byte-identical logs, `ecology_generation_steps=8` и замороженными `soak_hash` / `final_interest_hash`.

P4.8 control preparation уже перепинована на R6, но финальный P4 acceptance остаётся fail-closed до P4.7 lifecycle acceptance.
