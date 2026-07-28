# ADR-010: Authority ownership отдельно от compute assignment

- Статус: принято в A0
- Дата: 2026-07-29

## Контекст

Большая симуляция требует нескольких workers для роста, погоды, химии и других процессов. Конкурентная запись нескольких серверов в один aggregate создаёт lost updates и недетерминированность.

## Решение

В каждый момент aggregate имеет одного authoritative writer. Workers получают immutable `SimulationJob`, выполняют расчёт и возвращают `MutationProposal` с base revision/tick/hash, read/write sets и budget metrics.

Только authority выполняет validation, staged commit, persistence и official snapshot/delta.

`authority_owner_id` и `compute_worker_id` являются независимыми identifiers. Compute assignment не использует authority handoff.

## Последствия

- worker count масштабируется независимо;
- job можно повторить после crash;
- stale proposal безопасно отклоняется;
- authority остаётся bottleneck commit, поэтому большие logical objects должны sharding.

## Запрещённый обход

Worker не получает live AggregateRegistry/Repository write port и не возвращает готовый authoritative snapshot как приказ заменить состояние.
