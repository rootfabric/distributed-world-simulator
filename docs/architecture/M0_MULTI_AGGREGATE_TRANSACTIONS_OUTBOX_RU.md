# M0 — атомарные транзакции нескольких агрегатов и outbox

Checkpoint: `v16.8.5-domain-m0-aggregate-transactions`.

M0 вводит локальную authoritative transaction boundary над A1 aggregate snapshots и R3.1 atomic persistence. Операция сначала полностью проверяет preconditions и kind-specific adapters в staged-копии, затем одним atomic replace сохраняет:

- canonical snapshots всех aggregates;
- стабильный `MutationBatchResult`;
- replay fingerprint по `operation_id`;
- outbox records для последующей публикации.

Инвариант: **изменены все aggregates либо не изменён ни один**.

Поддерживаются `CREATE`, `UPDATE`, `DELETE`. Update требует точного owner/epoch/revision и увеличивает revision ровно на один. Create начинается с revision 0. Delete не несёт result snapshot.

Outbox является частью того же commit. Broker ACK не является authoritative commit. Публикация может повторяться после restart; `delivery_checksum` остаётся неизменным при переводе записи в `published`.

M0 не содержит NATS, JetStream, distributed consensus, cross-server transactions или Population Field gameplay.


## Staged validation и межагрегатные инварианты

Kind adapter проверяет каждый resulting snapshot отдельно. Этого недостаточно для связей между aggregates: два container snapshot могут быть валидны по отдельности, но одновременно ссылаться на один item. Поэтому coordinator обязательно использует `TransactionInvariantRegistry`. Все validators получают canonical deep-copy текущего и staged состояния и выполняются в стабильном порядке по `validator_id` до prepare. Любой отказ завершает batch без записи pending state.

Первый proof-validator проверяет двустороннюю связь item/container:

- item с `container_id` обязан присутствовать ровно в указанном container;
- container member обязан существовать как item и ссылаться обратно на этот container;
- world item с пустым `container_id` допустим;
- формально валидный double-membership batch отклоняется.

`MutationBatchResult` канонически связывает `affected_aggregates` с create/update/delete ID sets. Transaction state также проверяет двустороннюю связь operation result и outbox record по batch ID, operation ID, commit generation и simulation tick.

## Crash boundaries

`AFTER_PREPARE` оставляет только скрытый pending-файл; `load_or_empty()` не делает его authoritative. `AFTER_COMMIT` означает, что aggregate state, operation result, replay fingerprint и outbox уже сохранены; после restart повторный `operation_id` возвращает прежний result без новой mutation.

Outbox publication — отдельная локальная транзакция. Она меняет только delivery state записи и generation transaction store; aggregate snapshots остаются бит-в-бит неизменными.
