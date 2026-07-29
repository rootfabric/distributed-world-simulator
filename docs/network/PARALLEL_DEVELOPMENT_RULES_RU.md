# Правила параллельной разработки distributed runtime и gameplay

## Текущий режим

```text
runtime candidate: S0 spatial substrate
accepted aggregate base: A1 generic aggregates
next implementation after acceptance: T1 multi-peer transport v2
```

До принятия S1 основной foundation-track идёт последовательно. Разрешено параллельно развивать gameplay только при соблюдении стабильных command/persistence boundaries.

## 1. Tracks

### Track F — Foundation

```text
H0 → A1 → S0 → T1 → B0 → M0 → S1
```

В один момент активен один основной F-checkpoint.

### Track G — Gameplay

- items/inventory;
- construction;
- controllers;
- terrain/visual worlds;
- robots.

Новая authoritative операция обязана иметь domain command и не должна добавлять новый прямой UI mutation path.

### Track T — Test Infrastructure

- N2 harness extensions;
- external process descriptors;
- readiness probes;
- fault injection;
- JSON/JUnit;
- future NATS/worker orchestration.

### Track C — Content research

- type schemas;
- vegetation model;
- rule IR design;
- visual procedural prototypes.

До P0 этот track не меняет authoritative runtime или spatial contracts.

## 2. Shared critical files

Изменения в следующих слоях требуют отдельного versioned checkpoint:

```text
network DTO/protocol frame
authority/revision semantics
aggregate descriptor/registry
repository transaction format
runtime topology
message bus ports
spatial address/shard contracts
```

Gameplay branch не расширяет эти контракты ad hoc.

## 3. Обязательный путь новой gameplay-команды

```text
Input/UI/AI
→ client/domain command adapter
→ validation + operation ID
→ authoritative application service
→ staged mutation
→ persistence/result
→ snapshot/delta
→ client replica/presentation
```

H0 уже предоставляет network-first composition и client replica boundary. Старые локальные paths могут временно существовать только как legacy/offline paths; новая authoritative функция обязана иметь network command path, а gameplay UI переводится на client replica отдельными вертикальными checkpoint.

## 4. Aggregate rule

Новая сущность не обязана использовать `WorldEntityAggregate`.

До A1:

- новые non-item aggregate implementations не добавляются в runtime;
- проводится только research/schema work.

После A1 aggregate kind обязан иметь:

```text
stable aggregate_id
exact state_schema
adapter validator
authority/revision/tick
snapshot/delta
persistence adapter
spatial_scope
```

## 5. Worker rule

Worker:

- читает immutable job input;
- не получает repository write port;
- возвращает proposal;
- объявляет read/write sets;
- ограничен budget;
- не является authority.

Любой direct worker mutation запрещён.

## 6. Transport rule

Application/domain зависит от semantic port, а не от implementation.

Запрещено:

```text
nats.publish inside domain
enet peer calls inside aggregate
HTTP URL inside authoritative state
broker subject as entity identity
```

## 7. Merge gates

### Foundation patch

```text
focused contracts
negative/bypass tests
relevant loopback/process scenario
full network profile
full world regression
updated ADR/checkpoint/roadmap
```

### Gameplay patch

```text
domain test
persistence/replay test
no direct presentation mutation
network command compatibility
existing process regression
```

### Test infrastructure patch

```text
expected failure classification
process cleanup
atomic reports
cross-platform path handling
no false PASS on stderr/exit mismatch
```

## 8. Branch policy

```text
feature/h0-listen-host-runtime
feature/a1-generic-aggregate-foundation
feature/t1-multi-peer-transport-v2
feature/t1-multi-peer-transport-v2
feature/b0-message-bus-contracts
feature/m0-aggregate-transactions
feature/s1-distributed-compute-contracts
```

Review fixes remain in the same unaccepted feature branch.

## 9. No-go list

До foundation gates нельзя:

- добавлять giant universal aggregate;
- хранить every grass blade as entity;
- внедрять NATS subject logic в domain;
- строить Directory route только по process/peer ID;
- применять несколько partial commits для одной materialization;
- создавать shared client/server object references;
- использовать generated arbitrary GDScript в authority.
