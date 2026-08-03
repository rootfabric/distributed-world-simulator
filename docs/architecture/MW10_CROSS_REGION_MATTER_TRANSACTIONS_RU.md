# MW10 — Cross-region Matter Transactions

## Статус

```text
checkpoint: v17.12.0-simulation-mw10-cross-region-matter-transactions
build_id:   mw10-cross-region-matter-transactions
base:       v17.11.0-simulation-mw9-durable-handoff-recovery (ACCEPTED, fix2)
branch:     feature/mw10-cross-region-matter-transactions
status:     CANDIDATE FOR INDEPENDENT REVIEW
```

MW10 добавляет атомарную транзакцию для одной Matter-операции, пересекающей две и более MW9 authority-regions. Этап не вводит глобальный consensus: coordinator опирается на точные committed MW9 leases, durable локальный transaction repository и детерминированное правило recovery.

## 1. Инвариант атомарности

Для каждого плана фиксируются минимум два участника в лексикографическом порядке `region_id`. Один transaction ID охватывает один body и один распределённый mass ledger.

```text
BEGIN + reservations всех regions
  ↓
PREPARE region A
  ↓
PREPARE region B
  ↓
PREPARED
  ↓
COMMIT_DECIDED        необратимая точка
  ↓
COMMIT region A
  ↓
COMMIT region B
  ↓
COMMITTED + единый invalidation batch + outbox
```

До `COMMIT_DECIDED` recovery обязан abort-ить транзакцию и rollback-нуть только реально подготовленные регионы. После `COMMIT_DECIDED` recovery обязан завершить все отсутствующие commits. Частично committed canonical состояние не может быть объявлено aborted.

## 2. Exact authority fence

Каждый participant содержит:

- body/region/root identity;
- owner ID;
- authority epoch и lease revision;
- полный MW9 fencing token;
- предыдущий RL0 `RepresentationSourceRevision`;
- canonical mutation payload и hash;
- dirty bounds и affected scopes.

Authority gate проверяет точное равенство committed MW9 lease и participant. Сравнение только epoch или checksum token недостаточно. После durable reservation plan проверяется повторно: если lease изменился между первой проверкой и commit checkpoint, transaction автоматически получает `ABORT_DECIDED → ABORTED`, reservations освобождаются, Matter runtime не вызывается.

MW9 handoff обязан использовать `MatterCrossRegionHandoffInterlock`. Пока region присутствует в durable reservation set, handoff отклоняется с `MATTER_CROSS_REGION_TRANSACTION_RESERVES_HANDOFF_REGION`.

## 3. Distributed mass ledger

План содержит material rows для каждого региона и явные внешние inputs/outputs. Для каждого материала вычисляется:

```text
sum(region removed) + external input
-
sum(region added) - external output
=
residual
```

`abs(residual)` обязан укладываться в tolerance. Ledger сортируется канонически и входит в checksum плана. Commit decision не создаётся для несбалансированного плана.

## 4. Durable journal

Фазы:

```text
BEGIN
PREPARING
PREPARED
COMMIT_DECIDED
COMMITTING
COMMITTED

или

BEGIN / PREPARING / PREPARED
ABORT_DECIDED
ROLLING_BACK
ABORTED
```

Каждая запись хранит:

- immutable plan;
- append-only prepare/commit/rollback receipts;
- sequence и previous record checksum;
- decision;
- global commit hash;
- terminal invalidation batch.

Durable validator дополнительно доказывает:

- prepare receipts образуют точный prefix canonical participant order;
- commit receipts образуют точный prefix того же порядка;
- rollback receipts соответствуют suffix подготовленного множества и выполняются в обратном порядке;
- commit/rollback receipt ссылается на точный prepare checksum;
- prepare source revision строго продвигает предыдущую source revision;
- commit сохраняет подготовленную revision;
- rollback возвращает точную previous revision;
- global commit hash заново вычисляется из plan checksum и всех prepare receipt checksums;
- terminal invalidation покрывает ровно всех participants и связан с их exact source revisions, dirty bounds и scopes.

## 5. Durable checkpoint и repository

Checkpoint хранит:

- append-only transaction records;
- region reservations;
- terminal operation results;
- invalidation outbox;
- generation/server tick/previous checksum.

Repository использует атомарную схему:

```text
matter-cross-region-transactions.json
matter-cross-region-transactions.previous.json
.matter-cross-region-transactions.<pid>.<ticks>.pending.json
.matter-cross-region-transactions.lock/owner.json
```

Shared reservation нельзя изменить in-place: её checksum, participant binding и acquired tick остаются byte-semantic неизменными до terminal record. BEGIN добавляет полный participant region set одним checkpoint; terminal record удаляет тот же set. Result/outbox могут появиться только вместе с соответствующим terminal record. Публикация outbox выполняется отдельной generation.

Межпроцессный lock наследует проверенную MW9 модель: atomic candidate-directory rename, `/proc/<pid>` на Linux и консервативный stale timeout на других платформах.

## 6. Representation invalidation

Отдельные region invalidations не публикуются после локального prepare или частичного commit. После последнего commit формируется один `MatterCrossRegionInvalidationBatch`, привязанный к global commit hash.

Сначала terminal checkpoint атомарно сохраняет:

```text
COMMITTED record
operation result
unpublished outbox record
release всех reservations
```

Только затем runtime publisher получает batch. Ошибка публикации не откатывает canonical commit; restart повторяет unpublished outbox идемпотентно.

Это даёт RL2/RL3 единую видимую границу revisions: proxy или mesh, пересекающий regions, никогда не строится из смеси pre-commit и post-commit состояния, если consumer соблюдает batch frontier.

## 7. Recovery

```text
COMMIT_DECIDED / COMMITTING -> завершить commit remaining regions
ABORT_DECIDED / ROLLING_BACK -> завершить rollback prepared regions
BEGIN / PREPARING / PREPARED -> записать ABORT_DECIDED и rollback
COMMITTED + unpublished outbox -> повторить publication
```

Runtime adapter обязан быть идемпотентным по `(transaction_id, region_id, action)`. Receipt в durable journal является доказательством завершённого шага; recovery его не выполняет повторно.

## 8. Process-level acceptance

MW10 process-suite моделирует:

- hard crash после первого region commit при durable `COMMIT_DECIDED`;
- restart и завершение второго commit;
- hard crash после первого prepare до decision;
- restart, abort и rollback только подготовленного region;
- два sibling Godot-процесса, одновременно резервирующие пересекающийся region set;
- ровно одного durable winner, отсутствие leaked pending/lock у loser.

## 9. Граница этапа

MW10 не реализует:

- Raft/Paxos или multi-directory quorum;
- cross-body Matter transaction;
- long-running saga между Matter, Item Graph и Construction;
- distributed deadlock detector для произвольного динамического lock set;
- coarse SDF/mesh generation;
- representation network streaming;
- production database/transport;
- изменение production Moon/world catalog.

Следующий этап — RL2: multiresolution Matter meshing и cross-level transitions поверх устойчивого multi-region revision frontier.
