# V0-SM0 — экспериментальный multiserver roadmap

**Дата фиксации:** 2026-08-16  
**Статус:** SUPPLEMENTARY EXPERIMENTAL VECTOR / НЕ PRODUCTION COMMITMENT  
**Ветка:** `feature/sm0-two-authority-seamless-handoff-lab`  
**PR:** `#102 — SM0: two-authority seamless handoff lab`  
**Состояние ветки, от которого зафиксирован roadmap:** `8483c40fe23aea31179c3c1189ed1e9099e82386`  
**Назначение:** сохранить дальнейший путь исследований SM0, чтобы текущая двухсерверная лаборатория не превратилась в специальный случай `A <-> B` и чтобы не потерять направление к настоящему N-server seamless world.

> Этот документ является страховочным дополнительным вектором разработки. Он НЕ заменяет основной SM0 plan, V0 critical path, N3-N6 roadmap, control registry или обязательные human/reviewer gates. Любой runtime checkpoint по-прежнему получает отдельный work order, risk classification и acceptance.

Связанные текущие документы:

- [`V0_SM0_TWO_AUTHORITY_SEAMLESS_HANDOFF_LAB_RU.md`](V0_SM0_TWO_AUTHORITY_SEAMLESS_HANDOFF_LAB_RU.md) — исходный two-authority correctness lab;
- [`V0_SM0_AUTOMATED_HANDOFF_TEST_AND_EVIDENCE_RU.md`](V0_SM0_AUTOMATED_HANDOFF_TEST_AND_EVIDENCE_RU.md) — evidence contract;
- [`V0_SM0_P4_PREWARM_FAST_HANDOFF_DESIGN_RU.md`](V0_SM0_P4_PREWARM_FAST_HANDOFF_DESIGN_RU.md) — ближайший fast-handoff design;
- [`DISTRIBUTED_RUNTIME_FOUNDATION_ROADMAP_RU.md`](DISTRIBUTED_RUNTIME_FOUNDATION_ROADMAP_RU.md) — общий путь N3-N6;
- [`../network/SEAMLESS_WORLD_ROADMAP_RU.md`](../network/SEAMLESS_WORLD_ROADMAP_RU.md) — общий seamless-world track;
- [`../network/NETWORK_EXPERIENCE_ROADMAP_NX0_NX9_RU.md`](../network/NETWORK_EXPERIENCE_ROADMAP_NX0_NX9_RU.md) — NX prediction/interpolation/interest track;
- [`../architecture/S0_SPATIAL_SIMULATION_SUBSTRATE_RU.md`](../architecture/S0_SPATIAL_SIMULATION_SUBSTRATE_RU.md) — spatial hierarchy и разделение spatial/authority;
- [`../architecture/MW7_MATTER_INTEREST_REPLICATION_RU.md`](../architecture/MW7_MATTER_INTEREST_REPLICATION_RU.md) — существующий donor для regional projection streams;
- [`../architecture/RL3_REPRESENTATION_AWARE_NETWORK_STREAMING_RU.md`](../architecture/RL3_REPRESENTATION_AWARE_NETWORK_STREAMING_RU.md) — donor для coarse/fine representation streaming.

---

## 1. Где мы сейчас

Легенда:

```text
[DONE]       доказано текущей SM0 лабораторией
[CURRENT]    ближайший активный вектор
[NEXT]       следующий полезный эксперимент
[LATER]      страховочный дальнейший эксперимент
[CONVERGE]   место слияния с общим N3-N6/NX roadmap
```

Текущий путь:

```text
P3   two-authority correctness                     [DONE]
 |
P3.1 controlled WAN latency + matrix              [DONE]
 |     найден stop-and-wait MOVE RTT limit
 |
P4   prewarmed fast handoff                       [CURRENT]
 |     CRITICAL / human gate перед runtime mutation
 |
P5   two players / two authorities / projections  [NEXT]
 |
P6   projection pivot during handoff              [NEXT]
 |
P7   three-authority routing                      [LATER]
 |
P8   nested authority island                      [LATER]
 |
P9   foreign items + interaction routing          [LATER]
 |
P10 multi-authority view composition + LOD        [LATER]
 |
P11 simultaneous crossings + faults + soak        [LATER]
 |
N3/N4/N5/N6 + NX5/NX8 convergence                 [CONVERGE]
```

### Уже доказано

SM0 уже имеет реальную основу, которую нельзя выбрасывать при следующих экспериментах:

```text
2 real authority processes
stable logical_player_id
stable player_entity_id
single active writer
authority epoch fencing
A -> B -> A transfer
real server-to-server control path
replay-safe bounded handoff protocol
controlled WAN shaping
machine-readable evidence
```

P3.1 отдельно показал две разные проблемы, которые нельзя смешивать:

1. **boundary handoff latency** — растёт с WAN latency и является целью P4;
2. **ordinary movement RTT coupling** — текущий SM0 lab client шлёт MOVE в stop-and-wait режиме и должен в дальнейшем сходиться с существующим NX4/NX5 realtime path, а не получать второй отдельный predictor.

---

## 2. Целевая форма SM0 после расширения

SM0 не должен остаться архитектурой:

```text
Server A <-> Server B
```

Целевая экспериментальная форма:

```text
                    Directory / Route Resolver
                    /        |        \
                   A         B         C
                  / \       / \       / \
             local  foreign projections
                  \    \     |     /  /
                       clients
```

Основные свойства:

```text
N authorities, не hard-coded A/B pair
spatial identity != authority identity
client view != one physical server
foreign replica != second canonical object
handoff != despawn/spawn
server links created by current routing/interest need, not full N^2 mesh
```

На первом экспериментальном этапе Directory может оставаться лабораторным и заменяемым. SM0 не объявляет production N3 World Directory принятым.

---

## 3. Принцип N-server topology

Не строить обязательный full mesh всех servers.

Нежелательная форма:

```text
A connected to B,C,D,E...
B connected to A,C,D,E...
...
O(N^2) permanent peer relationships
```

Экспериментальная целевая модель:

```text
Directory знает:
- authority_id
- owned scope/shards
- authority_epoch
- route revision
- health/draining state
- replication/control endpoint

Authority открывает peer relationship только если есть:
- handoff candidate;
- overlapping client interest;
- cross-authority interaction;
- required boundary/projection stream.
```

Таким образом physical server topology может меняться, не меняя identity мира.

---

## 4. Cross-authority projection fabric

Следующий важный слой после handoff — не перенос authority, а возможность **видеть state, authority которого находится на другом сервере**.

Рабочая модель:

```text
Authority A canonical state
        |
        | interest-filtered snapshot/delta
        v
Authority B ForeignReplicaStore
        |
        | normal local client projection
        v
Client connected to B
```

Foreign replica всегда:

```text
READ_ONLY
source_authority_id bound
source_authority_epoch bound
source revision/sequence bound
checksum/hash fenced
never accepted as local canonical mutation target
```

### Два класса projection

#### Dynamic entity projection

Для:

```text
player
NPC
vehicle
loose world item
small dynamic object
```

Типичный поток:

```text
snapshot/delta
+ server tick
+ velocity/movement mode
+ interpolation metadata
```

#### Representation projection

Для:

```text
terrain
large construction
vegetation/population field
large matter region
far world geometry
```

Типичный поток:

```text
regional summary
coarse proxy
simplified representation
fine representation on demand
content-addressed artifact/cache
```

Это сохраняет разделение между canonical simulation state и render representation.

---

## 5. Handoff как смена роли replica

Желаемое seamless поведение:

До crossing:

```text
SERVER A                         SERVER B
P1 CANONICAL  ----------------> P1 FOREIGN GHOST
P2 GHOST      <---------------- P2 CANONICAL
```

После успешного P1 handoff A -> B:

```text
SERVER A                         SERVER B
P1 GHOST      <---------------- P1 CANONICAL
```

Критическая идея:

```text
same player_entity_id
same logical identity
same local presentation identity where possible
CANONICAL -> GHOST on source
GHOST -> CANONICAL on target
```

Не должно требоваться логически удалять P1 и создавать нового P1 только потому, что изменился authoritative server.

---

## 6. Вложенные authority zones

S0 уже допускает spatial hierarchy и `PARENT_CHILD`, но текущие regional authority experiments специально избегают overlapping authority-regions. Поэтому вложенный authority scope должен быть отдельным исследованием, а не неявным расширением двух зон.

Желаемая геометрия:

```text
Authority A owns large surface scope
└── Authority B owns city/island scope inside A
    └── Authority C may own station/complex inside B
```

При этом writable ownership никогда не должен реально перекрываться.

Концептуальная модель:

```text
Spatial scopes may overlap by hierarchy.
Effective writable authority scopes may not overlap.
```

Первичная гипотеза routing rule:

```text
resolve all matching active hierarchical leases
-> select most-specific valid lease
-> fence by topology_revision + lease_revision + authority_epoch
```

Это пока гипотеза для P8, НЕ утверждённый production contract.

Parent authority должен трактовать descendant-owned scope как исключённый из своего effective writable set.

---

## 7. Экспериментальная лестница

### P4 — Prewarmed Fast Handoff — **[CURRENT]**

Цель:

- убрать один PREPARE RTT из crossing critical path;
- prewarm target до crossing;
- сохранить source единственным writer до реального commit;
- использовать final immutable crossing state в fast commit;
- сохранить legacy PREPARE/PREPARED/COMMIT fallback.

Важно:

```text
risk = CRITICAL
runtime mutation only after explicit human gate/work order
independent review mandatory
```

P4 решает **authority transition latency**, но не должен создавать новый custom movement prediction stack.

### P5 — Two Players / Two Authorities / Foreign Player Projection — **[NEXT]**

Лаборатория:

```text
Authority A owns P1
Authority B owns P2
Client 1 active on A
Client 2 active on B
```

Доказать:

- оба игрока движутся одновременно;
- Client 1 видит P2, хотя P2 canonical на B;
- Client 2 видит P1, хотя P1 canonical на A;
- foreign player state read-only;
- remote interpolation использует общий NX5-style path, не новый SM0-only renderer;
- inventory identity каждого игрока не смешивается.

Это первый эксперимент, где server-to-server projection нужен даже **без handoff**.

### P6 — Projection Pivot During Handoff — **[NEXT]**

P1 идёт A -> B при активной foreign projection.

Доказать:

```text
B already has P1 ghost before commit
commit happens once
B ghost -> canonical
A canonical -> ghost
both clients continue seeing same P1 identity
no duplicate presentation/entity identity
no frame where both A and B can mutate P1
```

После crossing новый active server B продолжает получать A-owned projections, если они остаются в interest volume игрока.

### P7 — Three-Authority Route Lab — **[LATER]**

Топология:

```text
A | B | C
```

P1 проходит:

```text
A -> B -> C -> B -> A
```

Цель — уничтожить любые hidden assumptions:

```text
peer == the other server
source is always A/B
ports are fixed pair
zone lookup is binary
warm route count is permanently 1 by architecture
```

Route должен разрешаться через topology/directory data.

На этом этапе допустимо иметь только bounded number of warm/projection peer links вокруг текущего interest region.

### P8 — Nested Authority Island — **[LATER]**

Топология:

```text
A large parent scope
└── B closed child scope
    └── optional C nested child
```

Проверить:

- вход в child со всех допустимых сторон;
- выход обратно в parent;
- route chooses child only inside effective child scope;
- parent cannot mutate child-owned objects;
- stale topology revision fails closed;
- child unavailable does not silently give parent write authority;
- optional fallback semantics формализуются отдельно, а не возникают автоматически.

### P9 — Foreign World Items + Interaction Routing — **[LATER]**

Добавить world items/containers на разных authorities.

До взаимодействия:

```text
B-owned item visible on A as foreign replica
A-owned item visible on B as foreign replica
```

Mutation foreign replica запрещена.

Исследовать два command routes:

```text
1. Client -> active authority -> owner authority forwarding
2. Client receives owner route/ticket -> direct authoritative command
```

Для первого bounded experiment предпочтителен server-mediated forwarding, чтобы client composition не становилась owner-topology-aware раньше необходимости.

Затем проверить physical item authority handoff отдельно от player handoff.

Player-owned inventory продолжает использовать существующий Item Graph truth и не превращается в отдельный SM0 inventory store.

### P10 — Multi-Authority View Composition + Representation LOD — **[LATER]**

Active authority становится view composer для клиента:

```text
client interest volume
  -> local authoritative projections
  -> foreign entity projections from A/B/C
  -> coarse/fine representation streams
  -> one ClientReplicaStore/presentation world
```

Проверить:

- одновременно 3 projection sources;
- per-source sequence/hash fencing;
- source dropout removes/degrades only affected projection;
- bandwidth budget;
- distance/priority tiers;
- progressive representation loading;
- cache reuse;
- no canonical state generated from presentation artifact.

Здесь надо максимально переиспользовать идеи NX8, MW7 и RL3.

### P11 — Simultaneous Crossings / Faults / Soak — **[LATER]**

Сценарии:

```text
P1 A -> B while P2 B -> A
P1 A -> B while P2 B -> C
projection source disconnect
projection delta delay/reorder
handoff target restart
nested child authority unavailable
stale directory/topology revision
stale ghost receives attempted interaction
duplicate fast commit
client reconnect during projection pivot
```

Hard invariants:

```text
one active writer per aggregate
identity stable
no authority epoch rollback
foreign replica never accepts canonical mutation
no duplicate item/player IDs
projection loss cannot create ownership
fault on one peer does not freeze unrelated authority/client
```

После focused scenarios — repeated crossings + multi-client soak.

---

## 8. Связь с основным roadmap

Этот SM0 vector не создаёт параллельную production architecture. Он должен быть semantic/prototype donor для уже существующих checkpoints:

```text
SM0 P7/P8 topology experiments
        -> N3 World Directory

SM0 P9 generic object transfer
        -> N4 Generic Object Handoff

SM0 P4/P6 player transition
        -> N5 Seamless Player Handoff

SM0 P5/P6/P10 foreign projections
        -> N6 Ghosts + Interest Management

SM0 movement presentation convergence
        -> NX4/NX5

SM0 projection filtering/budgets
        -> NX8

SM0 regional projection semantics
        <- MW7 semantic donor

SM0 representation streaming
        <- RL3 semantic donor
```

Если SM0 experiment начинает дублировать уже существующий accepted subsystem, он должен остановиться и перейти на integration/reuse, а не продолжать второй stack.

---

## 9. Что намеренно НЕ решаем этой схемой

До отдельного gate не объявлять решёнными:

```text
production World Directory
consensus/RAFT
production NATS/JetStream requirement
dynamic automatic load balancing
dynamic region split/merge
cross-server Construction transaction
general distributed transaction across arbitrary authorities
planet-scale interest budgeting
production security/trust between authorities
Kubernetes/Agones deployment
```

SM0 остаётся controlled laboratory.

---

## 10. Текущий визуальный ориентир для разработчика

При открытии этого документа путь должен читаться так:

```text
DONE
  P3 correctness
  P3.1 WAN measurement

YOU ARE HERE
  P4 prewarmed fast handoff

NEXT EXPERIMENTAL PROOF
  P5 two players on different authorities + mutual foreign projections
  P6 ghost/canonical role pivot during handoff

PROVE N-SERVER, NOT A/B SPECIAL CASE
  P7 three authorities
  P8 nested authority scope

EXPAND WORLD CONTINUITY
  P9 foreign items + interaction routing
  P10 multi-authority view composition + representation LOD

HARDEN
  P11 simultaneous crossings + faults + soak

CONVERGE
  N3 -> N4 -> N5 -> N6
  NX4/NX5/NX8 reuse
```

### Ближайший практический путь

```text
P4 fast handoff
  -> independent evidence/review
  -> P5 two-player/two-authority projection lab
  -> P6 projection pivot
```

Именно эти три шага сейчас считаются ближайшей экспериментальной дорожкой. P7-P11 зафиксированы, чтобы не потерять дальнейшую архитектурную цель, но не являются автоматическим разрешением на runtime implementation.

---

## 11. Неподвижные инварианты всего вектора

1. Один canonical aggregate — один active authoritative writer.
2. Foreign projection всегда read-only.
3. Spatial identity не содержит authority owner.
4. Handoff не меняет logical/entity identity.
5. Authority epoch и topology/route revisions не откатываются.
6. Presentation/LOD artifact не становится canonical state.
7. Client не должен знать физическую topology всего cluster.
8. Server-to-server links создаются по routing/interest need, а не обязательным full mesh.
9. Nested spatial scopes допустимы только при формально непересекающемся effective writable authority.
10. SM0 не создаёт второй prediction, Item Graph, replication или representation stack там, где уже существует общий accepted foundation.
11. Любой CRITICAL authority runtime change проходит human gate и независимый exact-head review.
12. Этот roadmap хранит направление исследования, но не является self-acceptance какого-либо N3-N6 checkpoint.
