# T1A.7 — Runtime Recovery / Interest / Scale

**Дата:** 2026-08-10  
**Ветка:** `feature/t1a7-runtime-recovery-interest-scale`  
**Base:** T1A.6 ACCEPTED @ `06f332dc99287e94ba4515ce51346c4f639d240f`  
**Architecture:** `GLOBAL-P0-2026-08-10-R2`  
**Control:** `PC0-2026-08-10-R1`  
**Статус:** `ARCHITECTURE / REUSE AUDIT`

## Цель

T1A.6 доказал цепочку:

```text
canonical Construction runtime
  -> runtime snapshot
  -> existing M3 transport
  -> client replica
  -> derived presentation
```

T1A.7 должен сделать эту цепочку пригодной для recovery, reconnect, late-interest и большого числа constructs/interactive runtime subjects.

Главное правило:

```text
recovery != new persistence foundation
interest != permanent identity
scale != broadcast everything
transport != canonical gameplay truth
```

## Что уже есть и должно быть переиспользовано

### 1. Construction runtime truth

Используем существующие:

```text
ConstructionRuntimeStateStore
ConstructionAffordanceRuntimeExecutor
ConstructionRuntimeSnapshot
ConstructionRuntimeReplicaStore
T1A6 M3 server/client adapters
```

T1A.7 не создаёт второй runtime store или второй operation ledger.

### 2. Recovery / durability pattern

Matter уже задаёт корректный pattern через:

```text
matter_state_repository.gd
matter_state_coordinator.gd
```

`MatterStateCoordinator` отделяет repository I/O от runtime components, строит checkpoint, валидирует identity до restore, делает backup перед restore и rollback при частичном failure.

Для Construction нужно повторно использовать **этот architectural pattern и существующие project persistence boundaries**, но не импортировать Matter-specific body/grid semantics и не создавать private T1 filesystem/repository foundation.

T1A.7 recovery adapter должен работать поверх Construction-owned runtime state и существующего persistence owner/API.

### 3. Interest / reconnect pattern

MW7 уже доказывает:

```text
revisioned interest subscription
active + pending subscription
session binding
reconnect with same client identity / new peer+session
regional snapshot fallback
bounded delta replay
projection hash / ack fence
late observer snapshot
irrelevant mutations not sent
```

Ключевые реализации:

```text
scripts/simulation/matter/interest/matter_interest_server.gd
scripts/simulation/matter/interest/matter_interest_replica_client.gd
```

Construction не должен зависеть от Matter cell identity как от собственной permanent identity. T1A.7 должен взять pattern: **subscription revision + projection + baseline/replay + session fence**, но selection source должен быть Construction/world query/interest adapter, а не новая global interest registry.

## Предлагаемая composition

```text
                  existing persistence owner
                           |
                           v
canonical ConstructionRuntimeStateStore
           |               |
           |               +--> recovery codec/adapter
           |                    (domain projection only)
           |
           +--> ConstructionRuntimeProjection
                      |
          +-----------+-----------+
          |                       |
          v                       v
 interest selector          dirty/revision stream
 (existing world/           bounded per client
  spatial/query input)            |
          |                       |
          +-----------+-----------+
                      v
          existing M3/NX transport
                      |
                      v
          ConstructionRuntimeReplicaStore
                      |
                      v
             derived presentation
```

## T1A.7A — Recovery Contract

Первый подэтап должен быть минимальным.

### Persisted semantic state

Сохранять только canonical runtime semantics:

```text
construct_id
runtime subjects
subject revisions
runtime store generation
required operation replay state if existing durability owner requires it
authority recovery generation/epoch metadata through existing authority boundary
```

Не сохранять:

```text
Node3D paths
mesh/visual ids
peer_id
session_id
server_id
LOD/HLOD
camera interest
current packet/channel state
presentation interpolation state
```

### Restore invariant

До мутации live runtime:

```text
decode
-> schema validate
-> construct/runtime identity validate
-> checksum validate
-> all component restore validation
-> backup live state
-> restore atomically
-> rollback on failure
```

После recovery новый authority epoch должен позволять clients отбросить старую transport history и принять authoritative baseline.

## T1A.7B — Late Interest / Reconnect

Минимальный contract:

```text
client_id
session_id (transport fence only)
authority_epoch
interest_revision
selection descriptor / query input
known projection revision/checksum
```

Semantics:

```text
same interest revision + same checksum -> replay
same revision + different selection -> reject
older revision -> reject
new revision -> pending interest
new interest baseline accepted atomically
old view remains valid until new baseline is complete
reconnect may replay bounded history when compatible
otherwise full authoritative projection snapshot
```

Это повторяет безопасные свойства MW7, но не копирует Matter cell/address ontology.

## T1A.7C — Selective Replication

T1A.6 отправляет маленький D0 full runtime snapshot. Для scale нужен projection per client.

Начальный candidate:

```text
server canonical store
-> dirty construct/runtime-id set
-> per-client relevant construct set
-> reliable mutation/update stream for discrete runtime state
-> reliable full projection baseline/resync
```

На этом этапе **не нужно** делать lossy runtime truth. Двери, генераторы, контейнерные locks и workstation state дискретны и должны сходиться точно.

Оптимизация bandwidth может позже добавить compact delta DTO, но full baseline/resync остаётся correctness path.

## T1A.7D — Scale Gate

Нужен synthetic headless lab без одного presentation Node на subject.

Минимальные масштабы:

```text
100 constructs x 10 runtime subjects
1,000 constructs x 10 runtime subjects
10,000 runtime subjects canonical
```

Проверять:

```text
canonical subject count
selected subject count per client
bytes/messages projected vs broadcast baseline
dirty subjects processed per mutation
full baseline size
replay-log bound
connect/reconnect synchronization work
server projection time
replica apply time
memory growth over repeated interest moves
```

Acceptance принцип:

```text
unrelated client receives 0 runtime mutations for unrelated constructs
work per mutation scales with dirty/relevant set, not total world subject count
replay history has explicit bound
full baseline is available as fallback
no runtime Node3D requirement
```

## Recovery + interest acceptance scenario

Минимальный end-to-end test:

```text
server starts D0 + several unrelated constructs
A interest includes D0
B interest excludes D0
A opens D0 door
A receives mutation
B receives no D0 runtime mutation
server persists/checkpoints through existing durability boundary
server/runtime is reconstructed
new authority epoch starts
A reconnects with old projection cursor
old epoch traffic is rejected
A receives recovered OPEN door baseline or valid replay
A presentation becomes OPEN
B still receives no D0 state
A moves interest away, then back
old view is retained until new baseline swaps atomically
final server/A checksum converges
```

## Stop rules

T1A.7 implementation должен остановиться и вынести решение в P0/owner branch, если потребуется:

```text
new global interest-region identity
new world query fabric owner
new authority registry
new persistence repository foundation
new cross-domain transaction coordinator
new network channel namespace
new permanent spatial identity
```

## Substage order

```text
T1A.7.0 Architecture / reuse audit          <- current
T1A.7.1 Recovery snapshot + restore contract
T1A.7.2 Late-interest baseline + reconnect
T1A.7.3 Dirty/selective runtime replication
T1A.7.4 Scale/soak lab
T1A.7.5 Composition acceptance
```

После T1A.7 acceptance можно переходить к следующему Construction-scale этапу без накопления скрытой broadcast/persistence задолженности.
