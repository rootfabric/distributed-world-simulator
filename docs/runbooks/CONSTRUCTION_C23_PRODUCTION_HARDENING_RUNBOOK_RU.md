# C23 — Production Hardening Runbook

**Область:** construction production boundary
**Версия state envelope:** 2
**Совместимость чтения:** 1–2
**Версия operation DTO:** 1
**Recovery slots:** primary + previous

## 1. Неизменяемые production-инварианты

1. `ConstructAggregate`, Item Graph и C2B/M0 остаются единственным authoritative состоянием.
2. C23 не выполняет item mutation самостоятельно: он вызывает только переданный authoritative executor.
3. Любая операция имеет immutable `operation_id`, payload checksum и общий checksum.
4. Повтор того же `operation_id` с другим checksum отклоняется как конфликт.
5. Terminal allow/deny сохраняется и воспроизводится точно после restart.
6. Без authorizer сервис не запускается; повторный `setup()` запрещён; permission boundary fail-closed.
7. Audit не содержит payload, item metadata, токены или произвольные labels.
8. Повреждённый checkpoint никогда не загружается частично: он помещается в quarantine, затем используется предыдущий валидный slot.

## 2. Развёртывание и rolling upgrade

Перед добавлением новой версии узла:

1. Построить `ConstructionReleaseDescriptor` для текущей и новой версии.
2. Выполнить `ConstructionReleasePolicy.negotiate()`.
3. Запретить writer traffic, если пересечение state/operation versions пусто или отсутствуют обязательные capabilities `audit` и `exact-replay`.
4. Новую версию сначала поднять с `read_only = true`.
5. Проверить checksum snapshot, replay store, audit tail и metrics.
6. Переключить writer только через существующий C17 migration/authority protocol.
7. После переключения оставить предыдущую версию как reader до окончания rollback window.

Нельзя одновременно держать два writer одного aggregate. C23 negotiation не заменяет C17 fencing и authority epoch.

## 3. Save и migration

Текущая запись использует `planet_simulator.construction_production_state.v2`:

- `release_id`;
- reader compatibility range;
- `created_tick`;
- payload checksum;
- envelope checksum.

Legacy v1 читается только через явную migration `1 → 2`. Migration сохраняет payload без изменения и возвращает `migration_trace`. Неизвестная версия отклоняется.

## 4. Exact replay

Порядок обработки:

```text
validate DTO
→ terminal replay lookup
→ release/read-only fence
→ rate limit
→ permission authorize
→ authoritative executor
→ terminal replay record
→ metrics + hash-chain audit
→ response
```

Replay lookup выполняется до rate limit и повторной авторизации, потому что он возвращает уже принятое terminal решение. Конфликт checksum для существующего ID всегда отклоняется.

Authoritative executor также обязан быть idempotent. Это закрывает crash-window после authoritative commit, но до записи terminal result C23.

## 5. Corruption recovery

Каждый checkpoint записывается как checksum-pinned slot. Хранятся два последних slot.

При восстановлении:

1. проверить slot checksum;
2. проверить state envelope checksum;
3. проверить payload checksum;
4. проверить каждый вложенный subsystem state и cross-invariants `generation ↔ replay`, `replay_entries ↔ entries`, `rate_limit_subjects ↔ subjects`;
5. при ошибке поместить slot в quarantine;
6. попробовать предыдущий slot;
7. при отсутствии валидного slot остановить writer и вернуть `NO_VALID_CONSTRUCTION_PRODUCTION_CHECKPOINT`.

Запрещено исправлять checksum на месте или загружать уцелевшие части повреждённого state. Импорт recovery slots допускается только при строгом возрастании sequence и `sequence < next_sequence`.

## 6. Security и audit

Authorizer получает только:

- `subject_id`;
- `construct_id`;
- `action`;
- `permission_epoch`.

Audit event содержит identity операции, решение, error code, tick, previous hash и checksum. Payload не записывается. Нарушение цепочки обнаруживается при `load_state()`.

Rate limiter использует детерминированное fixed window по `subject_id + action`. Его состояние входит в checkpoint, поэтому restart не обнуляет защиту. Tick и retry boundary обязаны оставаться внутри safe JSON integer range.

Error code от authorizer/executor принимается только как token. Runtime objects и не-JSON-safe details не попадают в terminal result или audit; безопасные details канонизируются перед replay storage.

## 7. Metrics

Разрешены только фиксированные имена counters/gauges из `ConstructionObservability`. Произвольные labels запрещены, чтобы не создать uncontrolled cardinality.

Минимальные alerts:

- рост `operations_denied`;
- любое увеличение `checkpoints_recovered`;
- устойчивый рост `operations_failed`;
- частые `operations_rate_limited`;
- расхождение `replay_entries` и terminal operation count;
- нарушение audit checksum chain.

## 8. Chaos gate

Перед release обязательны сценарии:

- crash после authoritative execution, до terminal record;
- crash после terminal record, до ответа;
- corrupt latest checkpoint и fallback;
- повтор старой операции после restart;
- operation ID conflict;
- stale permission epoch;
- incompatible rolling upgrade;
- DTO mutation/fuzz matrix;
- deterministic soak минимум 2 000 операций.

## 9. Команды проверки

Linux:

```bash
./RUN_C23_PRODUCTION_HARDENING_TESTS.sh /path/to/godot
```

Windows PowerShell:

```powershell
./RUN_C23_PRODUCTION_HARDENING_TESTS.ps1 -GodotPath C:\Godot\godot.windows.editor.double.x86_64.console.exe
```

Полный gate:

```powershell
$env:GODOT_BIN = "C:\Godot\godot.windows.editor.double.x86_64.console.exe"
./RUN_WORLD_REGRESSION_TESTS.ps1
```

## 10. Rollback

1. Остановить выдачу новых writer leases.
2. Дождаться drain текущих operations.
3. Зафиксировать checkpoint и audit tail.
4. Вернуть authority предыдущему compatible release через C17 protocol.
5. Восстановить последний checkpoint, читаемый предыдущей версией.
6. Проверить exact replay последней terminal операции.
7. Только после checksum convergence возобновить writer traffic.
