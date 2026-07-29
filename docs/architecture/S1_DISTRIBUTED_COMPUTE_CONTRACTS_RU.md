# S1 — Distributed Compute Contracts

**Checkpoint:** `v16.9.0-simulation-s1-distributed-compute`
**База:** `v16.8.5-domain-m0-aggregate-transactions`

## Цель

S1 вводит безопасную границу между authoritative runtime и вычислительным worker:

```text
Region Authority
→ immutable SimulationJobEnvelope
→ Compute Worker
→ MutationProposal
→ authority validation
→ M0 MutationBatch
→ authoritative commit
```

Главный инвариант:

> worker вычисляет, authority проверяет и commit’ит через M0.

Worker не получает repository, aggregate registry, live aggregate или право authoritative-записи.

## Контракты

- `SimulationJobInputReference` — identity, authority epoch, revision, tick, полный snapshot checksum и только разрешённая read-set проекция state;
- `MutationReadSet` и `MutationWriteSet` — стабильные aggregate/path declarations;
- `ExecutionBudget` — maximum operations, output bytes и instruction units;
- `DeterminismFingerprint` — hash inputs, rule package, algorithm version, seed и tick range;
- `SimulationJobEnvelope` — immutable compute request;
- `MutationProposalOperation` — UPDATE patch без authority metadata;
- `MutationProposal` — worker proposal и измеренные budgets;
- `SimulationJobResultEnvelope` — success/failure result;
- `ComputeCapabilityDescriptor` и `ComputeWorkerDescriptor` — явная capability negotiation.

## Read/write boundary

Worker получает только `projected_state`, построенный из declared read paths. Полный canonical snapshot остаётся в M0 repository и связывается с job через `snapshot_checksum`, revision, authority epoch и tick.

Proposal может менять только paths, заранее объявленные в `MutationWriteSet`. В S1 production path разрешает только `UPDATE`; CREATE/DELETE остаются M0-возможностями и будут подключены отдельным versioned compute contract.

## Local worker adapter

`LocalComputeWorkerAdapter` доказывает contract semantics без отдельного процесса и без broker SDK. Он:

1. canonical-copy job DTO;
2. проверяет worker capability и package hash;
3. вызывает чистый handler;
4. проверяет proposal against write set;
5. применяет execution budgets;
6. создаёт deterministic proposal/result hashes.

## Authority acceptance

`DistributedComputeAuthority` повторно проверяет:

- job/result identity;
- worker registration/capability;
- determinism fingerprint и package hash;
- budget limits;
- current snapshot checksum, owner, epoch, revision и tick;
- declared write set;
- kind-specific resulting snapshot validation.

После этого proposal переводится в M0 batch. Aggregate revisions и official snapshot checksums создаёт authority, не worker.

## B0 integration

`SimulationJobQueueBridge` оборачивает S1 job в B0 `JobEnvelope`. Application/compute logic не знает NATS subject, JetStream consumer или ENet channel.

ACK job delivery выполняется только после успешного M0 commit.

## Replay

Exact повтор result для того же job attempt возвращает stable response без второй mutation. Changed result для уже принятого attempt отклоняется как `COMPUTE_RESULT_CONFLICT`. Durable inbox/replay после рестарта будет добавлен на B2 поверх JetStream/inbox records.

## Не входит в S1

- NATS и JetStream SDK;
- remote worker process;
- scheduler;
- dynamic rule IR;
- production PopulationField;
- World Directory;
- distributed consensus.
