# MW9 — Durable Distributed Handoff and Crash Recovery

## Статус

```text
checkpoint: v17.11.0-simulation-mw9-durable-handoff-recovery
build_id:   mw9-durable-distributed-handoff-recovery
base:       v17.10.0-simulation-rl1-matter-summary-pyramid (ACCEPTED)
branch:     feature/mw9-durable-handoff-recovery
status:     CANDIDATE FOR INDEPENDENT REVIEW
```

MW9 делает региональную authority из MW8 восстанавливаемой после завершения процесса в любой точке handoff. Этап не добавляет consensus-кластер или cross-region transaction: durable checkpoint остаётся локальным атомарным repository одного authority-directory service.

## 1. Источник истины

Canonical authority state хранится в `MatterDurableHandoffCheckpoint`:

```text
checkpoint generation
server tick
directory revision
sorted durable leases
append-only handoff journal
previous checkpoint checksum
checkpoint checksum
```

Repository использует схему:

```text
matter-handoff-state.json
matter-handoff-state.previous.json
.matter-handoff-state.<pid>.<ticks>.pending.json
.matter-handoff-state.lock/owner.json
```

Новая generation сначала полностью записывается и перечитывается из pending-файла. Затем под межпроцессным lock повторно проверяется progression относительно фактического active, active атомарно переименовывается в previous, а pending — в active. Pending-файл сам по себе никогда не считается committed.

Lock создаётся через атомарный rename уникального candidate-каталога. На Linux живой владелец проверяется через `/proc/<pid>`; на остальных платформах foreign lock считается живым в течение консервативного timeout. Это исключает ошибочное снятие lock между sibling-процессами, для которых Godot `OS.is_process_running()` неприменим. Устаревший lock может быть удалён только после доказанного завершения владельца либо по истечении 30 секунд.

При повреждённом или отсутствующем active repository загружает previous, после чего восстанавливает active из проверенного checkpoint. Нормальный CAS-конфликт удаляет собственный pending-файл; orphan pending остаётся только после реального crash и никогда не становится committed автоматически.

## 2. Durable lease и fencing

Lease содержит:

```text
region/body identity
region root cell address
region/grid hashes
owner_id
authority_epoch
lease_revision
ACTIVE или PREPARING
issued/renew/expires ticks
exact fencing token
active transfer identity
checksum
```

Fencing token привязан к полному набору:

```text
region_id
owner_id
authority_epoch
lease_revision
transition_id
issued_tick
expires_at_tick
```

Для mutation недостаточно передать checksum token. Gate валидирует весь exact token и требует byte-semantic equality с token текущего committed lease.

Lease использует logical server tick, а не локальное wall clock. Это сохраняет детерминированность тестов и исключает зависимость canonical recovery от timezone или системного времени.

## 3. Lease transitions

Допустимы только следующие переходы:

```text
ACTIVE -> ACTIVE
  renewal: same owner, same epoch, exact next lease revision
  expired claim: epoch + 1, только после expires_at_tick

ACTIVE -> PREPARING
  source owner и epoch неизменны
  BEGIN journal record обязателен
  old fencing token закреплён в transfer fingerprint

PREPARING -> ACTIVE
  COMMITTED: target owner, epoch + 1
  ABORTED: source owner, прежняя epoch
```

Нельзя:

- обновить lease раньше `renew_after_tick`;
- claim до expiry;
- изменить owner без epoch fence;
- перескочить lease revision;
- добавить или удалить authority-region через обычный checkpoint progression;
- активировать target без terminal COMMITTED record;
- вернуть source без terminal ABORTED record.

## 4. Append-only transfer journal

Фазы:

```text
BEGIN
PACKAGE_DURABLE
TARGET_PREPARED
COMMIT_DECIDED
COMMITTED

или

BEGIN / PACKAGE_DURABLE / TARGET_PREPARED
ABORT_DECIDED
ABORTED
```

Каждая запись содержит sequence, previous-record checksum и неизменяемый transfer fingerprint:

```text
transfer/region/source/target IDs
source and target epochs
frozen lease revision
source fencing token checksum
```

История checkpoint не может быть сокращена или изменена.

## 5. Durable package

До target prepare journal сохраняет точные canonical bytes MW8 package:

```text
package_transport
package_transport_hash
package_checksum
optional RL1 summary manifest
```

`package_transport` обязан быть каноническим JSON-объектом. Его внутренний `checksum` обязан точно совпасть с `package_checksum`; transport hash отдельно защищает сами bytes.

После `PACKAGE_DURABLE` package, checksum и RL1 manifest неизменяемы для всей оставшейся journal chain.

RL1 manifest остаётся cache hint. Он может помочь target переиспользовать summary artifacts, но не участвует в Matter mass ledger и не определяет authority.

## 6. Правило recovery

После restart coordinator восстанавливает последний committed checkpoint и применяет детерминированное правило:

```text
COMMIT_DECIDED -> завершить COMMITTED и активировать target
ABORT_DECIDED  -> завершить ABORTED и вернуть source
BEGIN          -> durable ABORT_DECIDED -> ABORTED
PACKAGE_DURABLE -> durable ABORT_DECIDED -> ABORTED
TARGET_PREPARED -> durable ABORT_DECIDED -> ABORTED
```

`COMMIT_DECIDED` необратим. После него abort отклоняется даже до фактической runtime-проекции в MW8.

До durable commit decision target shadow state может быть отброшен. После decision recovery обязана завершить commit.

## 7. MW8 runtime reconciliation

Durable checkpoint является источником истины, но существующие MW8 runtime objects всё равно должны быть приведены к нему после restart.

MW9 добавляет три boundary-компонента:

- `MatterDurableRegionalAuthorityGate` — сначала проверяет durable token/lease, затем при наличии вызывает legacy MW8 gate;
- `MatterMw8DurableRuntimeAdapter` — fail-closed набор Callables для freeze/package/prepare/commit/abort и синхронизации lease;
- `MatterDurableHandoffRecoveryService` — завершает durable recovery и идемпотентно проецирует terminal journal records в runtime adapter.

Если runtime projection временно не удалась, durable решение не откатывается. Service возвращает `MATTER_DURABLE_HANDOFF_RUNTIME_RECONCILIATION_PENDING`; повторный reconcile безопасен, а adapter обязан использовать transfer ID/record checksum как idempotency key.

## 8. Split-brain fences

MW9 доказывает:

- source и target закрыты в PREPARING;
- old owner/token не пишет после commit;
- expired claim всегда увеличивает epoch;
- exact transfer replay требует исходный fencing-token fingerprint;
- checksum-only forged token не проходит;
- commit decision нельзя заменить abort decision;
- terminal lease обязан соответствовать terminal journal record;
- stale/same-generation pending checkpoint не становится active;
- два конкурентных expired-lease claims дают ровно одного durable winner;
- loser не перезаписывает active и не оставляет pending/lock;
- corrupt active восстанавливается только из валидного previous.

## 9. Граница этапа

MW9 не реализует:

- Raft/Paxos и multi-node quorum;
- общий production database;
- автоматический lease-renewal daemon;
- cross-region Matter transaction;
- two-region mass ledger;
- artifact disk cache;
- network artifact streaming;
- Kubernetes/Agones orchestration;
- изменение production Moon/world catalog.

Эти ограничения намеренны. Следующий этап MW10 добавляет cross-region transaction поверх уже durable single-region authority.
