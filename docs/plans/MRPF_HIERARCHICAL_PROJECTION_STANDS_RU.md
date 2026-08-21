# MRPF Hierarchical Projection Stands — parallel research roadmap H0..H7

**Статус:** MAIN-OWNED PARALLEL RESEARCH PLAN / NOT A PRODUCT CHECKPOINT  
**Canonical owner:** `main`  
**Дата:** 2026-08-18  
**Parent architecture:** `V0_MULTI_ROUTE_PROJECTION_FABRIC_RU.md`  
**Product convergence gate:** `V0_POST_P6_SEAMLESS_INTEGRATION_RU.md`  
**Короткое имя:** `MRPF-H — Hierarchical Projection Stands`

## 0. Назначение

Эта дорожная карта разрешает и описывает отдельную стендовую разработку, которую можно вести **параллельно основной V0 product lane P4 -> P5 -> P6**.

Она не должна менять production V0 truth и не должна продолжать frozen SM0 branch как P12/P13.

Цель — заранее экспериментально проверить модель:

```text
SPACE / open-space domain
        ↓ representation ancestry
EARTH macro domain
        ↓
SURFACE region
        ↓
BASE / POI / city child domain
```

плюс дальний celestial source:

```text
MOON
```

Клиент должен уметь одновременно получать представления от нескольких уровней, при этом иметь ровно один canonical `ACTIVE_AUTHORITY`.

Главный invariant:

```text
AUTHORITY HIERARCHY != REPRESENTATION HIERARCHY
CONNECTION TOPOLOGY != AUTHORITY TOPOLOGY
EXACTLY ONE CANONICAL PLAYER WRITER
0..N READ-ONLY PROJECTION SOURCES
COARSE AND FINE REPRESENTATIONS MUST REPLACE/COMPOSE, NOT DUPLICATE TRUTH
```

---

## 1. Почему отдельная H-линия

Уже существующий MRPF-P0..P6 исследует generic multi-route client, direct N-source fan-in, route roles, manifests/grants и generic projection composition.

MRPF-H отвечает на другой, более конкретный вопрос:

> как свести один визуальный мир из вложенных пространственных уровней, где разные уровни могут иметь разных simulation authorities и разных projection publishers?

Поэтому линии могут развиваться параллельно:

```text
MRPF-P: generic connection / routing / fan-in
          \
           +----> shared convergence
          /
MRPF-H: SPACE/EARTH/SURFACE/BASE hierarchical projection stack
```

Рекомендуемая research branch:

```text
research/mrpf-hierarchical-projection-stack
```

При необходимости каждый H-checkpoint может иметь отдельную дочернюю ветку/worktree. Не использовать current V0 product branch как рабочую research ветку.

---

## 2. Базовая модель стенда

Логическая spatial hierarchy:

```text
SOLAR / SPACE
│
├── EARTH
│   └── SURFACE-314
│       └── BASE-17
│
└── MOON
```

Canonical authority в конкретный момент может быть, например:

```text
BASE-17 = ACTIVE_AUTHORITY
```

При этом client presentation может одновременно иметь:

```text
BASE-17      detailed local projection
SURFACE-314  local terrain / regional context
EARTH        macro terrain / mountains / atmosphere / landmarks
SPACE        Sun / Moon / stars / celestial macro view
```

Предки не получают право мутировать child-owned canonical state только потому, что они публикуют coarse representation.

---

## 3. Обязательные DTO/понятия для стендов

До runtime-реализации H-линия должна зафиксировать минимальные контракты.

### 3.1 Projection representation identity

Каждая representation должна иметь минимум:

```text
representation_id
canonical_subject_id
source_domain_id
source_authority_id / publisher_id
source_revision
representation_class
lod_level
coverage_scope
reference_frame_id
content_hash / checksum
valid_from_revision
```

### 3.2 Replacement / coverage contract

Fine representation обязана явно знать, какую coarse coverage она замещает:

```text
replacement_group_id
coverage_scope
priority / specificity
replaces_representation_ids[] or deterministic replacement rule
```

Запрещено получать видимый результат вида:

```text
coarse Earth surface
+
fine Surface surface
=
z-fighting / duplicate mountain / duplicate castle
```

### 3.3 Projection ancestry

Client composer должен знать chain:

```text
SPACE
  ↓
EARTH
  ↓
SURFACE-314
  ↓
BASE-17
```

Это representation ancestry, а не доказательство writer authority.

### 3.4 Active ancestry chain

Отдельно хранится control/authority chain, например:

```text
SPACE -> EARTH -> SURFACE-314 -> BASE-17
```

но:

```text
count(ACTIVE_AUTHORITY) == 1
```

Остальные уровни могут быть `PROJECTION`, `WARM`, `DRAIN` или отсутствовать физически.

---

# 4. MRPF-H0 — Contract Freeze / offline composer model

## Цель

Доказать contracts до процессов и сети.

Минимальная topology:

```text
synthetic SPACE representation
synthetic EARTH representation
synthetic SURFACE representation
synthetic BASE representation
one deterministic composer
```

Проверить:

- stable canonical subject identity сквозь LOD;
- deterministic specificity order `SPACE < EARTH < SURFACE < BASE`;
- coverage replacement без overlap artifacts;
- stale source revision reject;
- same-revision mutation reject;
- removal fine layer atomically reveals valid coarse fallback;
- derived representation никогда не становится canonical state.

Acceptance:

```text
same inputs -> same composed view hash
no duplicate representation in same replacement group
no gap after atomic fine-layer removal when valid fallback exists
zero canonical mutation APIs in composer
```

H0 может выполняться полностью headless.

---

# 5. MRPF-H1 — SPACE + EARTH coarse/fine replacement

## Процессы

```text
SPACE publisher process
EARTH publisher process
CLIENT/composer process
```

SPACE отвечает за open-space presentation и содержит coarse Earth representation:

```text
Earth LOD0 sphere / macro artifact
Earth transform
Moon/Sun placeholders allowed
```

EARTH выдаёт более точную Earth representation:

```text
Earth LOD1
continent / mountain macro
atmosphere detail
large landmark layer
```

Сценарий:

```text
1. Client connected only to SPACE.
2. Earth LOD0 visible.
3. EARTH route opens as PROJECTION.
4. Earth LOD1 becomes ready.
5. LOD1 atomically replaces matching LOD0 coverage.
6. EARTH source drops.
7. Client atomically falls back to valid SPACE LOD0.
8. EARTH reconnects with newer source_revision.
9. Fine layer returns without duplicate Earth identity.
```

Hard gates:

```text
one Earth identity
no visible double Earth
no frame with invalid mixed source revision
source dropout affects Earth fine layer only
SPACE control/presentation continues
```

Graphical evidence желательно обязательно: camera approach + forced source dropout.

---

# 6. MRPF-H2 — EARTH + SURFACE nested projection

## Процессы

```text
SPACE optional
EARTH-MACRO publisher
SURFACE-314 authority/publisher
CLIENT
```

Игрок пока canonical на `SURFACE-314`.

Routes:

```text
SURFACE-314 = ACTIVE_AUTHORITY
EARTH       = PROJECTION
```

EARTH выдаёт:

```text
far mountains
horizon
macro terrain
large distant landmark proxy
atmosphere macro
```

SURFACE выдаёт:

```text
local mutable terrain
rocks/vegetation
local constructions/items
physics-relevant representation
```

Стенд должен доказать:

- local terrain заменяет Earth macro только в своей coverage;
- far mountain outside local coverage остаётся из EARTH;
- far castle может идти coarse из EARTH, пока exact owner далеко;
- child surface canonical mutations не меняются Earth publisher'ом;
- Earth projection dropout не останавливает local gameplay;
- Surface dropout не позволяет Earth автоматически получить write authority.

Acceptance visual scene:

```text
near ground     <- SURFACE
far mountain    <- EARTH
far castle HLOD <- EARTH
sky/atmosphere  <- EARTH/SPACE according to contract
```

---

# 7. MRPF-H3 — SURFACE + BASE nested authority/projection

## Процессы

```text
EARTH-MACRO
SURFACE-314
BASE-17
CLIENT
```

Сценарий A — снаружи базы:

```text
SURFACE = ACTIVE_AUTHORITY
BASE    = PROJECTION
EARTH   = PROJECTION
```

Сценарий B — вход в базу:

```text
SURFACE ACTIVE -> DRAIN/PROJECTION
BASE PROJECTION -> WARM -> ACTIVE_AUTHORITY
EARTH stays PROJECTION
```

После входа клиент продолжает видеть:

```text
base interior / doors / items <- BASE
outside nearby terrain        <- SURFACE
far mountains / skyline       <- EARTH
```

Hard gates:

```text
same player identity
one writer throughout pivot
base proxy -> detailed base replacement without duplicate structure
outside surface remains visible where portal/window/open area permits
ancestor projection continuity across authority handoff
```

Отдельный тест: выход обратно `BASE -> SURFACE` с обратным role pivot.

---

# 8. MRPF-H4 — Upward projection delegation / dormant child

Это ключевой stand для масштабирования.

## Гипотеза

Detailed child authority не обязан быть online, чтобы distant observer видел coarse derived representation.

Pipeline:

```text
BASE canonical state
    ↓
BASE HLOD builder
    ↓ publish immutable artifact
SURFACE regional cache/catalog
    ↓ aggregate / further simplify
EARTH landmark catalog
```

Сценарий:

```text
1. BASE-17 online, build/revision R.
2. BASE publishes HLOD0/HLOD1 with content hashes.
3. SURFACE/EARTH accept derived artifacts.
4. BASE-17 becomes DORMANT/OFFLINE.
5. Remote client at 20 km has NO BASE connection.
6. Client still sees castle/base coarse representation from EARTH/SURFACE publisher.
7. Canonical base changes after reactivation.
8. New artifact revision invalidates old parent cache.
9. Parent publishes new HLOD without becoming base canonical owner.
```

Acceptance:

```text
BASE process absent -> distant representation still visible
stale artifact fenced by source/canonical revision
parent cannot mutate BASE truth
artifact promotion upward is lossy/derived only
no need for one client connection per dormant POI
```

Это stand, который должен доказать модель `canonical detail -> regional HLOD -> planetary macro`.

---

# 9. MRPF-H5 — SPACE + MOON celestial projection policy

Цель — доказать, что дальняя видимость не равна dynamic-interest radius.

## Процессы

```text
SPACE
MOON publisher (initially optional for client)
EARTH optional
CLIENT
```

### Фаза 1 — far Moon without Moon client route

SPACE уже имеет coarse Moon artifact:

```text
Moon LOD0
transform / ephemeris
illumination/phase metadata if needed
```

Client routes:

```text
SPACE = ACTIVE_AUTHORITY
MOON  = NO DIRECT CONNECTION
```

Acceptance:

```text
Moon ~384400 km visible
50 km LOCAL_DYNAMIC player not visible by default
Moon payload mostly cache hit / low-rate transform
```

### Фаза 2 — approach Moon

По мере роста angular size/screen error:

```text
MOON route CONNECTING
    ↓
PROJECTION
    ↓
coarse SPACE Moon replaced by finer MOON representation
    ↓
WARM
    ↓
ACTIVE_AUTHORITY when authority boundary requires it
```

Проверить симметричный уход от Earth/Moon fine layers обратно к SPACE coarse representation.

### Eligibility factors

Test matrix должна менять независимо:

```text
distance
physical size
angular size
representation class
screen-error threshold
horizon/occlusion
bandwidth budget
cache hit/miss
semantic priority
```

Hard rule:

```text
DISTANCE ALONE MUST NOT DECIDE VISIBILITY
```

---

# 10. MRPF-H6 — Integrated SPACE -> EARTH -> SURFACE -> BASE chain

Это основной интегрированный donor stand H-линии.

## Минимум процессов

```text
DIRECTORY / route-interest resolver
SPACE
EARTH
SURFACE-A
BASE
CLIENT
```

Опционально:

```text
SURFACE-B
MOON
```

## End-to-end scenario

```text
A. Player in open space
   SPACE ACTIVE
   Earth coarse visible from SPACE

B. Approach Earth
   EARTH PROJECTION opens
   Earth fine macro replaces SPACE Earth coverage

C. Descend toward surface
   SURFACE-A PROJECTION -> WARM
   local terrain progressively replaces Earth macro

D. Land
   SPACE/EARTH stay projection ancestors as needed
   SURFACE-A becomes ACTIVE

E. Move toward base
   BASE coarse proxy initially comes from EARTH/SURFACE
   BASE direct route opens only when justified
   BASE PROJECTION -> WARM

F. Enter base
   BASE becomes ACTIVE
   SURFACE becomes projection ancestor
   EARTH/SPACE remain presentation ancestors

G. Exit base and later leave planet
   reverse pivots
   fine representations collapse back toward parent coarse layers
```

Hard correctness gates:

```text
same logical player identity end-to-end
exactly one active authority at every step
no representation double-counting
no visible hole when valid fallback exists
source epoch/revision fencing everywhere
ancestor projection dropout isolated
child outage never silently grants parent write authority
canonical interactions always route to actual owner
```

Graphical gates:

```text
no duplicate Earth shell
no duplicate terrain patch
no duplicate base
progressive LOD replacement visually coherent
Moon/celestial background remains stable during nested local pivots
```

---

# 11. MRPF-H7 — Fault, churn and soak

H7 не добавляет новую topology; он ломает H6.

Fault matrix:

```text
EARTH projection source disconnect/reconnect
SURFACE source delay/reorder
BASE direct source dies while parent HLOD remains
SPACE source temporary loss
stale representation revision replay
same-revision mutation
manifest revision churn
route role churn PROJECTION <-> WARM <-> ACTIVE <-> DRAIN
fine artifact missing while coarse cache exists
fine artifact hash mismatch
parent cache stale after child canonical update
```

Soak target:

```text
>= 30 minutes
repeated SPACE <-> SURFACE and SURFACE <-> BASE pivots
periodic projection source churn
bounded route count
bounded queues/memory
zero split-brain
zero canonical identity changes
zero duplicate representation identities
zero unbounded artifact growth
```

---

## 12. Parallel execution map

После H0 работу можно частично распараллелить:

```text
H0 contract freeze
 |
 +--> H1 SPACE/EARTH replacement -------+
 |                                      |
 +--> H2 EARTH/SURFACE -----------------+--> H6 integration --> H7 soak
 |                                      |
 +--> H4 upward HLOD delegation --------+
 |                                      |
 +--> H5 Moon/celestial policy ---------+

H3 BASE nesting depends on H2 replacement semantics and benefits from H4 artifacts.
```

Практическое правило:

- H1 и H5 почти независимы;
- H2 можно вести параллельно H1 после H0;
- H4 может использовать synthetic BASE canonical state до H3;
- H3 собирает real nested BASE authority;
- H6 начинается только после H1/H2/H3/H4/H5 acceptance или явного documented defer;
- H7 только после H6.

---

## 13. Branch / control discipline

Эта программа является research donor, а не разрешением на uncontrolled production mutation.

Для каждого runtime checkpoint:

```text
fresh branch/worktree
bounded Work Order / design note
explicit source/base SHA
focused acceptance runner
machine-readable evidence
independent review for HIGH/CRITICAL authority changes
no merge into V0 product branch by default
```

Рекомендуемая naming схема:

```text
research/mrpf-h0-contracts
research/mrpf-h1-space-earth
research/mrpf-h2-earth-surface
research/mrpf-h3-surface-base
research/mrpf-h4-upward-hlod
research/mrpf-h5-celestial
research/mrpf-h6-integrated-hierarchy
research/mrpf-h7-fault-soak
```

Если Harness/control требует другую canonical naming — использовать Harness-generated equivalent.

---

## 14. Что переиспользовать

Обязательные donors:

```text
SM0 P8/P8.1    nested/reference-frame continuity
SM0 P10        multi-authority composer / source fencing / LOD
SM0 P11        fault/soak discipline
MRPF-P track   generic route container / direct fan-in / grants
RL3            coarse-to-fine representation streaming / content cache
MW7            regional interest projection / replacement snapshot semantics
S0/SD          spatial hierarchy/addressing
AUTHORITY       leases/epochs; never replace with presentation ownership
```

Не создавать альтернативный canonical Item Graph, Construction owner, persistence owner или network foundation.

---

## 15. Что является результатом H-линии

Принятый MRPF-H6/H7 не становится production V0 автоматически.

Его роль:

```text
accepted research evidence
        +
accepted MRPF-P donor
        +
accepted/frozen SM0 donor
        +
then-current accepted V0 P6 product baseline
        +
then-current NX/authority foundation
        ↓
V0-SM1 convergence
```

При post-P6 activation Director должен явно решить, какие H-contracts переносятся в production owners.

---

## 16. Success definition перед V0-SM1

Идеальное состояние к моменту принятия V0 P6:

```text
MRPF-P6 accepted
MRPF-H6 accepted
MRPF-H7 soak green
SM0 closed/frozen as donor evidence
```

Тогда V0-SM1 не должен исследовать базовые вопросы:

```text
может ли клиент держать N routes?
можно ли напрямую получать несколько projections?
как заменить coarse Earth на fine surface без duplicate geometry?
может ли parent показывать dormant child HLOD?
может ли Moon быть видима без прямого Moon connection?
сохраняются ли ancestor projections при nested authority pivot?
```

V0-SM1 должен заниматься переносом уже доказанных contracts в реальный V0 gameplay.

Если H6/H7 не готовы к P6, это не автоматически блокирует P6. Но post-P6 seamless activation обязан явно включить недоказанные H-gates в scope либо оформить human/main defer.

---

## 17. Final rules

```text
RUN MRPF-H IN PARALLEL WITH V0 P4->P5->P6
DO NOT CONTINUE FROZEN SM0 FOR THIS WORK
SPACE/EARTH/SURFACE/BASE ARE LOGICAL DOMAINS, NOT PERMANENT PHYSICAL MACHINES
SIMULATION AUTHORITY != PROJECTION PUBLISHER
ONE WRITER, MANY READ-ONLY REPRESENTATIONS
COARSE REPRESENTATION MAY BE SERVED BY AN ANCESTOR
FINE REPRESENTATION REPLACES COVERAGE ATOMICALLY
CHILD HLOD MAY SURVIVE CHILD COMPUTE DORMANCY
MOON MAY BE VISIBLE THROUGH SPACE WITHOUT DIRECT MOON ROUTE
DISTANCE ALONE DOES NOT DEFINE VISIBILITY
PARENT PRESENTATION NEVER IMPLIES PARENT WRITE AUTHORITY
H6/H7 ARE DONOR EVIDENCE FOR POST-P6 V0-SM1, NOT A SECOND PRODUCT TRUTH
```