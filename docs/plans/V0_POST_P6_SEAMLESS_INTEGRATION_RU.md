# V0 Post-P6 Seamless Integration Gate

**Статус:** MAIN-OWNED FUTURE ACTIVATION PLAN / NOT YET AN ELIGIBLE HARNESS CHECKPOINT  
**Canonical owner:** `main`  
**Дата:** 2026-08-18  
**Planned checkpoint id:** `V0_SM1_SEAMLESS_PRODUCT_INTEGRATION`

## 1. Назначение

Этот документ фиксирует точку, в которой V0 должен перестать наращивать только single-server product scope и начать перенос уже доказанных SM0 multi-authority semantics в реальный playable V0.

Главное правило:

```text
P4 real-resource Construction
        ↓
P5 equipment / tools
        ↓
P6 persistent shared outpost
        ↓
POST-P6 SEAMLESS INSERTION GATE
        ↓
V0-SM1 seamless product integration
        ↓
P7 bounded terrain mutation
        ↓
P8 first mobile construct / ship
```

После принятия `V0_P6_PERSISTENT_SHARED_OUTPOST` агент/Director **не должен автоматически dispatch-ить P7**. Сначала необходимо открыть этот план, проверить activation predicates и создать main-owned control update для `V0_SM1_SEAMLESS_PRODUCT_INTEGRATION` либо получить явное human decision о переносе seamless gate.

P6 является не просто очередным gameplay checkpoint. Это первый стабильный V0 baseline, на котором уже существует законченная петля:

```text
join
→ mine
→ canonical inventory / containers
→ tools / equipment
→ build from real resources
→ shared persistent outpost
→ disconnect / reconnect
→ repeat
```

Именно такую работающую симуляцию следует распределять между authorities. Не следует одновременно изобретать базовые Item/Construction/reconnect semantics и multi-server authority transfer.

---

## 2. Почему seamless вставляется после P6, а не после P8

Если ждать P8, первый production-oriented seamless integration должен будет одновременно адаптировать:

```text
player
items / containers
tools / equipment
Construction
terrain mutation
mobile construct / ship
cross-authority routing
```

Это создаёт слишком большой mixed-risk checkpoint.

После P6 граница меньше и чище:

```text
stable playable outpost
        +
proven SM0 authority contracts
        ↓
seam-aware V0 product baseline
```

После этого P7 terrain и P8 ship уже проектируются поверх seam-aware routing/authority model, а не требуют позднего массового retrofit.

---

## 3. Что является donor evidence

Основной capability donor:

```text
PR #102
feature/sm0-two-authority-seamless-handoff-lab
```

Windows-runtime-validated SM0 FINAL carrier:

```text
b5966ef113b73e3156488805057ce9b464362d89
```

SM0 должен использоваться как **accepted/frozen evidence and capability donor**, а не как будущая production base ветка V0.

Нельзя делать:

```text
merge old SM0 lab wholesale into future P6 lineage
continue V0-SM1 from the historical SM0 branch
promote SM0 test-only owners into canonical production owners
```

Правильная модель:

```text
accepted SM0 evidence
        +
then-current accepted V0/P6 baseline
        +
then-current canonical main/control
        ↓
fresh V0-SM1 convergence branch
        ↓
minimal capability transfer
        ↓
real V0 graphical/runtime validation
```

Это следует canonical continuation rule проекта: accepted long-lived branches остаются evidence, а новый major runtime frontier начинается от актуальной canonical/product base, явно объявленной main.

---

## 4. Что переносим из SM0

Нужно переиспользовать semantics, а не копировать лабораторию целиком.

### 4.1 Authority handoff contract

```text
stable logical_player_id
stable player_entity_id
monotonic authority_epoch
exactly one active writer
source freeze
prepare target shadow
retirement proof
source retire
activate target
replay-safe completion
stale/same-epoch mutation fail-closed
```

### 4.2 Client route continuity

```text
current route
standby / warm next route
input sequence continuity
no reconnect screen during normal crossing
no respawn/new player identity
late/stale result fencing
```

### 4.3 Nested/reference-frame continuity

SM0 P8/P8.1 evidence remains relevant для будущих moving constructs:

```text
outer authority may change
inner/local identity remains stable
reference-frame presentation is derived
world transform changes must not rewrite local canonical identity
```

### 4.4 Foreign item / interaction boundary

SM0 P9 доказал необходимые semantics:

```text
direct foreign canonical mutation forbidden
foreign interaction routed to current owner
WORLD <-> SHIP transfer preserves item identity
source frozen during PREPARE
exact replay idempotent
failed commit rolls back / aborts safely
```

В V0-SM1 эти правила должны быть привязаны к **существующему canonical M4 Item Graph**, а не к SM0 synthetic item authority store.

### 4.5 Multi-authority presentation

SM0 P10 donor semantics:

```text
multiple authority projections
        ↓
one client presentation view

per-source epoch / sequence fencing
representation LOD is derived
cached/degraded representation cannot become canonical truth
one-source dropout is isolated
```

### 4.6 Fault / soak discipline

SM0 P11 donor evidence:

```text
simultaneous crossings
reorder / delay
stale owner
operation replay
peer unavailable
projection dropout
exactly one writer invariant
process-isolated soak
```

Эти сценарии должны стать основой V0-SM1 acceptance, но выполняться уже на реальном V0 gameplay composition.

---

## 5. Что НЕ переносим как production truth

Запрещено превращать лабораторные реализации SM0 в конкурирующие foundations.

Не переносить как canonical owners:

```text
SM0 synthetic item authority store
SM0 test-only directory as global production World Directory
SM0 debug ship/deck presentation
SM0 fixture-only world state
SM0 private persistence semantics
SM0 private network authority registry
```

V0-SM1 должен переиспользовать текущие production owners:

```text
NetworkedGameplayService / accepted successor
canonical player identity/ownership
canonical M4 Item Graph / accepted successor
Construction owner/transactions
existing persistence/recovery owner
current NX-owned authority/network contracts
```

Инвариант:

```text
NO SECOND GAMEPLAY TRUTH
NO SECOND ITEM GRAPH
NO SECOND CONSTRUCTION TRUTH
NO SECOND PERSISTENCE OWNER
NO PRIVATE V0 NETWORK FOUNDATION
```

---

## 6. Activation predicates после P6

`V0_SM1_SEAMLESS_PRODUCT_INTEGRATION` **не является eligible checkpoint сейчас**. Он должен быть зарегистрирован main-owned control change только после достижения P6, когда известны exact heads.

Минимальные predicates для активации:

```text
V0_P6_PERSISTENT_SHARED_OUTPOST accepted
P6 stable baseline evidence complete
  - 5 clean E2E repeats
  - 30-minute two-client soak
SM0 independent closure PASS and frozen evidence available
current NX owner-authority boundary accepted/non-blocking for this scope
no unresolved critical V0 -> NX directional hit for touched surfaces
fresh canonical main known
post-P6 standard PC0 NON_RED
post-P6 directional PC0 NON_RED for critical hits
fresh Design Brief / Work Order
CRITICAL risk routing acknowledged
human approval for cross-server authority activation
```

Не являются blanket prerequisite для первого bounded V0-SM1:

```text
production dynamic load balancing
arbitrary-many-server topology
full NATS/JetStream deployment
complete N3/N4/N5/N6 production acceptance
perfect visual smoothness
WAN latency optimization
```

Но если real implementation требует новый protocol owner, new authority foundation, reconciliation redesign или new global directory ownership, V0 должен fail closed и передать foundation change в NX/main architecture control.

---

## 7. Planned V0-SM1 scope

Первый real product integration должен быть намеренно bounded:

```text
Authority A
Authority B
one normal graphical V0 client path
second observer/player client where required
real V0 player
real canonical Item Graph
real mining
real Construction/outpost state
real reconnect/recovery
```

Минимальный product scenario:

```text
connect in A
→ move / mine
→ ore appears in canonical inventory
→ approach authority boundary
→ A -> B handoff without new player identity
→ inventory remains continuous
→ foreign/local item interactions remain authoritative
→ build/use shared outpost state in B
→ second client converges
→ B -> A handoff
→ disconnect/reconnect on either side
→ same accepted durable state
```

Hard correctness gates:

```text
same logical_player_id
same player_entity_id
monotonic authority epoch
exactly one canonical writer
no duplicate/lost item
no duplicate Construction commit
operation/replay fencing preserved
input sequence continuity
no ordinary crossing respawn/reconnect screen
A/B projection convergence
reconnect convergence
zero split-brain
zero duplicate canonical truth
```

Smoothness is a later quality gate. A bounded pause/correction may initially be tolerated if canonical correctness and identity continuity remain exact.

---

## 8. Branching rule

После P6 нельзя продолжать SM0 lineage и нельзя заранее закреплять сегодняшний P4/P6 SHA.

Director должен определить в момент активации:

```text
exact canonical main
exact accepted P6 product head
exact accepted/frozen SM0 donor boundary
exact current NX authority foundation boundary
```

После этого создаётся fresh branch, рекомендуемое имя:

```text
feature/v0-sm1-seamless-product-integration
```

или актуальный Harness-generated equivalent.

Base rule:

```text
then-current accepted P6/main-declared V0 product baseline
```

а не:

```text
historical SM0 branch
old P0 playable frontier
stale P4/P5 continuation by assumption
```

---

## 9. Network ownership rule

До отдельного accepted NX/main control change V0 сохраняет действующий network baseline.

SM0 не разрешает V0 самовольно создавать production network foundation.

Если для V0-SM1 требуется:

```text
new protocol ownership
new global authority registry
new reconciliation model
new Character ownership semantics
new production World Directory foundation
```

результат:

```text
V0_BLOCKED_REQUIRES_NX
```

а не private V0 implementation.

---

## 10. Связь с P7 и P8

P7 и P8 остаются продуктовым направлением, но после P6 получают новый входной gate.

```text
P6 accepted
    ↓
V0-SM1 decision/activation REQUIRED
    ↓
V0-SM1 accepted
    OR explicit Human/Main defer decision
    ↓
P7 bounded terrain mutation
    ↓
P8 first mobile construct / ship
```

Причина:

- P7 должен знать authority/interest boundary до того, как mutable terrain станет большой частью product state;
- P8 должен строиться поверх уже seam-aware player/item/Construction routing, а не заставлять одновременно внедрять корабль и cross-server handoff.

---

## 11. Agent routing rule

Любой Director/agent, который после P6 выбирает следующий V0 runtime checkpoint, обязан выполнить:

```text
1. Read main-owned project registry / goals / checkpoint catalog.
2. Read this document.
3. Do NOT auto-dispatch P7.
4. Resolve exact P6 / main / SM0 / NX boundaries.
5. Run fresh PC0 + directional audit.
6. Prepare CRITICAL-risk Design Brief for V0-SM1.
7. Create a main-owned control update that registers V0_SM1_SEAMLESS_PRODUCT_INTEGRATION.
8. Obtain required Human approval for cross-server authority activation.
9. Only then issue bounded V0-SM1 Work Order.
```

Если seamless activation явно отложена человеком, решение должно быть durable main-owned control/evidence, а не сообщением в чате.

---

## 12. Final rule

```text
P6 IS THE STABLE SINGLE-SERVER V0 BASELINE
P6 IS ALSO THE SEAMLESS INSERTION POINT
DO NOT AUTO-ADVANCE P6 -> P7
SM0 IS A CAPABILITY DONOR, NOT THE FUTURE PRODUCT BASE
V0-SM1 STARTS FROM THEN-CURRENT ACCEPTED V0/P6
PORT CONTRACTS, NOT LAB TRUTH
CROSS-SERVER AUTHORITY IS CRITICAL / HUMAN-GATED
NEW NETWORK FOUNDATION BELONGS TO NX/MAIN
SEAM-AWARE V0 BEFORE TERRAIN AND SHIP EXPANSION
```
