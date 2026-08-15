# ECO P4.7 — Production Integration Soak — CANONICAL CANDIDATE

Статус: `CANONICAL_RUNNER_READY_AFTER_GDSCRIPT_TYPE_REPAIR / EXACT_COMMITTED_A_B_PENDING`.

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
- handoff count = 32;
- save/load count = 96;
- client update count = 96;
- interest projection count = 12;
- remaining catch-up debt не должен превышать 8;
- global RNG не потребляется;
- каждый Godot process ограничен timeout 600 секунд.

## R5 GDScript type repair

Exact Windows parser run на Godot `4.7.1.stable.double.custom_build.a13da4feb` обнаружил parse failure в server rotation: `SERVERS` был untyped Array, поэтому `var target_server := SERVERS[...]` выводился как Variant и тип нельзя было вывести.

Исправление ограничено acceptance test:

```gdscript
const SERVERS: Array[String] = ["server-a", "server-b", "server-c"]
var current_server_index: int = SERVERS.find(...)
var target_server: String = SERVERS[...]
```

Production runtime kernels и принятые P4.1–P4.6 surfaces не изменялись. Candidate pins после ремонта:

```text
soak test blob = 9c2093e43417603bb1283e918dd511f6597f667f
runner blob    = f6806edf25a7e466eb7f0ea3c2f8e31b0f768216
```

Targeted exact attached-Godot parser reproduction для typed server-rotation pattern проходит. Полный committed P4.7 parser/A/B soak остаётся обязательным и должен быть выполнен на exact Windows checkout.

## Lifecycle boundary

`RUN_ECO_P4_7_PREACCEPTANCE_TESTS.ps1` сохраняет legacy filename, но его текущая семантика canonical. P4.7 нельзя принять до exact committed A/B PASS с byte-identical logs и замороженными `soak_hash` / `final_interest_hash`.

P4.8 control preparation уже существует, но финальный P4 acceptance остаётся fail-closed до P4.7 lifecycle acceptance.
