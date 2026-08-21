# V0 Multi-Route Projection Fabric — архитектура и экспериментальный стенд MRPF-P0..P6

**Статус:** MAIN-OWNED FUTURE ARCHITECTURE PLAN / PRE-P6 RESEARCH TRACK / NOT YET AN ELIGIBLE PRODUCT CHECKPOINT  
**Canonical owner:** `main`  
**Дата:** 2026-08-18  
**Короткое имя:** `MRPF — Multi-Route Projection Fabric`  
**Связанный product gate:** `V0_POST_P6_SEAMLESS_INTEGRATION_RU.md`  
**Будущий product checkpoint:** `V0_SM1_SEAMLESS_PRODUCT_INTEGRATION`

> Обязательный companion для иерархических стендов: `MRPF_HIERARCHICAL_PROJECTION_STANDS_RU.md` (`MRPF-H0..H7`). Он описывает parallel research track `SPACE -> EARTH -> SURFACE -> BASE + MOON`, representation replacement, upward HLOD delegation и nested authority/presentation transitions. MRPF-P и MRPF-H могут развиваться параллельно до V0 P6 и сходятся как donor evidence перед V0-SM1.

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
authority_id / publisher_id
server_instance_id
endpoint
source_epoch
spatial scope / coverage
representation classes
max_allowed_lod
priority
expiry
projection grant/ticket
```

Manifest является hint/authorization для projection topology, но не canonical world truth.

Stale manifest/revision должен fail closed.

---

## 9. Security / anti-wallhack boundary

Наличие physical endpoint не означает право подписаться на любое содержимое сервера.

Projection source обязан проверять `ProjectionGrant`.

Grant должен связывать минимум:

```text
principal/session
player_entity_id
observer authority/session proof
allowed spatial scope
allowed representation classes
max LOD / detail
expiry
topology/route revision
```

Клиент может управлять transport lifecycle, но не может сам объявить:

```text
"покажи мне всех players на планете"
```

`LOCAL_DYNAMIC` особенно жёстко ограничивается server-approved interest.

---

## 10. Command routing при direct projection

Наличие direct projection route не даёт write capability.

Для foreign object:

```text
projection says owner_authority_id = C
```

Возможные command paths:

```text
Client -> active B -> C
```

или в будущем:

```text
Client -> C with owner-scoped capability/ticket
```

Но canonical decision всегда делает actual owner.

Для cross-authority transfer (pickup, inventory transfer, Construction/material ownership) клиент никогда не является transaction coordinator. Server-to-server coordination остаётся обязательной.

---

## 11. Projection source fan-out / server cost

Direct projection убирает relay B, но source C всё ещё может обслуживать множество observers.

Требуется shared projection generation:

```text
canonical C state
    ↓
build reusable projection/representation once per compatible tier
    ↓
encode/cache
    ↓
fan-out to subscribers
```

Не пересобирать одинаковый coarse artifact отдельно на каждого клиента.

Update classes:

```text
near dynamic   -> high Hz
medium dynamic -> lower Hz
far landmark   -> low Hz / event-driven
terrain macro  -> cache + invalidation
celestial      -> mostly cache + very low-rate transform
```

---

## 12. Связь с существующими foundations

MRPF не создаёт второй network/interest/LOD stack.

Обязательные donors/owners:

```text
SM0 P10/P11
    multi-source presentation + fencing + fault evidence

NX5
    remote interpolation path

NX8
    shared interest/replication budget direction

MW7
    regional subscription / projection sequence concepts

RL3
    representation-aware coarse->fine streaming / cache

S0 / SD
    spatial hierarchy / WorldAddress semantics

AUTHORITY
    writer lease/epoch; presentation never owns canonical truth
```

Если требуется новый global network foundation, V0/MRPF должен route change в NX/main architecture control, а не создавать private foundation.

---

## 13. Экспериментальная лестница MRPF-P0..P6

### P0 — Contract Freeze

Зафиксировать DTO/инварианты:

```text
ClientConnectionSet
AuthorityRoute
ProjectionManifest
ProjectionSourceDescriptor
ProjectionGrant
ProjectionSubscription
ProjectionFrame
RepresentationClass
RouteRole
```

Focused tests:

- exactly one ACTIVE route;
- arbitrary number of projection routes in model;
- duplicate route/source rejection;
- stale manifest rejection;
- forged/expired grant rejection;
- projection cannot request mutation capability;
- deterministic route-role pivot state machine.

### P1 — Direct N-Source Fan-In

Processes:

```text
A projection source
B active authority + projection source
C projection source
Moon/Macro source
Client composer
```

Доказать:

```text
client receives A/B/C/Moon directly
B does not relay A/C/Moon payload
one client presentation view
per-source epoch/sequence/checksum fencing
one-source dropout isolated
```

Collect bytes/packets per source to prove data path.

### P2 — Earth / Sub-Earth Hierarchy

Topology:

```text
EARTH-MACRO publisher
└── SUB-EARTH-314 simulation authority
```

Client:

```text
SUB-EARTH-314 ACTIVE
EARTH-MACRO PROJECTION
NEIGHBOR optional PROJECTION
```

Scene/evidence should show simultaneously:

```text
near terrain from SUB-EARTH
far mountain from EARTH
far landmark coarse projection
```

Доказать, что parent representation does not imply parent write authority.

### P3 — Multi-Scale Visibility / Moon

Deterministic candidate set includes:

```text
Moon ~384400 km
player 50 km
castle 10 km
mountain skyline
near local player
```

Policy должна получить ожидаемую inclusion/exclusion при разных screen-error/bandwidth budgets.

Дополнительно проверить:

```text
coarse -> fine progressive replacement
cache reuse
horizon/occlusion
budget degradation
```

### P4 — Projection -> Warm -> Active Pivot

Topology initially:

```text
A ACTIVE
B PROJECTION
C PROJECTION
```

Player moves toward B:

```text
B PROJECTION -> WARM
```

Handoff:

```text
A ACTIVE -> DRAIN
B WARM -> ACTIVE
```

Hard gate:

```text
no new transport connection required at crossing if B route already exists
same logical/player identity
exactly one writer
input sequence continuous
A may remain PROJECTION/DRAIN after pivot
```

### P5 — Directory / Manifest / Grants / Churn

Separate resolver process.

Check:

```text
manifest add/remove source
revision replacement
source health
projection grant expiry/renewal
connection budget
route close/reopen
stale endpoint/server_instance fencing
```

Client не должен открывать unauthorized source даже если endpoint известен.

### P6 — Integrated Multi-Server Stand

Минимум real processes:

```text
1 Directory / Interest Resolver
2 SUB-EARTH-A
3 SUB-EARTH-B
4 EARTH-MACRO
5 MOON / CELESTIAL publisher
6 CLIENT
```

Scenario:

```text
client ACTIVE on A
Earth macro + Moon + B projections active
far mountain visible
far castle coarse visible
50-km player hidden
Moon visible
move toward B
B PROJECTION -> WARM
A ACTIVE -> DRAIN
B WARM -> ACTIVE
no reconnect / no new player identity
drop EARTH-MACRO -> local gameplay continues
drop MOON -> only Moon projection degrades/disappears
restore manifest/source -> projection recovers
```

Acceptance:

```text
exactly one ACTIVE authority through entire scenario
no canonical mutation from projections
no relay of foreign view payload through active authority
bounded route count under policy
projection dropout isolation
source sequence/epoch fencing
stable player identity
zero split-brain
```

After deterministic pass:

```text
>= 30 minute soak
repeated A<->B pivots
projection source churn
manifest revision churn
no unbounded queue/memory/route growth
```

---

## 14. Отдельный future extension: on-demand authority provisioning

После generic MRPF correctness возможен следующий research slice:

```text
landing prediction
    ↓
region has no running compute
    ↓
provision target server
    ↓
deterministic baseline generation
    ↓
load sparse mutations
    ↓
Projection route becomes available
    ↓
PROJECTION -> WARM -> ACTIVE
```

Это не должно входить в первый P0..P6, чтобы не смешивать routing/presentation correctness с orchestration/bootstrap.

Нужны отдельные contracts:

```text
AuthorityRegionId stable
ServerInstanceId disposable
provisioning lifecycle
region bootstrap request/result
generator/content revisions
mutation checkpoint
lease only after PREPARED
failure before retirement keeps source writer
```

---

## 15. Что означает "server Earth"

Не фиксировать физическую архитектуру как:

```text
one planet == one permanent server
```

Логические identities:

```text
Earth planetary/macro domain
Earth surface authority regions
```

отделены от physical server instances.

Сегодня стенд может иметь один EARTH-MACRO process и один SUB-EARTH process. Позже Earth surface region может мигрировать или provisioning'иться на другом worker без изменения WorldAddress/region identity.

---

## 16. План параллельной разработки до V0 P6

MRPF разрешён как отдельный research track, пока основной V0 идёт:

```text
V0:
P4 -> P5 -> P6

parallel:
MRPF P0 -> P1 -> P2 -> P3 -> P4 -> P5 -> P6
```

Не нужно блокировать V0 P4/P5 этим экспериментом.

Предпочтительно к моменту product P6 иметь:

```text
MRPF-P6 accepted research evidence
```

Тогда post-P6 V0-SM1 переносит proven capability вместо одновременного исследования transport topology.

Если MRPF не завершён к P6, post-P6 gate обязан включить недостающие MRPF acceptance slices или оформить explicit human defer.

Research branch рекомендуемо:

```text
research/mrpf-multi-route-projection-fabric
```

или Harness-generated equivalent.

Нельзя продолжать frozen SM0 branch как runtime carrier этой новой архитектуры.

---

## 17. Convergence в V0-SM1

После product P6:

```text
accepted V0 P6
+
accepted/frozen SM0 donor
+
MRPF donor evidence
+
current NX/authority foundation
    ↓
fresh V0-SM1 convergence branch
```

V0-SM1 использует real:

```text
player
Item Graph
mining
Construction/outpost
reconnect/persistence
graphical client
```

и переносит MRPF contracts в production-owned systems.

Не cherry-pick synthetic research truth как новую canonical foundation.

---

## 18. Final architecture rules

```text
CLIENT ROUTES ARE A GENERIC SET, NOT PRIMARY+SECONDARY FIELDS
EXACTLY ONE ACTIVE PLAYER AUTHORITY
PROJECTION ROUTES ARE READ-ONLY
PROJECTION PAYLOAD SHOULD NORMALLY FLOW DIRECT SOURCE -> CLIENT
ACTIVE AUTHORITY IS NOT THE DEFAULT VISUAL RELAY
DIRECT CONNECTION DOES NOT GRANT VISIBILITY RIGHTS
PROJECTION GRANTS ARE SERVER-CONTROLLED
DISTANCE ALONE DOES NOT DEFINE INTEREST
CELESTIAL / LANDMARK / TERRAIN / DYNAMIC USE DIFFERENT POLICIES
N ROUTES ARE POLICY-BOUNDED, NOT PROTOCOL-HARDCODED
FAR WORLD USES AGGREGATE/MACRO PUBLISHERS INSTEAD OF HUNDREDS OF CONNECTIONS
SIMULATION AUTHORITY != PROJECTION PUBLISHER
REPRESENTATION != CANONICAL TRUTH
SERVER INSTANCE IS DISPOSABLE; WORLD/REGION IDENTITY IS NOT
MRPF MAY RUN BEFORE P6; PRODUCT SEAMLESS ACTIVATES AFTER P6
```