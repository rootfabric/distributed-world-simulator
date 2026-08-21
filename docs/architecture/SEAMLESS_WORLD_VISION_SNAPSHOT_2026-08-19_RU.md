# Seamless World — срез архитектурного видения на 2026-08-19

Status: `INFORMATIONAL PROJECT SNAPSHOT — DURABLE MEMORY — NOT CANONICAL ACTIVATION`

Дата среза: `2026-08-19`  
Наблюдаемый `main` перед фиксацией среза: `785898c14a75071dfec2ca1a170a369c44339180`  
Текущая research-линия архитектуры на момент среза: `research/seamless-world-architecture-r1`  
Research PR: `#137 — Research: seamless world R2 + pre-P6 incubation train`  
Наблюдаемый exact architecture candidate HEAD: `693043c3be2bc7c7cb0c728b87b88d6018899d6b`  
SM0 evidence donor: `feature/sm0-two-authority-seamless-handoff-lab`, PR `#102`

---

## 0. Назначение этого документа

Этот файл — **срез текущего понимания и направления проекта**, сохранённый в `main` как долговечная память.

Он нужен для того, чтобы через недели или месяцы можно было быстро восстановить:

- зачем строится бесшовная распределённая сеть;
- какие архитектурные идеи считаются наиболее перспективными сейчас;
- что уже доказал SM0;
- что является следующим поколением архитектуры R2;
- в каком порядке предполагается реализовывать систему;
- какие ошибки проект сознательно пытается не допустить;
- какие части в будущем могут стать отдельным reusable network/seamless framework.

Это **не frozen specification**, не checkpoint acceptance, не activation record и не замена текущему control state.

Архитектура, названия, этапы, transport, storage technology, API и конкретные реализации могут меняться по мере появления новых экспериментов и evidence.

Если этот срез расходится с более новым canonical state, приоритет всегда у:

```text
PROJECT_CONTROL.md
HARNESS_CONTROL.md
config/control/project-program-registry.v1.json
config/control/harness/project-goals.v1.json
config/control/harness/checkpoint-catalog.v1.json
current main-owned architecture/control pointers
fresh exact-head accepted/reviewed evidence
```

Главное правило чтения:

```text
THIS FILE EXPLAINS THE VISION AT ONE POINT IN TIME.
IT DOES NOT AUTHORIZE FUTURE RUNTIME WORK BY ITSELF.
```

---

# 1. Общая цель

Целевой результат — persistent seamless distributed world, в котором один логический мир может исполняться на нескольких authority-процессах без видимых для игрока серверных границ и без появления нескольких канонических истин.

Желаемый пользовательский эффект:

```text
игрок движется по миру
       |
       v
внутренняя authority может A -> B -> C
       |
       v
игрок не переподключается вручную
PlayerId не меняется
ItemId не меняются
инвентарь не дублируется
объекты вокруг не исчезают из-за серверной границы
ввод продолжается
операции остаются exactly-once
```

Архитектурный north star проекта остаётся совместим с общей целью DWS:

```text
persistent seamless distributed world simulator
without duplicate truth layers
```

Бесшовность здесь означает не только красивую картинку. Она должна одновременно сохранять:

```text
AUTHORITY_CORRECTNESS
STATE_CONTINUITY
TRANSPORT_CONTINUITY
VISUAL_CONTINUITY
```

---

# 2. Что уже дал SM0

Долгоживущая ветка:

```text
feature/sm0-two-authority-seamless-handoff-lab
```

должна рассматриваться как **evidence donor**, а не как будущая production база.

На runtime carrier SM0 были доказаны важные примитивы:

- стабильная logical/player identity при authority handoff;
- один активный writer;
- monotonic authority epoch fencing;
- replay-safe handoff state machine;
- freeze / prepare / retire / activate механика;
- moving nested authority/reference-frame continuity;
- foreign item interaction через authority boundary без второго Item Graph;
- multi-authority presentation composition;
- representation LOD;
- deterministic fault injection;
- process-isolated authority tests;
- repeated simultaneous crossings и soak.

SM0 принципиально **не доказал**:

- production Ownership Directory;
- arbitrary-N authority deployment;
- production WAN seamlessness;
- production gateway fabric;
- dynamic split/merge;
- dynamic load balancing;
- arbitrary distributed physics;
- complete cross-authority transaction model;
- production-ready reusable framework extraction.

Поэтому правильная стратегия:

```text
SM0
  = proven mechanisms + tests + failure lessons

SM1/R2
  = new production architecture using SM0 as donor
```

Нельзя просто продолжать старую SM0 branch lineage как production truth.

---

# 3. Главное изменение мышления после SM0

Первоначальная задача могла выглядеть как:

```text
Player moves from Server A to Server B
```

Текущая архитектура рассматривает проблему шире:

```text
one logical world
    |
    +-- stable identity
    +-- canonical ownership
    +-- ownership migration
    +-- carried canonical state
    +-- physical interaction locality
    +-- client ingress routing
    +-- projection / AOI
    +-- cross-owner operations
    +-- recovery / fencing
    +-- temporal continuity
    +-- static N-authority composition
    +-- later dynamic placement
```

Это переход от "handoff demo" к foundation для настоящего distributed world runtime.

---

# 4. Пять разных архитектурных понятий

Ключевая идея R2 — не смешивать разные вопросы в один `region/server` объект.

```text
WHERE IS IT?
    Spatial Cell / Spatial Address

WHO MAY WRITE?
    Canonical Authority / OwnershipRecord

WHAT STATE MIGRATES AS ONE OWNERSHIP UNIT?
    AuthorityDomain

WHAT MUST BE SIMULATED TOGETHER?
    InteractionIsland

HOW DOES A CLIENT ENTER THE WORLD?
    Edge Gateway
```

Следовательно:

```text
SpatialCellId
!= AuthorityId
!= AuthorityDomainId
!= InteractionIslandId
!= GatewayId
```

Это одно из центральных решений текущего видения.

Сервер не должен быть идентичностью объекта, spatial cell не должен автоматически быть ownership domain, а gateway не должен становиться authority.

---

# 5. Ownership Directory — canonical ownership oracle

Production multi-authority runtime должен иметь один логически canonical ownership oracle.

Концептуально:

```text
OwnershipRecord {
    subject_or_domain_id
    owner_authority_id
    authority_epoch
    fencing_token
    directory_generation
    authority_incarnation
    state_revision
    lease_state
    route_revision
}
```

Ключевая операция:

```text
CAS(
  expected owner / epoch / fence,
  desired owner / epoch / fence
)
```

Именно успешный Directory CAS является ownership linearization point.

Не локальный флаг сервера.
Не gateway route.
Не факт получения prepared snapshot.
Не client belief.

Главный fail-closed invariant:

```text
Directory committed B @ N+1

=> A @ N can never become canonical writer again
   without a new valid fenced ownership transition
```

Критический сценарий:

```text
A owns Domain D @ epoch 10 / fence 100
A partitions
Directory commits B @ 11 / 101
A restarts from old durable state
A attempts canonical mutation
=> FENCED
```

Это должно проверяться как глобальный invariant, а не только внутри Directory implementation.

---

# 6. AuthorityDomain — единица ownership migration

Одна из главных R2 идей:

```text
AuthorityDomain
```

— bounded closure canonical state, который меняет writer ownership как одна единица.

Это не обязательно одна entity и не обязательно physics island.

Первый обязательный production use case:

```text
PlayerAuthorityDomain player/42
│
├── Player aggregate
├── Inventory root
├── Hotbar
├── Equipment
├── Backpack
│   └── Container
│       ├── Ore stack
│       ├── Battery
│       └── Device
├── carried Item Graph subtree
└── domain operation/timeline metadata
```

Почему это нужно:

плохая модель:

```text
Player -> B
Item1 -> B CAS
Item2 -> B CAS
Item3 -> B CAS
...
```

целевая модель:

```text
PlayerAuthorityDomain A -> B
```

и обычные carried descendants наследуют authority.

Scaling invariant:

```text
1 item     -> 1 domain ownership transition
10 items   -> 1 domain ownership transition
100 items  -> 1 domain ownership transition
1000 items -> 1 domain ownership transition
```

Serialized state может расти с количеством содержимого, но ownership transition count не должен становиться O(items).

---

# 7. AuthorityBinding

Subject связывается с ownership domain явно:

```text
AuthorityBinding {
    subject_id
    authority_domain_id
    binding_generation
    mode = INHERIT | EXPLICIT
    binding_revision
}
```

Обычный carried state:

```text
INHERIT
```

Самостоятельно owned subject при необходимости:

```text
EXPLICIT
```

Canonical mutation должна проверять:

```text
current binding_generation
current domain owner
current authority_epoch
current fencing_token
```

Stale binding не должен позволять mutation даже если stale process локально считает объект своим.

---

# 8. Item Graph остаётся единственной structural truth

Seamless runtime не должен создавать второй inventory/container graph.

Правило:

```text
Item Graph
    = canonical item/container relationships

Seamless runtime
    = authority / routing / migration metadata
```

Pickup означает одновременно изменение:

```text
Item Graph membership
+
AuthorityBinding
```

Пример:

```text
до pickup:
Item X -> WORLD graph
Binding -> WorldDomain/A

после pickup:
Item X -> PlayerInventory/42
Binding -> PlayerAuthorityDomain/42
```

Недопустимы промежуточные accepted состояния:

```text
Graph says PLAYER, binding says WORLD

или

Graph says WORLD, binding says PLAYER
```

Drop выполняет обратный rebind к canonical WorldDomain текущего мира.

Stable `ItemId` сохраняется.

---

# 9. DomainMutationBarrier — точная граница handoff

Handoff должен иметь deterministic state cut.

Концептуально:

```text
DomainMutationBarrier {
    authority_domain_id
    domain_revision
    last_committed_operation_sequence
    freeze_generation
    timeline_stamp
}
```

Barrier отвечает на вопрос:

> какие gameplay mutations уже принадлежат переносимому state, а какие должны выполняться после transfer?

Операции, которые обязательно надо гонять в race matrix:

- pickup;
- drop;
- stack split;
- stack merge;
- container move;
- equip;
- unequip;
- mount/unmount;
- item use;
- relevant player-state mutations.

Каждая операция должна закончить ровно в одном состоянии:

```text
INCLUDED BEFORE BARRIER
or
QUEUED / RETRIED AFTER BARRIER
or
EXPLICITLY REJECTED
```

Недопустимо:

```text
lost
committed twice
acknowledged but absent
silently committed only on stale source
```

---

# 10. Production AuthorityDomain handoff

Целевой transfer flow:

```text
SOURCE ACTIVE
      |
      v
TARGET COMPATIBILITY CHECK
      |
      v
TARGET WARM
      |
      v
SOURCE DOMAIN FROZEN
      |
      v
TARGET DURABLY PREPARED SHADOW
      |
      v
DIRECTORY CAS COMMIT
      |        ^
      |        |
      |   ownership linearization point
      v
TARGET ACTIVE
      |
      v
SOURCE READ_ONLY / RETIRED
```

Rollback rule:

```text
BEFORE DIRECTORY_COMMITTED
    rollback/cancel may restore source progress

AFTER DIRECTORY_COMMITTED
    old source may never locally roll itself back into writer state
```

Если target падает после Directory commit:

```text
recover committed target
or
forward-transfer with a new fenced transition
or
fail closed
```

Но не:

```text
"B did not activate, therefore A becomes writer again"
```

---

# 11. Temporal continuity

Authority process migration не должна означать запуск simulation timeline заново.

Концептуально:

```text
AuthorityTimelineStamp {
    timeline_epoch
    simulation_tick
    state_revision
}
```

Точная clock implementation ещё может меняться, но invariant должен сохраниться:

```text
accepted canonical/presentation timeline never rolls back
because authority process changed
```

Это важно для:

- client prediction;
- reconciliation;
- interpolation;
- projectiles;
- timed interactions;
- moving reference frames;
- observer projection ordering;
- visible rewind/correction metrics.

---

# 12. Edge Gateway — ingress, но не owner

Gateway должен быть non-authoritative.

Базовая topology:

```text
Client -> Edge Gateway -> Authority
```

Gateway может владеть:

- connection/session transport state;
- route cache;
- PRIMARY/OBSERVER/WARM routing roles;
- interest aggregation;
- retries/resume transport logic;
- gateway selection/rehome logic.

Gateway не может владеть canonical gameplay truth.

Правило:

```text
Gateway role != ownership grant
```

`PRIMARY`, `OBSERVER`, `WARM`, `DEGRADED`, `DRAINING` — routing/session roles.

Canonical owner определяется Directory/fencing model.

---

# 13. Три разные миграции нельзя смешивать

Текущий дизайн сознательно различает:

### Spatial movement

```text
SpatialCell 10 -> SpatialCell 11
```

### Authority migration

```text
PlayerAuthorityDomain A -> B
```

### Gateway mobility

```text
Client path G1 -> G2
```

Они могут происходить независимо.

Например:

```text
client uses Gateway EU
player domain owned by Authority US-B
```

может быть корректным состоянием.

Gateway change не должен автоматически менять gameplay authority.

Spatial boundary crossing не должен автоматически означать ownership transfer, если placement policy этого не требует.

---

# 14. Gateway mobility

Gateway rehome должен поддерживать как минимум:

```text
FAILURE_DRIVEN
QUALITY_DRIVEN
```

Quality signals могут включать:

- RTT;
- jitter;
- loss;
- health;
- load;
- hysteresis;
- cooldown.

Required invariants:

```text
PlayerEntityId unchanged
logical ClientSessionId stable/resumable
OperationId survives path change
canonical authority unchanged unless separate authority protocol changes it
old route cache has no ownership power
```

Temporary dual-path retry не должен создавать duplicate commit.

---

# 15. Projection / AOI

После того как ownership correctness надёжен, клиент может видеть state от нескольких authorities.

Пример:

```text
Client/Gateway
  PRIMARY  -> Authority A
  OBSERVER -> Authority B
  OBSERVER -> Authority C
```

Projection должна быть:

```text
read-only
versioned
fenced by epoch/revision
allowed to become stale/degraded
never canonical owner
```

Projection не должна материализовать второй Item Graph.

Observer loss не должен превращать observer в writer.

Prepared target projection до Directory commit не должна делать target PRIMARY owner.

---

# 16. Cross-authority operations

Первый bounded pattern:

```text
Player@A -> Item@B
```

Целевой алгоритм:

```text
resolve canonical owner
       |
       v
owner = B / epoch N / revision R
       |
       v
send operation {
  OperationId
  expected owner B
  expected epoch N
  expected revision/binding
}
       |
       v
B validates and commits
```

Если ownership уже стал:

```text
B -> C
```

то stale operation должна fail closed, затем caller выполняет explicit re-resolve/retry policy с тем же end-to-end `OperationId`.

Не должно быть default стратегии:

```text
broadcast operation to all servers
```

---

# 17. InteractionIsland — физическая co-simulation closure

`InteractionIsland` не равен `AuthorityDomain`.

Пример:

```text
InteractionIsland ship/17
├── ship hull
├── pilot physical body
├── passengers
├── mounted component
└── bounded attached physics cargo
```

Назначение:

```text
AuthorityDomain
    = ownership / migration closure

InteractionIsland
    = co-simulation / placement constraint
```

Это предотвращает ошибку, когда обычный inventory graph начинают трактовать как physics cluster или наоборот.

InteractionIsland планируется доказывать после базового authority/gateway/AOI/cross-owner foundation, а не раньше.

---

# 18. Static-first стратегия

Проект сознательно не начинает с dynamic server meshing.

Сначала должен быть доказан static N-authority world.

Текущий production roadmap R2:

```text
SM1-H0   Production seamless contracts
SM1-H1   Durable Ownership Directory
SM1-H2   Generic AuthorityDomain transfer
SM1-H2A  AuthorityBinding + Domain Closure
SM1-H2B  Player Carrying Domain Lab
SM1-H3   Single Edge Gateway transparency
SM1-H4   PRIMARY / OBSERVER multi-authority gateway
SM1-H5   Gateway-mediated PlayerAuthorityDomain handoff
SM1-H6   Multi-region gateway selection
SM1-H7   Gateway mobility / rehome / failure
SM1-H8   Production projection / AOI / interest aggregation
SM1-H9   Cross-authority operation foundation
SM1-H10  Physical InteractionIsland runtime
SM1-H11  Static N-authority world
SM1-H12  Integrated static seamless-world acceptance
```

Только после H12:

```text
SM-D1 Dynamic AuthorityDomain placement
SM-D2 Dynamic split / merge
SM-D3 Interaction-aware dynamic meshing
```

Это важный архитектурный предохранитель.

Нельзя одновременно изобретать:

- ownership;
- transfer;
- recovery;
- gateways;
- AOI;
- load balancing;
- split/merge;
- distributed physics.

Static correctness должна существовать до dynamic placement.

---

# 19. Pre-P6 incubation

Production SM1 не должен обходить последовательный V0/P product train.

Поэтому текущее видение использует отдельный research incubation train.

```text
I0 Architecture closure
I1 Seamless research harness / global oracles
I2 Ownership Directory prototype
I3 Generic AuthorityDomain transfer prototype
I4 Player Carrying Domain lab
I5 Edge Gateway incubation
I6 Projection/AOI + bounded cross-owner operations
I7 Fault/WAN/soak rehearsal
I8 Production port plan + Work Order pack
```

Главный принцип:

```text
INCUBATION OUTPUT = DONOR
INCUBATION LINEAGE != FUTURE PRODUCTION LINEAGE
```

Research может заранее ответить на сложные инженерные вопросы, но не может:

- стать canonical V0 owner;
- подменить P5/P6 acceptance;
- автоматически активировать SM1;
- менять production mutation lease;
- объявлять research PASS production checkpoint PASS;
- wholesale-merge research history в production;
- активировать dynamic meshing.

---

# 20. Product train и точка входа SM1

На момент этого среза P4 уже является accepted predecessor, а P5 runtime train запущен на exact accepted P4 product lineage.

Наблюдаемый P5 context:

```text
feature/v0-p5-equipment-tools
PR #145
HIGH-RISK RUNTIME IN PROGRESS
```

Этот operational факт быстро меняется и **не должен обновляться в этом snapshot вручную**.

Актуальное состояние P5/P6 всегда читать из `main` control state и live PR/evidence.

Production SM1 должен появиться только после:

```text
P5 accepted
   |
   v
P6 accepted
   |
   v
main-owned post-P6 seamless decision
   |
   +-- DEFER
   |
   +-- ACTIVATE_V0_SM1
             |
             v
       exact accepted successor base
             |
       fresh SM1 epoch
             |
       fresh Work Order
             |
       runtime mutation lease rotation
             |
       Director dispatch
```

Research/SM0 branch history не является production base.

---

# 21. Текущий immediate blocker research-линии

PR #137 имеет implementer self-audit finding:

```text
R2-SA-001
```

Суть:

machine roadmap использует формулировку:

```text
required_before_first_runtime_work
```

в то время как pre-P6 incubation разрешает donor-only semantic research runtime после architecture review, ещё до production SM1 activation.

Поэтому machine contract должен однозначно различать как минимум:

```text
production runtime activation gates
vs
research incubation semantic runtime gates
```

Предпочтительное направление repair:

```text
required_before_first_production_runtime_work
```

и отдельный explicit incubation gate/reference.

До fresh independent review/adjudication:

```text
I1 harness scaffolding = allowed
I2+ semantic runtime   = blocked
```

Этот blocker сам является историческим фактом среза и может быть закрыт позже.

---

# 22. Как должен выглядеть I1 Seamless Harness

Нужно один раз построить общий deterministic test environment для всех следующих этапов.

Процессы:

```text
Scenario Coordinator
        |
        +-- Directory
        +-- Gateway 1..N
        +-- Authority 1..N
        +-- Client 1..N
        +-- Network/Fault Controller
        +-- Global Evidence Analyzer
```

Раздельные link profiles:

```text
Client <-> Gateway
Gateway <-> Directory
Gateway <-> Authority
Authority <-> Directory
Authority <-> Authority
```

Fault/network controls:

- latency;
- jitter;
- loss;
- duplicate;
- reorder;
- bandwidth;
- queue pressure;
- lag spike;
- disconnect;
- partition;
- hard process crash;
- restart;
- authority incarnation change.

Seeded run должен быть reproducible.

---

# 23. Global Oracles

Вместо множества локальных "кажется PASS" вся seamless-линия должна использовать общие invariants.

Минимум:

```text
writer_violations == 0
identity_changes_due_to_topology == 0
stale_owner_mutations_accepted == 0
duplicate_canonical_commits == 0
projection_canonical_writes == 0
unexpected_revision_rollback == 0
```

Дополнительно по соответствующим checkpoint:

```text
duplicate_item_ids == 0
lost_item_ids == 0
unexpected_session_resets == 0
binding_generation_violations == 0
canonical_timeline_rollbacks == 0
```

Global analyzer должен агрегировать события из **реальных отдельных процессов**, иначе split-brain bug может остаться невидимым локальному тесту одного authority.

---

# 24. Отдельные измерения seamlessness

Correctness и визуальная гладкость нельзя смешивать в один PASS.

Каждый крупный checkpoint должен по возможности отдельно выдавать:

```text
AUTHORITY_CORRECTNESS
STATE_CONTINUITY
TRANSPORT_CONTINUITY
VISUAL_CONTINUITY
```

Метрики:

```text
handoff_total_ms
canonical_write_gap_ms
movement_input_gap_ms
inventory_operation_gap_ms
projection_gap_ms
visual_gap_frames
max_prediction_error
hard_correction_count
client_disconnect_count
client_session_change_count
gateway_rehome_count
gateway_route_flip_count
duplicate_entity_count
duplicate_item_count
stale_owner_mutations_accepted
duplicate_canonical_commits
```

Можно иметь authority PASS и visual FAIL.

Visual smoothing никогда не исправляет authority FAIL.

---

# 25. Canonical integrated journey

Настоящий static seamless-world acceptance должен быть одним длинным user-visible journey, а не только набором disconnected unit tests.

Целевой сценарий:

```text
Client -> Gateway G1

connect
move on Authority A
pickup Item X
place X into nested inventory
use X

Authority B becomes WARM/OBSERVER
PlayerAuthorityDomain A -> B

continue movement
use X immediately on B
foreign projections from A/C remain visible

G1 fails or becomes materially worse
session rehomes G1 -> G2
Authority B remains canonical owner

perform one cross-authority operation

drop X
X becomes WorldDomain/B item

B crashes/restarts under fencing/recovery rules

continue session
```

Запускать под controlled:

```text
latency
jitter
loss
reorder
fault injection
```

Final correctness counters должны оставаться нулевыми для split-brain/duplication/stale writes/revision rollback.

---

# 26. Дополнительные design principles, которые желательно сохранить

Ниже не frozen contracts, а architectural guidance, которую текущий анализ считает полезной для будущей реализации.

## 26.1 Directory API должен быть storage-independent

Не связывать ownership semantics заранее с конкретной технологией:

```text
Postgres / etcd / Consul / Redis / NATS / custom store
```

Сначала contract и deterministic reference implementation.

Storage можно заменить, если semantic guarantees остаются теми же.

## 26.2 Fencing должен проверяться на canonical mutation path

Недостаточно, чтобы только Directory знал текущего owner.

Mutation envelope должен позволять проверить текущие:

```text
AuthorityDomainId
AuthorityEpoch
FencingToken
OperationId
DomainRevision / expected revision
binding generation where relevant
```

## 26.3 Transfer protocol должен допускать evolution от full snapshot к delta

На раннем этапе допустим:

```text
full snapshot
```

Но boundary желательно строить так, чтобы позже поддержать:

```text
base snapshot
+
delta log
+
final barrier delta
```

Иначе большие inventory/vehicle/domain state будут делать handoff слишком дорогим.

## 26.4 Control plane и data plane следует разводить

Conceptual split:

```text
CONTROL PLANE
Directory
ownership CAS
leases
placement
compatibility
route metadata
health

DATA PLANE
input
snapshots
state deltas
projections
gameplay operations
```

Это не обязательно разные процессы на первом этапе, но API ownership должен оставаться разделённым.

## 26.5 Backpressure — часть production architecture

Позже потребуются explicit policies для:

```text
per-link queues
queue limits
priority
deadline/drop rules
congestion metrics
interest degradation
projection quality downgrade
```

Особенно для gateway/AOI/projection traffic.

## 26.6 Transport independence

Authority semantics, Directory semantics, transfer state machine и routing rules не должны быть жёстко привязаны к конкретному Godot transport.

Желаемый layering:

```text
protocol / semantic contracts
        |
transport abstraction
        |
Godot adapter(s)
```

Это позволит позже выделить mature seamless/network runtime в отдельный reusable framework без переписывания core semantics.

---

# 27. Framework-ready, но не framework extraction сейчас

Долгосрочное направление — сделать сетевую/бесшовную часть пригодной для использования и другими проектами.

Но текущая стратегия:

```text
DO NOT EXTRACT TOO EARLY
```

Сначала нужно доказать mature semantics внутри реального simulator use case:

- canonical items;
- nested inventory;
- reconnect;
- moving reference frames;
- cross-owner operations;
- failures;
- N-authority topology;
- WAN-like conditions.

Поэтому сейчас следует:

```text
preserve module boundaries
preserve transport independence
avoid simulator-specific assumptions in protocol core
keep adapters explicit
keep tests reusable
```

но не объявлять SM0/ранний SM1 готовым standalone framework.

Framework extraction — отдельный будущий architecture/product decision после достаточной зрелости.

---

# 28. Рекомендуемая research branching model

После architecture review рекомендуется не одна mega-branch, а последовательность небольших donor branches:

```text
research/sm1-i0-contracts
research/sm1-i1-harness
research/sm1-i2-directory
research/sm1-i3-domain-transfer
research/sm1-i4-player-carrying-domain
research/sm1-i5-edge-gateway
research/sm1-i6-projection-cross-owner
research/sm1-i7-fault-soak
research/sm1-i8-production-port-plan
```

Каждая должна явно сообщать:

```text
RESEARCH_ONLY=true
PRODUCTION_ACTIVATION=false
CANONICAL_OWNER_MUTATION=false
DONOR_ONLY=true
```

При production activation нужные contracts/algorithms/tests переносятся намеренно на exact accepted production base.

---

# 29. Практический порядок реализации от текущей точки

На момент среза наиболее логичный execution sequence такой:

```text
1. Fresh independent review PR #137 exact HEAD
2. Adjudicate / repair R2-SA-001
3. Freeze incubation contract vocabulary
4. Build I1 multi-process research harness
5. Build global evidence/oracle analyzer
6. I2 Ownership Directory prototype
7. Prove stale-writer fencing under crash/restart/partition
8. I3 generic AuthorityDomain transfer
9. Crash every named transfer phase
10. I4 real Player Carrying Domain
11. Race handoff with inventory/equipment/item operations
12. I5 Edge Gateway transparency + PRIMARY/OBSERVER/WARM
13. Gateway failure/quality rehome
14. I6 projection/AOI + one bounded cross-owner operation
15. I7 multi-process fault/WAN/soak rehearsal
16. I8 production port map + Work Orders
17. Wait for canonical post-P6 ACTIVATE_V0_SM1 decision
18. Start fresh production SM1 from exact main-declared accepted base
19. Execute H0 -> H12 static seamless roadmap
20. Only then consider D1/D2/D3 dynamic meshing
```

---

# 30. Что нельзя потерять при будущих пересмотрах

Даже если конкретная архитектура R2 изменится, следующие lessons считаются особенно ценными и должны быть пересмотрены осознанно, а не исчезнуть случайно:

1. **Stable identity не зависит от process/server identity.**
2. **Canonical writer должен быть один.**
3. **Ownership transition имеет один linearization point.**
4. **Stale writer должен быть fenced после restart.**
5. **Gateway не является gameplay authority.**
6. **Projection не является canonical truth.**
7. **Item Graph нельзя дублировать seamless subsystem-ом.**
8. **Player переносится вместе с реальным carried-state closure, а не как naked entity.**
9. **Inventory size не должен давать один ownership CAS на каждый carried item.**
10. **Handoff должен иметь deterministic mutation barrier.**
11. **Temporal continuity является частью state continuity.**
12. **Gateway mobility и authority migration — разные процессы.**
13. **Spatial partition и ownership partition — разные модели.**
14. **InteractionIsland и AuthorityDomain — разные closure.**
15. **Static N-authority correctness предшествует dynamic meshing.**
16. **OperationId должен жить end-to-end через retries/routes/gateways.**
17. **Correctness и visual smoothness должны измеряться отдельно.**
18. **Research evidence — donor, а не автоматическая production lineage.**
19. **Transport/storage implementations должны оставаться replaceable там, где это возможно.**
20. **Архитектура должна проверяться adversarial fault tests, а не только happy path.**

---

# 31. Как использовать этот срез позже

Если новый разработчик/агент открывает проект спустя длительное время:

```text
1. Прочитать PROJECT_CONTROL.md
2. Прочитать current registry/goals/checkpoints
3. Определить текущий seamless CURRENT pointer / active branch
4. Найти свежие PR/review/evidence
5. Затем прочитать этот snapshot
```

Этот файл отвечает на вопрос:

> "какое целостное видение бесшовного мира было у проекта 19 августа 2026 года и почему оно было таким?"

Он **не** отвечает авторитетно на вопрос:

> "что разрешено реализовывать прямо сейчас?"

Для второго вопроса всегда использовать актуальный main-owned control state.

---

# 32. Источники среза

Основные материалы, из которых сформировано это видение:

```text
SM0 evidence:
  feature/sm0-two-authority-seamless-handoff-lab
  PR #102

Current research architecture at snapshot time:
  research/seamless-world-architecture-r1
  PR #137

Key R2 documents on research branch:
  docs/architecture/SEAMLESS_WORLD_CURRENT_RU.md
  docs/architecture/SEAMLESS_WORLD_ARCHITECTURE_R2_RU.md
  docs/architecture/SEAMLESS_WORLD_R2_DECISION_RECORD_RU.md
  docs/plans/SEAMLESS_WORLD_SM1_ROADMAP_R2_RU.md
  docs/plans/seamless-world-sm1-roadmap.v2.json
  docs/testing/SEAMLESS_WORLD_VALIDATION_STRATEGY_R2_RU.md
  docs/plans/SEAMLESS_WORLD_PRE_P6_INCUBATION_PLAN_RU.md
  docs/plans/seamless-world-pre-p6-incubation.v1.json

Main control context:
  PROJECT_CONTROL.md
  HARNESS_CONTROL.md
  config/control/project-program-registry.v1.json
  config/control/harness/project-goals.v1.json
  config/control/harness/checkpoint-catalog.v1.json
```

---

# 33. Короткая карта видения

```text
                    CURRENT VISION SNAPSHOT
                             |
                             v
                       R2 REVIEW/CLOSE
                             |
              +--------------+--------------+
              |                             |
          V0 P5 -> P6                PRE-P6 INCUBATION
                                            |
                                  I1 harness/oracles
                                            |
                                      I2 Directory
                                            |
                                  I3 AuthorityDomain
                                            |
                              I4 Player Carrying Domain
                                            |
                                      I5 Gateway
                                            |
                                I6 AOI / cross-owner
                                            |
                                   I7 fault/WAN/soak
                                            |
                                    I8 port/work orders
              |                             |
              +--------------+--------------+
                             |
                             v
                   POST-P6 MAIN DECISION
                             |
                    ACTIVATE_V0_SM1 ?
                       /           \
                    defer          yes
                                    |
                                    v
                            fresh production SM1
                                    |
                  H0 -> H1 -> H2 -> H2A -> H2B
                                    |
                   H3 -> H4 -> H5 -> H6 -> H7
                                    |
                  H8 -> H9 -> H10 -> H11 -> H12
                                    |
                                    v
                         STATIC SEAMLESS WORLD
                                    |
                                    v
                       D1 -> D2 -> D3 dynamic
```

---

## Final note

Этот snapshot намеренно подробный.

Его ценность не в том, чтобы запретить будущей архитектуре изменяться, а в том, чтобы будущие изменения происходили **осознанно**: было видно, какая проблема уже рассматривалась, почему было принято текущее решение и какие invariants предполагалось сохранить.

Если новая evidence покажет лучший путь — архитектуру следует менять.

Но новое решение должно явно объяснить, какой старый assumption оно заменяет и почему новая модель лучше сохраняет цель проекта:

```text
ONE PERSISTENT WORLD
ONE CANONICAL TRUTH
MANY EXECUTION AUTHORITIES
SEAMLESS USER EXPERIENCE
RECOVERABLE AND TESTABLE DISTRIBUTED RUNTIME
```
