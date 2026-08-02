# C23 — Production Hardening

**Дата:** 2026-08-02
**База:** C22 Compiled Construct Proxies and Hierarchical Detail Streaming, IMPLEMENTED CANDIDATE с documented focused gate 191 assertions
**Статус поставки:** IMPLEMENTED CANDIDATE
**Рекомендуемая ветка:** `feature/c23-production-hardening`

## Условие старта

C13–C21 в проектной документации имеют статус `ACCEPTED`. C22 содержит полный vertical slice, focused runner и validation matrix; его формальный статус остаётся `IMPLEMENTED CANDIDATE`, поэтому C23 не переобъявляет C22 принятым, а строится поверх фактически реализованных контрактов.

## Задача

C23 добавляет production boundary вокруг существующего authoritative construction executor. Он не создаёт новый Item Graph и не меняет `ConstructAggregate` напрямую.

```text
versioned operation DTO
→ exact replay gate
→ release/read-only fence
→ bounded rate limiter
→ permission authorizer
→ existing authoritative executor
→ terminal journal
→ metrics + tamper-evident audit
→ backward-compatible checkpoint
```

## Реализованные контракты

### Versioned operation DTO

`ConstructionProductionOperation` содержит:

- immutable operation/subject/construct identities;
- action и permission epoch;
- release ID и operation version;
- deterministic tick;
- JSON-safe payload checksum;
- общий checksum.

DTO имеет exact field validation. Runtime objects, неизвестные поля, unsafe числа, неверные версии и mutation checksum отклоняются.

### Backward-compatible state

`ConstructionStateEnvelope` поддерживает:

- чтение legacy v1;
- текущую запись v2;
- explicit migration trace `1 → 2`;
- reader compatibility range;
- payload и envelope checksums.

Unknown schema/version, unsafe checkpoint tick, повторная инициализация и partial corruption fail closed.

### Rolling upgrades

`ConstructionReleasePolicy` вычисляет пересечение state/operation versions и capabilities. Несовместимые releases и отсутствие state-critical capabilities `audit + exact-replay` отклоняются. Candidate может быть поднят read-only до передачи writer authority через C17.

### Replay old operations

`ConstructionReplayStore` хранит terminal result по operation ID, сортирует export state и сохраняет checksum. Повтор идентичной операции возвращает точный result без нового authoritative mutation. Тот же ID с другим checksum отклоняется.

### Observability и audit

`ConstructionObservability` использует фиксированный набор counters/gauges без произвольных labels. Audit:

- не сохраняет payload;
- содержит monotonic event index;
- связан `previous_hash`;
- checksum-pinned;
- проверяется полностью при restore; gauge `audit_events` обязан совпадать с длиной цепочки.

### Security и rate limits

Сервис не запускается без authorizer. Permission check получает subject, construct, action и epoch. Fixed-window limiter сохраняется в checkpoint, ограничивает `subject + action` и не допускает выход tick/retry boundary за safe JSON integer. Невалидные error codes и runtime details от внешнего authorizer/executor санитизируются до записи terminal result.

### Corruption recovery

`ConstructionRecoveryStore` держит два slot. Последний повреждённый slot quarantine-ится, после чего загружается предыдущий валидный checkpoint. Частичное восстановление запрещено. Импорт slot-ов требует валидных checksum и строгой монотонности sequence.

### Chaos boundaries

Проверяются две crash-window:

1. authoritative execution завершён, terminal record C23 ещё не записан;
2. terminal record записан, ответ потерян.

Первая требует idempotent authoritative executor; вторая закрывается replay store без повторного executor call.

## Focused test profile

Добавлены четыре профиля:

```text
contracts:    49 assertions expected
integration:  63 assertions expected
chaos:        27 assertions expected
soak:       4048 assertions expected
total:      4187 assertions expected
```

Soak выполняет два независимых детерминированных прогона по 2 000 operations, десять checkpoints и exact replay на каждой checkpoint boundary. Сравниваются final state checksum и audit tail.

## Runtime gate

В текущей рабочей среде double-precision Godot executable из Library не materialized из-за отказа файлового backend, а системный Godot отсутствует. Поэтому поставка не помечена `ACCEPTED`: code, runners и static consistency gate подготовлены, но обязательный Godot editor/focused/world execution должен быть выполнен принимающей средой.

## Ожидаемый полный gate

```text
C23 focused:      4/4 profiles, 4187 assertions
C22 focused:      191 assertions
C2B regression:   258 assertions
C9 regression:    204 assertions
C13–C21:          PASS
Network N0–M4:    PASS
World regression: 152/152 tests, 155 steps
Main-scene CLI:   6/6
Git diff check:   PASS
```

## Delivery

- production hardening scripts: 10;
- focused tests: 4;
- fixture: 1;
- dedicated Linux/PowerShell runners;
- world regression registration;
- config, validation, checkpoint и runbook;
- patch manifest с исходными путями и `.gd.uid` для всех новых scripts/tests.

## Следующее решение

После независимого запуска Godot gate:

- при полном PASS сменить статус C23 на `ACCEPTED`;
- при любой parser/runtime/regression ошибке выпустить `fix1`, не меняя authority boundary.
