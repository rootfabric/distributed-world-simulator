# S1 — Distributed Compute Contracts

**Checkpoint:** `v16.9.0-simulation-s1-distributed-compute-fix1`
**Build ID:** `s1-distributed-compute-contracts-fix1`
**База:** `v16.8.5-domain-m0-aggregate-transactions`

## Цель

S1 вводит безопасную границу между authoritative runtime и вычислительным worker:

```text
Region Authority
→ canonical issued job registry
→ immutable SimulationJobEnvelope
→ Compute Worker
→ MutationProposal + job_checksum
→ authority-side issued job lookup
→ M0 MutationBatch
→ authoritative commit
```

Главный инвариант:

> worker вычисляет, authority проверяет результат только относительно ранее выданного issued job и commit’ит через M0.

Worker не получает repository, aggregate registry, live aggregate, authoritative object graph, SceneTree, filesystem, network adapter или право authoritative-записи.

## Контракты

- `SimulationJobInputReference` — identity, authority epoch, revision, tick, полный snapshot checksum и только разрешённая read-set проекция state;
- `MutationReadSet` и `MutationWriteSet` — стабильные aggregate/path declarations;
- `ExecutionBudget` — maximum operations, output bytes и instruction units;
- `DeterminismFingerprint` — hashes входов, job type, capability, read/write sets, rule package, algorithm version, seed и tick range;
- `SimulationJobEnvelope` — immutable compute request;
- `MutationProposalOperation` — UPDATE patch без authority metadata;
- `MutationProposal` — worker proposal, `job_checksum` и измеренные budgets;
- `SimulationJobResultEnvelope` — success/failure result с `job_checksum`;
- `ComputeCapabilityDescriptor` и `ComputeWorkerDescriptor` — явная capability negotiation.

## Authority-issued job boundary

`SimulationJobFactory` не просто формирует DTO. После полной валидации он регистрирует canonical job через `DistributedComputeAuthority.register_issued_job()`.

Authority хранит локальный runtime ledger:

```text
job_id + job_attempt
→ immutable canonical job
→ job checksum
```

Повторная регистрация:

- тот же checksum → stable replay;
- другой checksum → `COMPUTE_JOB_CONFLICT`.

`accept_result()` принимает только result. Job, возвращённый worker или transport, не используется как источник истины. Authority извлекает свой issued job по `job_id/job_attempt` и требует совпадения `job_checksum` в result и proposal.

Ошибки boundary:

- `COMPUTE_JOB_NOT_ISSUED`;
- `COMPUTE_JOB_CHECKSUM_MISMATCH`;
- `COMPUTE_JOB_CONFLICT`.

Ledger остаётся локальной S1 foundation. Durable issued-job/result inbox после рестарта authority относится к B2.

## Read boundary и exact projection

Worker получает только `projected_state`, построенный из declared read paths. Полный canonical snapshot остаётся в M0 repository и связывается с job через `snapshot_checksum`, revision, authority epoch и tick.

Job validation доказывает точное соответствие:

- каждый input reference имеет ровно одну read-set entry;
- отсутствуют дополнительные input references;
- kind/schema input совпадают с read-set identity;
- каждый declared path присутствует;
- в `projected_state` нет дополнительных полей вне read set.

Для проверки projection повторно строится canonical projection по declared paths и сравнивается с переданным `projected_state`.

## Write boundary

Proposal может менять только paths, заранее объявленные в `MutationWriteSet`.

Для каждого UPDATE проверяется:

- aggregate присутствует во входах job;
- write-set kind/schema совпадают с input identity;
- proposal kind/schema совпадают с write set;
- write-set и proposal identity совпадают с текущим authoritative snapshot;
- operation kind и paths разрешены.

S1 protocol v1 разрешает только `UPDATE`. `CREATE` и `DELETE` остаются M0-возможностями и будут подключены отдельным versioned compute extension.

## Determinism fingerprint

Fingerprint связывает:

- canonical input references и полные snapshot checksums;
- job type;
- required capability;
- read-set hash;
- write-set hash;
- rule package hash;
- algorithm version;
- deterministic seed;
- from/to ticks.

Изменение access scope, capability или job semantics меняет fingerprint даже при неизменных projected inputs.

## Local worker adapter

`LocalComputeWorkerAdapter` доказывает contract semantics без отдельного процесса и без broker SDK. Он:

1. canonical-copy job DTO;
2. проверяет worker capability и package hash;
3. вызывает чистый handler;
4. проверяет proposal against write set;
5. применяет execution budgets;
6. помещает issued `job_checksum` в proposal/result;
7. создаёт deterministic proposal/result hashes.

## Authority acceptance

`DistributedComputeAuthority` повторно проверяет:

- existence и checksum authority-issued job;
- result/proposal identity;
- worker registration/capability;
- determinism fingerprint и package hash;
- budget limits;
- current snapshot identity, checksum, owner, epoch, revision и tick;
- declared write set и authoritative kind/schema;
- kind-specific resulting snapshot validation.

После этого proposal переводится в M0 batch. Aggregate revisions и official snapshot checksums создаёт authority, не worker.

## B0 integration

`SimulationJobQueueBridge` оборачивает S1 job в B0 `JobEnvelope`. Application/compute logic не знает NATS subject, JetStream consumer или ENet channel.

ACK job delivery выполняется только после успешного M0 commit.

## Replay

Exact повтор result для того же issued job attempt возвращает stable response без второй mutation. Changed result для уже принятого attempt отклоняется как `COMPUTE_RESULT_CONFLICT`.

Повтор result после потерянного ACK не повышает M0 generation и не создаёт второй outbox record.

## Не входит в S1

- NATS и JetStream SDK;
- remote worker process;
- durable issued-job/result inbox;
- scheduler;
- dynamic rule IR;
- production PopulationField;
- World Directory;
- distributed consensus.
