# MW7 — региональный interest management для persistent matter

## Статус

```text
checkpoint: v17.7.0-simulation-mw7-matter-interest-replication
base: v17.6.0-simulation-mw6-matter-network-replication / fix2 (ACCEPTED)
branch: feature/mw7-matter-interest-replication
scope: isolated asteroid matter track
production Moon changed: false
world catalog changed: false
```

## Цель

MW6 доказал единственный authoritative путь matter mutation, но его full snapshot содержит весь persistent sparse store тела. Это приемлемо для лабораторного астероида, однако не масштабируется на планету или длительно изменяемый мир.

MW7 сохраняет глобальную каноническую последовательность MW6 на сервере и добавляет над ней независимые клиентские проекции. Каждый клиент получает только persistent bricks своей наблюдаемой области. Процедурные revision-0 bricks по-прежнему генерируются локально и никогда не передаются.

## Два уровня последовательности

Сервер хранит два разных понятия порядка:

1. `global stream_sequence` MW6 — канонический порядок всех terminal mutation outcomes тела;
2. `region_sequence` MW7 — порядок только тех committed изменений, которые пересекают конкретную subscription.

Нерелевантная глобальная мутация не повышает `region_sequence` клиента и не создаёт для него сетевой кадр. Это позволяет клиентам разных областей иметь разные компактные projection streams, не меняя глобальный authoritative journal.

## Interest subscription

Подписка задаётся checksum-protected DTO:

```text
subscription_id
client_id
authority_epoch
interest_revision
cell_level
center_cell_address
radius_cells
```

Форма области в MW7 — ограниченный cube в octree-grid на фиксированном уровне. Принадлежность определяется Chebyshev distance в индексах cells:

```text
max(|dx|, |dy|, |dz|) <= radius_cells
```

`radius_cells` ограничен значением `8`, то есть максимумом `17³ = 4913` cells до clipping на границе root.

`interest_revision` является fence:

- меньшая revision отклоняется;
- та же revision с другим checksum отклоняется;
- новая revision создаёт replacement regional projection.

## Двухфазная смена области

Клиент не очищает текущую проекцию сразу после локального запроса новой области.

```text
active subscription/view
→ pending subscription
→ серверный replacement REGION_SNAPSHOT
→ атомарная замена store
→ invalidation entered + left brick presenters
```

До replacement snapshot старая область остаётся видимой. Уже находившиеся в transport-очереди кадры старой active subscription могут быть применены. Delta новой pending subscription запрещён до snapshot, потому что у него ещё нет доказанной projection base.

## Региональная проекция

Projection state клиента состоит только из:

- subscription identity/checksum;
- persistent snapshots revision `>= 1` внутри области;
- `region_sequence`;
- source global stream cursor последнего релевантного изменения;
- `projection_hash`.

Projection hash включает body/authority identity, subscription checksum, оба sequence и sparse-store hash. Поэтому нельзя незаметно:

- пропустить релевантный brick;
- подменить revision;
- применить delta к другой области;
- подтвердить чужой projection state.

Региональная replica не копирует глобальный mutation journal. Полный journal остаётся authoritative state MW5/MW6. Командный result доступен инициатору отдельно, а regional delta несёт result transport только как проверяемый контекст изменения.

## Серверный pipeline

`MatterInterestServer` регистрируется наблюдателем уже принятого `MatterAuthoritativeServer`.

```text
MW6 authoritative delta
→ exact decode changed persistent snapshots
→ фильтрация для каждой subscription
→ staging regional projection
→ region_sequence + 1
→ MatterInterestDelta
→ ReplicationEnvelope(kind=INTEREST)
```

MW6 full replicas продолжают получать глобальные frames. Interest peers регистрируются в authority только для command ownership и не получают full sparse-store snapshot от MW6.

Ошибки observer-проекции не откатывают уже committed canonical mutation. Они записываются в `replication_observer_errors`; regional client после разрыва sequence/hash обязан перейти на snapshot resync.

## Delta и snapshot

### REGION_DELTA

Содержит:

- previous/target regional sequence;
- source global stream sequence;
- operation identity и exact result transport;
- только релевантный subset изменённых persistent snapshots;
- base/target projection hashes.

Клиент проверяет sequence, global cursor, base hash и subscription identity, затем атомарно применяет snapshots. При target-hash mismatch store и cursors восстанавливаются из backup.

### REGION_SNAPSHOT

Содержит полную persistent проекцию одной subscription, а не полный sparse store тела. Используется:

- при первом подключении к уже изменённой области;
- после новой interest revision;
- при отсутствии replay chain;
- после eviction replay-log;
- после server restart или projection hash mismatch.

Snapshot атомарно заменяет regional store и удаляет bricks, вышедшие из области.

## Reconnect

Клиент сообщает:

```text
known_region_sequence
known_projection_hash
subscription transport
```

Сервер выбирает:

- `CURRENT` — региональное состояние совпадает;
- `DELTA_REPLAY` — доступна непрерывная региональная цепочка и совпадает base hash;
- `REGION_SNAPSHOT` — gap, eviction, новая subscription или hash mismatch.

Replay-log независим для каждой subscription/client projection. Он не является durable журналом и после server restart может быть пустым; в этом случае snapshot строится из authoritative MW5 store.

При reconnect сервер также сверяет сохранённый projection cache с текущим authoritative persistent store. Если observer-проекция когда-либо пропустила изменение, state пересобирается с `region_sequence = 0`, и клиент получает replacement snapshot вместо продолжения ложной replay-цепочки.

## Acknowledgement

Ack привязан к:

- client/session;
- authority epoch;
- subscription id/revision;
- acknowledged region sequence;
- projection hash.

Сервер принимает только hash, ранее вычисленный для указанного regional sequence, и отклоняет rollback acknowledgement.

## Exact transport

Все float-bearing DTO внутри frames используют принятый MW5 transport:

```text
planet_simulator.matter_persistence_transport.v1
ieee754-binary64-le-hex
```

Новый decimal JSON path не создаётся. `NetworkCommandEnvelope`, `NetworkCommandGateway` и `ReplicationEnvelope` переиспользуются без альтернативного сетевого стека.

## Граница этапа

MW7 не реализует:

- cross-server interest handoff;
- authority migration между matter servers;
- spatial query index сложнее bounded cell cube;
- adaptive interest LOD;
- bandwidth compression/fragmentation больших regional snapshots;
- durable regional replay logs;
- production Moon integration;
- planetary region files и background compaction.

Эти задачи относятся к следующим checkpoints регионального хранения и распределённого authority.

## Focused acceptance

Runner:

```text
RUN_MW7_MATTER_INTEREST_TESTS.ps1
RUN_MW7_MATTER_INTEREST_TESTS.sh
```

Focused-профиль проверяет:

- cell index/path roundtrip и bounded region enumeration;
- отказ oversized subscription;
- отсутствие утечки distant mutation в чужую область;
- regional snapshot без full-body sparse store;
- enter/leave с двухфазной replacement snapshot;
- presenter invalidation entered/evicted bricks;
- projection ack и forged hash rejection;
- disconnected subscription продолжает строить региональный replay;
- reconnect через contiguous delta replay;
- snapshot fallback после replay eviction;
- sequence-gap resync без частичной записи;
- отсутствие ошибок authority replication observer.
