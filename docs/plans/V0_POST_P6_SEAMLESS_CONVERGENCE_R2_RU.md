# V0 Post-P6 Seamless Convergence R2

**Статус:** MAIN-OWNED FUTURE ACTIVATION PLAN / NOT YET AN ELIGIBLE HARNESS CHECKPOINT  
**Canonical owner:** `main`  
**Дата:** 2026-08-20  
**Planned checkpoint:** `V0_SM1_SEAMLESS_PRODUCT_INTEGRATION`  
**Machine contract:** `config/control/harness/v0-post-p6-seamless-convergence.v1.json`

## 0. Назначение

Этот документ нормализует post-P6 seamless plan после появления Seamless World R2 и pre-P6 incubation train.

Он не активирует SM1, не меняет P5/P6 runtime, не передаёт ownership и не делает research-ветки production base.

Если более ранний `V0_POST_P6_SEAMLESS_INTEGRATION_RU.md` читается так, будто production convergence строится только как `SM0 + MRPF + P6`, эта интерпретация считается устаревшей. Исторический документ остаётся полезным источником сценариев и требований, но текущая donor-иерархия определяется этим R2 plan и его machine contract.

Главная продуктовая последовательность остаётся неизменной:

```text
P5 equipment/tools
        ↓
P6 persistent shared outpost
        ↓
POST-P6 SEAMLESS INSERTION GATE
        ↓
ACTIVATE_V0_SM1 ?
   /          \
 no            yes
 ↓              ↓
P7        fresh V0-SM1 convergence
                ↓
               P7
                ↓
               P8
```

После acceptance P6 нельзя автоматически dispatch-ить P7. Сначала должен быть durably recorded `ACTIVATE_V0_SM1` или `DEFER_V0_SM1_WITH_EXPLICIT_HUMAN_DECISION`.

---

## 1. Каноническая convergence-модель

После P6 production convergence собирается из пяти разных классов входов:

```text
accepted P6 product baseline
        +
accepted Seamless R2 incubation semantics
        +
frozen SM0 scenario/evidence donor
        +
accepted/usable MRPF projection donor
        +
current NX production network foundation
        ↓
fresh V0-SM1 production branch
        ↓
minimal intentional capability transfer
        ↓
real V0 runtime / graphical / fault validation
```

Ни один research donor не становится production base автоматически.

Production base всегда:

```text
then-current accepted P6 product lineage
as explicitly declared by main-owned control
```

---

## 2. Роли программ и доноров

### 2.1 V0 / accepted P6 — production execution base

P6 предоставляет реальный product state, который распределяется между authorities:

```text
player identity
canonical inventory / containers
equipment / tools
mining/resource flow
Construction / shared outpost
persistence / restart
reconnect convergence
```

SM1 не создаёт альтернативную копию этих foundations.

### 2.2 Seamless World R2 — semantic authority donor

Seamless R2 является главным semantic donor для новой production multi-authority архитектуры.

Ключевые concepts:

```text
Ownership Directory
OwnershipRecord
AuthorityIncarnation
AuthorityEpoch
FencingToken
DirectoryGeneration
AuthorityDomain
AuthorityBinding
DomainMutationBarrier
PlayerAuthorityDomain
InteractionIsland
Edge Gateway as non-authoritative routing/session layer
```

Research implementation остаётся donor-only. В production переносятся contracts, algorithms, tests и проверенные invariants, а не research lineage wholesale.

### 2.3 SM0 — historical scenario/evidence donor

SM0 остаётся доказательством важных сценариев:

```text
stable identity across A<->B
single writer
epoch fencing
freeze/prepare/retire/activate lessons
nested/reference-frame continuity
foreign item boundary
multi-authority presentation
fault matrix / process-isolated soak
```

SM0 не является production World Directory, production network foundation или future V0 base.

### 2.4 NX — production network foundation owner

NX или его accepted main-owned successor владеет production network foundation surfaces:

```text
protocol ownership
connection/session transport
input sequencing
prediction/reconciliation
network authority contracts
transport envelopes
network health/backpressure
```

SM1 не создаёт private V0 network foundation.

Если SM1 требует новый protocol owner, reconciliation foundation, global transport authority или иной NX-owned foundation change, результат должен быть:

```text
V0_BLOCKED_REQUIRES_NX_OR_MAIN_ARCHITECTURE
```

а не branch-private implementation.

### 2.5 MRPF — projection/topology donor

MRPF отвечает за presentation/projection questions:

```text
generic N-route projection model
hierarchical macro/detail composition
ProjectionManifest / ProjectionGrant
multi-scale visibility / LOD
source fencing / dropout isolation
connection-budget-aware projection topology
```

MRPF не является canonical gameplay owner и не должен становиться blanket blocker всего SM1.

---

## 3. Нормативное разделение foundations

```text
OWNERSHIP / MIGRATION
    Seamless R2 contracts -> production SM1

GAMEPLAY CANONICAL STATE
    accepted V0/P6 owners

TRANSPORT / PREDICTION / RECONCILIATION
    NX / accepted successor

PRESENTATION / PROJECTION
    MRPF-derived read-only model

COMMAND / SESSION ROUTING
    non-authoritative Edge Gateway layer
```

Hard rule:

```text
ONE FOUNDATION PER CANONICAL QUESTION
NO SECOND GAMEPLAY TRUTH
NO SECOND ITEM GRAPH
NO SECOND CONSTRUCTION TRUTH
NO SECOND PERSISTENCE OWNER
NO SECOND OWNERSHIP ORACLE
NO PRIVATE V0 NETWORK FOUNDATION
```

---

## 4. Transport topology decision

R2 Gateway и MRPF direct projection не являются конкурирующими архитектурами. Целевая форма — hybrid control/data plane.

### 4.1 Canonical command/session plane

Целевой production ingress:

```text
Client
  │
  └── stable command/session path ──> Edge Gateway
                                      │
                                      ├── ACTIVE authority route
                                      ├── WARM authority route(s)
                                      └── DRAIN/DEGRADED route(s)
```

Gateway:

- не решает canonical ownership;
- не удовлетворяет ownership authorization;
- не становится Item Graph/Construction/persistence owner;
- меняет route role только в соответствии с accepted ownership transition;
- сохраняет logical client/session continuity там, где это поддерживается текущим NX contract.

### 4.2 Projection data plane

Read-only projection может идти напрямую от authorized publisher к клиенту:

```text
ProjectionPublisher A ─────> Client
ProjectionPublisher B ─────> Client
Earth/Macro Publisher ─────> Client
Celestial Publisher ───────> Client
```

При этом:

```text
projection != authority
projection route != mutation capability
projection cache != canonical state
```

Active gameplay authority не обязан быть relay для всего view traffic соседей.

### 4.3 Handoff route pivot

Предпочтительная форма:

```text
before:
    A = ACTIVE
    B = PROJECTION/WARM

commit:
    accepted ownership transition

pivot:
    A = DRAIN
    B = ACTIVE

settled:
    A = PROJECTION or DISCONNECTED
    B = ACTIVE
```

Обычное crossing не должно требовать new player identity, respawn или обязательного transport reconnect в точке ownership pivot.

---

## 5. Pre-P6 порядок research-работ

P5/P6 product train продолжает идти независимо. Seamless research остаётся donor-only и не блокирует P5/P6 сам по себе.

Приоритет до P6:

```text
1. Close I2 at the reviewed I2.6 boundary
   unless fresh review finds a concrete blocker.

2. I3 — Generic AuthorityDomain Transfer
   Directory-backed transfer with no old-source resurrection after commit.

3. I4 — Player Carrying Domain
   player + inventory + hotbar + equipment + nested carried Item Graph closure.

4. Start/maintain I8 Production Port Map early
   instead of waiting until all incubation work is finished.

5. Continue MRPF only as bounded projection donor work.

6. Perform NX <-> SM1 ownership audit before P6 acceptance/activation decision.
```

Не следует бесконечно расширять I2 новыми sub-checkpoints после того, как one-writer Directory/fencing contract закрыт. Следующий semantic risk находится в domain transfer и реальной carried-state closure.

---

## 6. Production Port Map

Для каждого incubation component до production activation должна существовать одна из классификаций:

```text
PORT_AS_IS
PORT_WITH_ADAPTER
REIMPLEMENT_FROM_CONTRACT
KEEP_RESEARCH_ONLY
DISCARD
```

По умолчанию research code не считается production-ready только потому, что tests проходят.

Особенно для Directory/fencing прототипов предпочтительно сначала доказать contract portability и ownership integration с текущими production owners, а затем выбрать `PORT_WITH_ADAPTER` или `REIMPLEMENT_FROM_CONTRACT`.

---

## 7. Exact inputs обязательны в post-P6 activation gate

Непосредственно перед `ACTIVATE_V0_SM1` main-owned control обязан разрешить exact boundaries:

```text
1. exact canonical main
2. exact accepted P6 product head / declared successor base
3. exact accepted Seamless R2 incubation donor boundary
4. exact frozen SM0 evidence donor boundary
5. exact accepted/usable MRPF donor boundary, if available
6. exact current NX production network foundation boundary
```

Нельзя заранее закреплять сегодняшние P5/P6 research SHA как future production base.

Если MRPF не закрыт полностью, это не автоматический blocker. Design Brief должен либо включить недостающий bounded projection contract/test scope, либо main/human должен явно defer соответствующую часть.

---

## 8. Fresh production branch rule

При activation создаётся fresh branch:

```text
feature/v0-sm1-seamless-product-integration
```

или Harness-generated equivalent.

Base:

```text
exact accepted P6/main-declared V0 product baseline
```

Запрещено:

```text
start production SM1 from SM0 branch
start production SM1 from Seamless research branch
start production SM1 from MRPF branch
wholesale merge any donor lineage into P6
promote research synthetic owners into production owners
```

Donor SHA используется как evidence/provenance input, не как branch ancestry requirement.

---

## 9. Production SM1 milestone direction

После activation production sequence следует R2 semantic order:

```text
H0   Production seamless contracts
H1   Durable Ownership Directory integration
H2   Generic AuthorityDomain transfer
H2A  AuthorityBinding + domain closure
H2B  Player Carrying Domain
H3   Single Edge Gateway transparency
H4   PRIMARY/OBSERVER/WARM routing
H5   Gateway-mediated PlayerAuthorityDomain handoff
H6   Multi-region gateway selection
H7   Gateway rehome/failure
H8   Projection / AOI integration
H9   Cross-authority operation foundation
H10  InteractionIsland runtime
H11  Static N-authority world
H12  Integrated static seamless acceptance
```

Только после H12 допускается отдельная dynamic program для placement/split/merge.

---

## 10. First bounded V0-SM1 product scenario

Первый integration slice должен использовать настоящие P6 owners:

```text
connect in A
→ move / mine
→ canonical ore enters inventory
→ use/equip tool
→ receive allowed foreign/macro projections
→ approach authority boundary
→ B becomes WARM
→ ownership transition A -> B
→ same player identity
→ same carried ItemIds
→ inventory/equipment remains continuous
→ build/use shared outpost state in B
→ second client converges
→ B -> A
→ disconnect/reconnect on either side
→ same durable canonical state
```

Hard correctness gates:

```text
exactly one canonical writer
stable logical_player_id
stable player_entity_id
stable carried ItemIds
stale old authority mutation accepted = 0
duplicate item ids = 0
lost item ids = 0
duplicate Construction commits = 0
projection canonical writes = 0
canonical revision rollback = 0
ordinary crossing respawn/reconnect = 0
```

Visual smoothness измеряется отдельно и не может маскировать authority/state correctness.

---

## 11. Что этот plan НЕ разрешает сейчас

На текущей product стадии этот документ не разрешает:

```text
production SM1 activation
P6 activation before P5 acceptance
P7 dispatch before post-P6 decision
production Gateway runtime
production World Directory replacement
NX ownership mutation
wholesale research merge
dynamic split/merge/load balancing
```

До post-P6 gate разрешены только bounded donor-only research, reviews, tests, port maps и ownership audits в рамках их собственных control rules.

---

## 12. Recovery rule

Fresh agent должен читать в таком порядке:

```text
config/control/harness/v0-product-train-policy.v1.json
config/control/harness/v0-post-p6-seamless-convergence.v1.json
this document
V0_POST_P6_SEAMLESS_INTEGRATION_RU.md   # historical/current scenario context
V0_MULTI_ROUTE_PROJECTION_FABRIC_RU.md # projection companion
current Seamless R2 pointer/roadmap
current NX control boundary
```

Machine/control state имеет приоритет над prose и chat history.
