# V0 Multi-Route Projection Fabric — архитектура и экспериментальный стенд MRPF-P0..P6

**Статус:** MAIN-OWNED FUTURE ARCHITECTURE PLAN / PRE-P6 RESEARCH TRACK / NOT YET AN ELIGIBLE PRODUCT CHECKPOINT  
**Canonical owner:** `main`  
**Дата:** 2026-08-18  
**Короткое имя:** `MRPF — Multi-Route Projection Fabric`  
**Связанный product gate:** `V0_POST_P6_SEAMLESS_INTEGRATION_RU.md`  
**Будущий product checkpoint:** `V0_SM1_SEAMLESS_PRODUCT_INTEGRATION`

## 0. Зачем этот документ

Этот документ фиксирует следующий архитектурный шаг после SM0: клиент больше не должен мыслиться как объект, подключённый ровно к одному игровому серверу или к жёстко заданной паре `primary/secondary`.

Целевая модель:

```text
ClientConnectionSet
    ├── ACTIVE_AUTHORITY     exactly 1
    ├── PROJECTION           0..N
    ├── WARM                 0..K
    ├── DRAIN                0..K
    └── CONNECTING/DEGRADED  bounded by policy
```

Главные правила:

```text
CONNECTION TOPOLOGY != AUTHORITY TOPOLOGY
N TRANSPORT ROUTES DO NOT MEAN N WRITERS
EXACTLY ONE CANONICAL PLAYER AUTHORITY
FOREIGN/MACRO PROJECTION IS READ-ONLY DERIVED PRESENTATION
CLIENT MAY RECEIVE PROJECTIONS DIRECTLY FROM THEIR SOURCES
ACTIVE AUTHORITY MUST NOT BE THE DEFAULT RELAY FOR ALL NEIGHBOR VIEW TRAFFIC
```

Структура маршрутов не должна иметь архитектурного лимита `2`, `3` или `4`. Практическое число открытых соединений обязательно ограничивается interest/bandwidth/CPU/connection budget policy.

Этот план является обязательным архитектурным дополнением к post-P6 seamless gate. Он может и должен быть предварительно проверен отдельным research-стендом **до достижения продуктового V0 P6**, чтобы будущий V0-SM1 не изобретал multi-route topology одновременно с переносом реального gameplay.

---

## 1. Откуда мы пришли

SM0 уже доказал две важные половины, но они пока существуют раздельно.

### 1.1 Handoff correctness

SM0 доказал:

```text
stable logical_player_id
stable player_entity_id
exactly one writer
authority epoch fencing
freeze -> prepare -> retire -> activate
replay safety
fault isolation
A <-> B repeated handoff
```

Исторический SM0 automated client при redirect меняет текущий destination на target. Это полезный correctness donor, но не финальная production multi-route transport модель.

### 1.2 Multi-source presentation

SM0 P10 доказал:

```text
A projection
B projection
C projection
        ↓
one composer
        ↓
one presentation view
```

При этом process-isolated consumer напрямую запрашивает projection у каждого source process. Active B не обязан проксировать payload A/C. P10 composer уже хранит state по `source_authority_id`, fence'ит source epoch/sequence/checksum, выбирает LOD по budget/distance и не разрешает derived presentation стать canonical truth.

MRPF должен соединить эти две половины:

```text
multi-route direct projection
        +
single active authority
        +
role pivot during handoff
```

---

## 2. Целевая клиентская модель

### 2.1 ClientConnectionSet

Клиент хранит generic registry:

```text
routes[route_id] = {
    authority_region_id,
    server_instance_id,
    endpoint,
    authority_epoch,
    route_revision,
    role,
    capabilities,
    health,
    projection_grant,
    bandwidth_budget,
    last_sequence,
}
```

Роли:

```text
DISCONNECTED
CONNECTING
PROJECTION
WARM
ACTIVE_AUTHORITY
DRAIN
DEGRADED
```

Инвариант:

```text
count(role == ACTIVE_AUTHORITY) == 1
```

`PROJECTION`, `WARM`, `DRAIN` могут существовать одновременно для нескольких источников.

### 2.2 Role pivot вместо reconnect

Один и тот же route должен менять роль без обязательного teardown/reconnect:

```text
PROJECTION
    ↓ player approaches this authority
WARM
    ↓ handoff commit
ACTIVE_AUTHORITY
    ↓ player leaves
DRAIN
    ↓ still visible / useful
PROJECTION
    ↓ no longer relevant
DISCONNECTED
```

Предпочтительное crossing-поведение:

```text
before:
    B = ACTIVE_AUTHORITY
    C = PROJECTION

prewarm:
    B = ACTIVE_AUTHORITY
    C = WARM

pivot:
    B = DRAIN
    C = ACTIVE_AUTHORITY

settled:
    B = PROJECTION or DISCONNECTED
    C = ACTIVE_AUTHORITY
```

Если target уже был projection source, crossing не должен требовать открытия нового transport connection в критический момент.

---

## 3. Direct projection data plane

### 3.1 Нежелательный default

Не делать active authority постоянным relay:

```text
A ─┐
C ─┼─> B(active) ─> Client
D ─┘
```

Это заставляет B оплачивать чужой inbound, aggregation и повторный outbound для каждого клиента.

### 3.2 Предпочтительный путь

```text
A ───────────────> Client
B(active) ───────> Client
C ───────────────> Client
D ───────────────> Client
```

Каждый source отвечает за собственную read-only projection. Клиентский composer сводит их в одну presentation world.

Server-to-server traffic остаётся там, где он действительно нужен:

```text
canonical handoff
cross-authority transaction
item/Construction ownership transfer
lease/topology control
recovery
```

View payload не должен автоматически идти через текущего player authority.

---

## 4. SimulationAuthority и ProjectionPublisher — разные роли

Нельзя смешивать:

```text
кто имеет право мутировать canonical state
```

и:

```text
кто публикует производное визуальное представление
```

Вводится логическое разделение:

```text
SimulationAuthority
    owns canonical mutation rights for effective scope

ProjectionPublisher
    publishes read-only derived representations
```

Один process/server может исполнять обе роли, но контракт остаётся раздельным.

Это позволяет parent/macro server публиковать крупномасштабный вид мира, даже если внутри него существуют child authorities, при условии:

```text
parent macro representation is derived
parent cannot mutate child-owned canonical objects
child authority remains single writer
macro artifact/version is fenced
```

---

## 5. Иерархический пример: Земля + sub-Earth + Луна

### 5.1 Игрок стоит на поверхности

Предположим:

```text
Earth planetary/macro domain
└── Earth surface region 314
    └── currently computed by SUB-EARTH-B
```

Клиент находится внутри region 314.

Маршруты:

```text
SUB-EARTH-B = ACTIVE_AUTHORITY
EARTH-MACRO = PROJECTION
NEIGHBOR-C   = optional PROJECTION/WARM
MOON         = optional CELESTIAL PROJECTION
```

`SUB-EARTH-B` присылает:

```text
local player
near players/NPC/items
local mutable terrain
local constructions
physics-relevant state
high-frequency local deltas
```

`EARTH-MACRO` может присылать:

```text
far terrain silhouette
mountain ranges / skyline
regional atmosphere/cloud macro layers
far large constructions / landmarks
planet-scale derived representation
```

`MOON` может присылать:

```text
very coarse celestial artifact
low-frequency transform/ephemeris state
illumination/phase metadata if required
```

Клиент сводит всё в одну сцену.

### 5.2 Замок в 10 км

Если замок находится вне current sub-region, но достаточно велик и видим:

```text
canonical Construction truth -> owner authority of that scope
far representation -> owner publisher OR Earth macro publisher
client -> receives coarse landmark representation
```

При приближении representation может прогрессивно повышаться:

```text
HLOD silhouette
    ↓
coarse mesh
    ↓
simplified construction mesh
    ↓
near detailed projection
    ↓
canonical interaction only through actual owner
```

### 5.3 Луна в 384 400 км и игрок в 50 км

Distance-only interest policy недостаточна.

Желаемый результат:

```text
Moon at ~384 400 km  -> visible
player at 50 km      -> normally not visible
```

Поэтому projection eligibility определяется не одним радиусом.

---

## 6. Multi-scale Projection Eligibility

Каждый candidate representation классифицируется по нескольким осям.

### 6.1 Representation class

Минимальный набор:

```text
LOCAL_DYNAMIC
    player, NPC, loose item, projectile, small vehicle

REGIONAL_LANDMARK
    castle, tower, large station, large construct

TERRAIN_MACRO
    mountain range, horizon, continent/large terrain proxy

PLANETARY_LAYER
    atmosphere, cloud macro field, planet shell

CELESTIAL_BODY
    Moon, planet, star, large asteroid

EXPLICIT_INTEREST
    future mission/event/navigation representation
```

### 6.2 Eligibility factors

Resolver/selector учитывает:

```text
spatial relationship / scope chain
representation class
physical size
estimated angular size / screen coverage
screen-error budget
horizon / planet occlusion
visibility flags
semantic priority
update cost
observer bandwidth budget
observer connection budget
cached artifact availability
source health
```

Принцип:

```text
DISTANCE IS ONE INPUT, NOT THE GLOBAL VISIBILITY RULE
```

### 6.3 Примеры policy

```text
LOCAL_DYNAMIC:
    hard/soft distance cap; high update rate; no 50-km player by default

REGIONAL_LANDMARK:
    larger distance; coarse HLOD allowed; priority by angular size

TERRAIN_MACRO:
    horizon-aware; content-addressed coarse artifact; low delta rate

CELESTIAL_BODY:
    global/celestial eligibility; may remain visible at enormous distance;
    very coarse immutable artifact + low-rate transform is sufficient
```

Большая Луна может проходить celestial policy при 384 400 км, тогда как двухметровый player не проходит LOCAL_DYNAMIC policy уже на десятках километров.

---

## 7. Не соединяться с сотнями серверов

`N routes` означает отсутствие архитектурного hard-code, а не обязанность держать физическое соединение с каждой authority-region в мире.

Используется иерархическая progressive topology:

```text
far:
    parent / macro aggregate publisher

medium:
    regional publishers

near:
    detailed authority publishers

handoff candidate:
    warm route to exact target
```

Пример подлёта к Земле:

```text
far space:
    SPACE-A ACTIVE
    EARTH-MACRO PROJECTION

approach:
    SPACE-A ACTIVE
    EARTH-MACRO PROJECTION
    SURFACE-314 PROJECTION/CONNECTING

landing:
    SPACE-A DRAIN
    SURFACE-314 ACTIVE
    EARTH-MACRO PROJECTION
    SURFACE-neighbor PROJECTION/WARM
```

Connection budget может закрывать малоценные routes и заменять их aggregate source.

---

## 8. Projection Manifest / source discovery

Клиент не сканирует сеть и не выбирает произвольные серверы самостоятельно.

Control plane выдаёт versioned manifest:

```text
ProjectionManifest {
    observer_session_id
    observer_world_address
    topology_revision
    manifest_revision
    sources[]
}
```

Source descriptor содержит минимум:

```text
source_authority_id
projection_publisher_id
server_instance_id
endpoint
source_authority_epoch
scope_chain
representation_classes
role_hint
quality_ceiling
bandwidth_hint
projection_grant
expires_at
```

Manifest может быть построен специализированным Interest/Route Resolver поверх Directory/SD/AUTHORITY данных.

Active gameplay server не обязан быть data relay. Его роль в security/control может ограничиваться подтверждением observer position/identity или выдачей/co-sign signed grant.

---

## 9. Security: ProjectionGrant

Нельзя позволять клиенту запросить arbitrary region и использовать projection fabric как wallhack.

Projection source принимает subscription только с валидным grant:

```text
ProjectionGrant {
    session/principal
    player_entity_id
    allowed spatial scope / observer anchor
    allowed representation classes
    max quality
    max radius / policy envelope
    authority/topology revision
    expiry
    signature/token
}
```

Клиент управляет transport lifecycle, но не определяет единолично, что ему разрешено видеть.

При stale/forged grant source отвечает fail-closed и не выдаёт canonical/private state.

---

## 10. Projection stream contract

Каждый stream обязан быть source-bound:

```text
source_authority_id
source_authority_epoch
projection_publisher_id
projection_sequence
manifest/subscription revision
checksum/hash
representation class
presentation_only = true
canonical_write_allowed = false
```

Per-source fencing:

```text
epoch rollback -> reject
sequence rollback -> reject
same sequence + different checksum -> reject
exact replay -> idempotent
source dropout -> degrade/remove only that source
```

Ни одна projection не может быть использована как доказательство canonical mutation ownership.

---

## 11. LOD, progressive representation и cache

Переиспользовать принципы RL3, MW7, NX interest, а не создавать отдельный SM-only renderer/network stack.

Для тяжёлых представлений предпочтительны content-addressed artifacts:

```text
macro proxy
    ↓
coarse mesh
    ↓
simplified mesh
    ↓
fine representation
```

Клиент может иметь artifact cache. Если hash совпадает, source передаёт только manifest/activation metadata.

Особенно важно для:

```text
mountains
planet shell
Moon mesh/texture proxy
large castle HLOD
large construction silhouette
```

Очень далёкие почти статические объекты не требуют high-rate stream.

Пример Moon:

```text
cached celestial artifact
+ low-rate transform/ephemeris
+ rare representation revision invalidation
```

---

## 12. Interaction с foreign projection

Projection read-only не означает, что объект нельзя интерактивно использовать.

### 12.1 Простое intent routing

Если клиент уже напрямую соединён с owner source:

```text
Client -> owner authority: INTERACT intent
```

Owner проверяет:

```text
session/grant
actor identity
current actor authority proof
range/visibility
object revision
permissions
operation replay
```

### 12.2 Cross-authority mutation/transfer

Client никогда не координирует canonical transaction.

Например pickup foreign item:

```text
Client -> item owner: PICKUP intent
item owner <-> player/item target authority: canonical transaction
commit once
client receives result/projection update
```

Для сложных Item/Construction/Matter transfer server-to-server coordination остаётся обязательным.

---

## 13. Server orchestration / кто знает соседей

Не строить permanent full mesh `N^2`.

Directory/Topology plane хранит/разрешает:

```text
authority_region_id
parent/child scope relation
adjacent/overlap-interest relation
current server_instance_id
endpoint
authority_epoch
lease/topology revision
health / draining / provisioning state
projection capabilities
```

Server открывает peer control relationship только при необходимости:

```text
handoff candidate
cross-authority interaction
derived summary exchange
required projection aggregation
recovery
```

Client projection data path может при этом идти напрямую к source publisher.

Для future on-demand region provisioning:

```text
interest predicts target region
-> control plane provisions worker
-> worker bootstraps deterministic baseline + durable mutations
-> publishes projection capability
-> client opens PROJECTION route
-> route upgrades to WARM
-> only after PREPARED may authority pivot occur
```

---

## 14. Parent/child authority и macro projection

Spatial hierarchy может быть:

```text
Earth macro scope
└── region 314 child authority
    └── optional city/ship nested authority
```

Canonical writable scopes не должны реально перекрываться.

Но presentation scopes могут перекрываться:

```text
EARTH-MACRO publishes derived horizon for whole Earth
SUB-EARTH-314 publishes detailed local region
```

Composer обязан знать representation priority/source binding и исключать duplicate presentation identity.

Правило:

```text
OVERLAPPING PRESENTATION IS ALLOWED
OVERLAPPING CANONICAL WRITE OWNERSHIP IS NOT
```

Если macro representation включает child-owned construct/terrain summary, это только derived artifact, построенный из accepted baseline/durable summary/revision, а не второй canonical store.

---

## 15. Experimental stand до product V0 P6

Рекомендуется открыть отдельный research branch после формального freeze/closure SM0.

Рекомендуемое имя:

```text
research/mrpf-multi-route-projection-fabric
```

Base выбирается отдельным Work Order. Допустим donor-based research base от frozen SM0 evidence, но **не** превращать этот branch в product V0 base.

Checkpoint IDs должны иметь префикс `MRPF_`, чтобы не путать их с product `V0_P0..P8` и historical `SM0_P*`.

### MRPF-P0 — Contract Freeze

Доказать детерминированными unit/model tests:

```text
ClientConnectionSet generic N routes
role state machine
exactly-one-active invariant
ProjectionManifest
ProjectionGrant
ProjectionSourceDescriptor
projection epoch/sequence/hash fencing
representation class policy
```

Никакой production V0 mutation.

### MRPF-P1 — Direct N-Source Fan-In

Real processes:

```text
Authority/Projection A
Authority/Projection B
Authority/Projection C
Celestial/Macro D
Client composer
```

B является ACTIVE, A/C/D — PROJECTION.

Проверить:

```text
client receives all sources directly
B does not relay A/C/D payload
one-source dropout isolated
per-source sequence/hash fencing
all foreign data read-only
connection registry has no hard-coded pair assumption
```

### MRPF-P2 — Hierarchical Earth / Sub-Earth Composition

Топология:

```text
EARTH-MACRO
└── SUB-EARTH-314 ACTIVE
+ NEIGHBOR-315 PROJECTION
```

Сцена:

```text
local player/ground from SUB-EARTH
far mountains from EARTH-MACRO
far castle/landmark from macro or neighbor source
neighbor dynamic state only when policy permits
```

Проверить отсутствие duplicate presentation identity и отсутствие parent write authority над child canonical scope.

### MRPF-P3 — Multi-Scale Visibility / Moon Case

Добавить Moon projection source и policy fixtures.

Обязательный сценарий:

```text
Moon ~384 400 km -> INCLUDED as CELESTIAL_BODY coarse representation
player 50 km     -> EXCLUDED as LOCAL_DYNAMIC
mountain skyline -> INCLUDED as TERRAIN_MACRO
castle 10 km     -> INCLUDED/EXCLUDED according to angular/landmark policy
```

Проверить:

```text
angular-size threshold
representation class
horizon/occlusion flag
screen-error budget
bandwidth priority
cache reuse
LOD coarse->fine
```

### MRPF-P4 — Projection -> Warm -> Active Pivot

Target C уже подключён как PROJECTION до crossing.

Проверить:

```text
C PROJECTION -> WARM -> ACTIVE
B ACTIVE -> DRAIN -> PROJECTION/DISCONNECTED
no new player identity
no required transport reconnect at pivot
one active authority at every observable state
input sequence continuity
projection identity continuity
```

### MRPF-P5 — Orchestrated Discovery / Grants / Churn

Отдельный resolver/directory process выдаёт manifests.

Проверить:

```text
client does not scan arbitrary endpoints
signed/validated projection grants
manifest revision replacement
source added/removed as observer moves
server restart changes server_instance_id but not stable authority_region identity
stale endpoint/epoch fails closed
no permanent N^2 server mesh
connection budget closes low-value source
```

### MRPF-P6 — Integrated Multi-Scale Multi-Server Stand

Минимум distinct processes:

```text
Directory / Interest Resolver
SUB-EARTH-A authority+projection
SUB-EARTH-B neighbor/target authority+projection
EARTH-MACRO projection publisher
MOON projection publisher
real client/composer
```

Опционально отдельный observer/second client.

Integrated scenario:

```text
1. client ACTIVE on SUB-EARTH-A
2. client concurrently receives EARTH-MACRO + MOON + neighbor projections
3. local player/near items stay A-authoritative
4. far mountain is visible from EARTH-MACRO
5. far castle uses coarse landmark representation
6. 50-km remote player is not visible by default policy
7. Moon remains visible by celestial policy
8. client moves toward B
9. existing B projection route becomes WARM
10. A -> B authority pivot occurs without transport reconnect
11. A becomes DRAIN/PROJECTION
12. all identities/epochs remain fenced
13. drop EARTH-MACRO: local authority continues
14. drop MOON: only Moon representation degrades/disappears
15. drop unrelated neighbor: active gameplay remains live
16. restore source / manifest revision and recover projection
```

P6 acceptance минимум:

```text
exactly one active player writer
zero duplicate canonical entity IDs
zero projection->canonical promotion
zero ungranted projection leak
zero source sequence/epoch rollback accepted
all source dropouts isolated
no active-server relay required for macro/Moon payload
role pivot reuses preexisting target route
client connection count determined by budget/policy, not pair hard-code
all processes exit cleanly
machine-readable summary
```

Рекомендуемый soak после deterministic acceptance:

```text
>= 30 minutes
multiple manifest revisions
repeated A <-> B pivots
projection source churn
bounded memory/connection count
no queue growth
```

---

## 16. Что MRPF-P6 НЕ доказывает

Не заявлять автоматически:

```text
production World Directory
production arbitrary planetary sharding
dynamic split/merge balancing
on-demand cloud/Kubernetes provisioning
full anti-cheat/security hardening
WAN-ready bandwidth targets
all celestial bodies
all Construction HLOD
all terrain/matter streaming
```

MRPF-P6 доказывает форму client/server topology и projection semantics.

On-demand compute provisioning должен идти отдельным следующим research/runtime checkpoint после этой основы.

---

## 17. Связь с product V0 P6 -> V0-SM1

Желаемая последовательность:

```text
NOW:
    SM0 closure/freeze
    MRPF research may proceed in parallel with V0 P4/P5/P6

PRODUCT:
    V0 P4 -> P5 -> P6 accepted
             +
    SM0 accepted donor
             +
    MRPF-P6 accepted donor OR explicit decision to include its missing gates in V0-SM1
             ↓
    V0-SM1 seamless product integration
             ↓
    P7 terrain
    P8 ship
```

Future V0-SM1 должен переносить contracts/semantics, а не research fixture truth.

---

## 18. Что переносить в V0-SM1

Переносим:

```text
generic N-route ClientConnectionSet
exactly-one-active route invariant
PROJECTION/WARM/ACTIVE/DRAIN role pivot
direct source projection subscriptions
ProjectionManifest/Grant semantics
multi-scale representation classes
per-source epoch/sequence/checksum fencing
hierarchical parent/macro + child detailed composition
bandwidth/connection/LOD budget
source dropout isolation
content-addressed representation cache
```

Не переносим как production owners:

```text
MRPF synthetic directory
MRPF fixture-specific source registry
MRPF synthetic Earth/Moon objects
MRPF test authority store
MRPF private persistence
```

---

## 19. Donor alignment

Этот план должен переиспользовать существующие accepted/reviewed идеи:

```text
SM0 P10          multi-authority view composition
SM0 P6/P7        projection pivot / N-authority routing donors
MW7              regional interest projection
RL3              representation-aware coarse-to-fine network streaming + cache
NX                transport/interest/budget ownership
SD/AUTHORITY      spatial address vs authority lease separation
G                 deterministic procedural baseline
LIFE              active/dormant lifecycle
```

Нельзя создавать private альтернативу этим owners без main/NX architecture decision.

---

## 20. Final architecture rule

```text
THE CLIENT PRESENTATION WORLD MAY BE COMPOSED FROM MANY SERVERS
THE CLIENT CAN KEEP N ROUTES, BUT POLICY BOUNDS REAL CONNECTIONS
EXACTLY ONE ROUTE OWNS CANONICAL PLAYER AUTHORITY
PROJECTION ROUTES ARE READ-ONLY DERIVED SOURCES
DIRECT PROJECTION IS PREFERRED OVER ACTIVE-SERVER RELAY
DISTANCE ALONE DOES NOT DEFINE VISIBILITY
MOON CAN BE VISIBLE WHILE A FAR PLAYER IS NOT
HIERARCHICAL MACRO SOURCES PREVENT HUNDREDS OF CONNECTIONS
PROJECTION PUBLISHER != CANONICAL SIMULATION OWNER
OVERLAPPING PRESENTATION IS ALLOWED; OVERLAPPING WRITERS ARE NOT
TARGET PROJECTION ROUTE SHOULD BE PROMOTABLE TO WARM/ACTIVE WITHOUT RECONNECT
MRPF-P0..P6 SHOULD DE-RISK THIS BEFORE PRODUCT V0-SM1
```
