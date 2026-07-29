# Checkpoint v16.8.5 — M0 Aggregate Transactions

Ветка: `feature/m0-aggregate-transactions`.

Реализованы строгие контракты `MutationBatch`, aggregate preconditions, create/update/delete operations, stable result, operation ledger, atomic transaction state, crash-safe repository и transactional outbox.

Acceptance gates:

- перенос item между двумя containers обновляет три aggregates одним commit;
- exact replay не выполняет вторую mutation;
- changed payload с тем же operation ID отклоняется;
- stale/invalid aggregate приводит к полному rollback;
- cross-aggregate conservation validator отклоняет double membership до prepare;
- crash после prepare не публикует staged state;
- crash после commit восстанавливает stable result;
- outbox сохраняется атомарно и отмечается published независимо от aggregate state.


Дополнительные hardening gates:

- `MutationBatchResult` effect sets совпадают с canonical affected aggregate list;
- persisted operation result и outbox records имеют взаимные ссылки и одинаковые commit metadata;
- M0 PowerShell summary публикуется атомарно и runner безопасно обрабатывает native stderr;
- staged invariant validators обязательны для coordinator composition.
