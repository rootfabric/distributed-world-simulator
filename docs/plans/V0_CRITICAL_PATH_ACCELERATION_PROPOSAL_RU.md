# V0 Critical Path Acceleration Proposal — Planetary Outpost First

**Status:** `CONTROL PROPOSAL / NOT CANONICAL UNTIL MAIN ACCEPTANCE`  
**Repository:** `rootfabric/distributed-world-simulator`  
**Proposal base:** `main @ 09714b6f2681e3b5cf3f2f9e28416cf9a7378304`  
**Architecture:** `GLOBAL-P0-2026-08-12-R3-REFRESH-R1`  
**Registry generation at base:** `79`  
**Date:** `2026-08-13`

---

## 1. Зачем меняется execution route

R3 уже canonical. H0.2/NX.C1 больше не находится в состоянии «нужно сначала спроектировать/реализовать»: bounded source implementation существует на exact head:

```text
1814ca72c9569ea2aa7e3d1dd4a69eb790888908
```

Текущий lifecycle head PR #97:

```text
d1a4466775a6e08192179dfc9af397eafbf574c0
```

NX.C1 ещё НЕ принят как runtime/source checkpoint. Для него по-прежнему обязательны exact Godot focused validation, world/core regression, two-client, impaired-network, reconnect/ownership-epoch, post-build independent review и fresh CH→NX revalidation.

Проблема текущего global execution route другая: `H0.2 -> H0.3 -> V0 runtime` делает сетевой HIGH-risk verification и development multi-worker scheduler транзитивными блокерами даже для одного bounded offline/single-player composition vertical slice.

Это создаёт process waterfall там, где V0 должен использовать scenario-specific gates.

---

## 2. Решение

Не ослаблять H0.2/NX.C1. Не принимать его по source-only evidence. Не обходить H0.3 для настоящего multi-worker runtime development.

Изменить только область действия gates:

```text
                                  ┌─ H0.2 / NX.C1 runtime verification ──> H0_2_PASS + NX SOURCE_ACCEPTED
                                  │                                         │
R3 canonical + post-R3 PC0 ──────┼─> V0-S1 PLANETARY OUTPOST ─> V0-S2 ────┼─> V0-S3 NETWORKED
                                  │                                         │
                                  └─ H0.3 after H0.2 acceptance ────────────┘
                                      required for >1 simultaneous
                                      autonomous runtime implementation worker
```

Новая семантика:

```text
H0.2/NX.C1
  gates networked V0 behavior
  DOES NOT gate V0-S1 offline composition

H0.3
  gates multiple simultaneous autonomous runtime IMPLEMENTATION workers
  DOES NOT gate one bounded V0-S1 implementation worker

H0.2 VERIFYING work
  may coexist with V0-S1 implementation
  only while NX branch performs verification/review and is not a second runtime-mutation worker
```

Если NX снова входит в non-trivial runtime mutation/FIX implementation, общий pre-H0.3 runtime implementation ceiling остаётся `1`, и Director обязан сериализовать mutation work.

---

## 3. Новый первый runtime checkpoint

Machine checkpoint to add:

```text
V0_S1_PLANETARY_OUTPOST
```

Назначение:

> Доказать, что уже существующие canonical world, Character/Player, Construction, Item Graph и Persistence могут жить в одной минимальной пользовательской симуляции без создания новой private truth.

### Preconditions

```text
H0_1_PASS
C22_MAIN_INTEGRATED
GLOBAL_P0_R3_CANONICAL
POST_R3_STANDARD_PC0_NON_RED
POST_R3_DIRECTIONAL_PC0_NON_RED
CANONICAL_MAIN_KNOWN
NO_GLOBAL_PROJECT_RED
PRE_H0_3_RUNTIME_IMPLEMENTATION_WORKERS_LE_1
```

Не являются precondition:

```text
H0_2_PASS
NX_SOURCE_ACCEPTED
H0_3_SCHEDULER_ACCEPTED
NX_MAIN_INTEGRATED
```

### Bounded runtime scope

V0-S1 должен собрать, а не переизобрести:

```text
procedural planetary surface
        +
local/offline playable character
        +
existing Construction placement/commit path
        +
small outpost
        +
existing container + Item Graph interaction
        +
existing persistence/recovery path
```

Минимальный пользовательский сценарий:

1. Запустить V0-S1 сцену/режим.
2. Появиться на процедурной поверхности планеты.
3. Передвигаться локальным игроком.
4. Поставить несколько строительных элементов и получить маленькую базу.
5. Иметь внутри/рядом один существующий container.
6. Положить предмет в container и забрать обратно.
7. Сохранить состояние.
8. Полностью завершить runtime.
9. Запустить снова.
10. Восстановить позицию/базу/container/item state через существующие canonical owners.
11. Выполнить минимум 30 минут bounded simulation soak без роста ошибок/очередей и без corruption canonical state.

### Required predicates

```text
V0_S1_EXACT_CURRENT_MAIN_BASE
V0_S1_RISK_CLASSIFIED_MEDIUM_OR_HIGH
V0_S1_DESIGN_BRIEF_READY_IF_REQUIRED
V0_S1_SINGLE_RUNTIME_IMPLEMENTATION_WORKER_PASS
V0_S1_PLANETARY_SURFACE_PASS
V0_S1_LOCAL_PLAYER_PASS
V0_S1_CONSTRUCTION_OUTPOST_PASS
V0_S1_CONTAINER_ITEM_ROUNDTRIP_PASS
V0_S1_PERSISTENCE_RESTART_RECOVERY_PASS
V0_S1_30_MIN_SIMULATION_SOAK_PASS
V0_S1_NO_DUPLICATE_CANONICAL_TRUTH_PASS
FULL_WORLD_CORE_REGRESSION_PASS
POST_BUILD_CRITIQUE_COMPLETED
EVIDENCE_MAP_COMPLETE
INDEPENDENT_REVIEWER_PASS
REVIEW_HEAD_EXACT_AND_FRESH
TESTED_HEADS_EXACT_AND_FRESH
STANDARD_PC0_NON_RED
DIRECTIONAL_PC0_NON_RED_FOR_CRITICAL_HITS
CRITICAL_CROSS_BRANCH_OVERLAP_ZERO
HUMAN_ATTENTION_QUEUE_EMPTY_OR_RESOLVED
DRAFT_PR_OPEN
V0_S1_CHECKPOINT_PROPOSED
```

Risk floor по умолчанию `MEDIUM`. Если Work Order затрагивает persistence semantics, authority, save format, public contract или canonical mutation semantics — существующая risk-policy автоматически повышает работу до `HIGH` или выше.

### Forbidden ownership/scope

V0-S1 — composition consumer. Он не может создавать или переносить ownership для:

```text
ITEM_IDENTITY_AND_GRAPH
CONSTRUCTION_TRUTH
PERSISTENCE_DURABILITY
NETWORK_REPLICATION_POLICY
AUTHORITY_FOUNDATION
WORLD_QUERY_FABRIC
WORLD_TRANSACTION_MODEL
SPATIAL_DOMAIN_FABRIC
MATERIAL_ONTOLOGY
WORLD_WORK_BUDGET
DEVELOPMENT_HARNESS
```

Также запрещено для V0-S1:

```text
new private Item Graph
new private save format
new terrain truth
new Construction truth
new Network authority semantics
NX.C1 merge or source-acceptance inference
ship flight / orbital transition
server handoff
multi-worker runtime mutation
```

---

## 4. Следующие V0 slices

### V0-S2 — Landed Ship-0

После стабильного V0-S1:

```text
planetary outpost
  +
landed ship as persistent construct/interior
  +
enter/exit
  +
container/cargo
  +
persistence/restart
```

Ship-0 ещё НЕ требует:

```text
flight
planet↔space transition
orbital mechanics
network owner authority
server handoff
```

Цель — проверить крупную конструкцию/интерьер/контейнеры и сохранение до ввода сложной динамики.

### V0-S3 — Networked Outpost / Ship Interaction

Networked slice остаётся строго gated:

```text
H0_2_PASS
NX SOURCE_ACCEPTED
required NX runtime integration/main acceptance
NET-min scenario gate
two-client + impaired-network evidence
```

Только здесь новый `OWNER_AUTHORITATIVE_VALIDATED` становится допустимой V0 experimental axis.

### V0-S4 — Movable Ship / Planet ↔ Space

После V0-S2 и нужных network/reference-frame gates:

```text
movable ship
reference-frame transitions
planet ↔ space
later docking/server handoff
```

Это НЕ должно быть частью первого V0-S1 checkpoint.

---

## 5. H0.2/NX.C1 lane остаётся без послаблений

Параллельная сеть продолжает текущую доказательную цепочку:

```text
NX.C1 source IMPLEMENTED
        ↓
exact Godot focused validation
        ↓
world/core regression
        ↓
two-client
        ↓
impaired network
        ↓
reconnect + ownership epoch
        ↓
post-build independent review
        ↓
fresh CH → NX revalidation
        ↓
H0_2_PASS + NX SOURCE_ACCEPTED
        ↓
H0.3 multi-worker scheduler eligibility
        +
V0-S3 network eligibility
```

`tested_heads` не заполняются из Project Control/source evidence.

---

## 6. H0.3 после изменения маршрута

H0.3 остаётся обязательным и полезным, но его контракт становится точнее:

```text
H0.3 = DEVELOPMENT multi-worker scheduler
H0.3 != game runtime scheduler
H0.3 != V0 composition prerequisite
```

До H0.3:

```text
simultaneous autonomous runtime IMPLEMENTATION workers <= 1
```

После H0.3 можно безопасно открывать несколько mutation work orders с ownership/path conflict prevention.

Verification/review-only activity на уже реализованной ветке не должна искусственно занимать второй runtime mutation slot.

---

## 7. Atomic control change-set required to activate this proposal

Этот документ сам по себе НЕ меняет canonical route. Для activation нужен один согласованный control change-set от exact then-current main.

Обязательные файлы:

```text
docs/plans/H_PRIMARY_EXECUTION_ROADMAP_RU.md
  remove global H0.3-before-any-V0 waterfall
  declare split H0.2 / V0-S1 / H0.3 lanes

docs/control/CURRENT_PROJECT_FRONTIERS_RU.md
  show V0-S1 as independently eligible network-free slice

config/control/project-program-registry.v1.json
  bump registry generation
  update stale post-R3/H0.2 state
  remove global V0_RUNTIME_START <- H0_3 block
  add scenario-specific V0-S1 and V0-S3 transitions
  register V0 composition frontier/eligibility without new foundation ownership

config/control/harness/project-goals.v1.json
  add V0_S1_PLANETARY_OUTPOST goal

config/control/harness/checkpoint-catalog.v1.json
  add machine V0_S1_PLANETARY_OUTPOST checkpoint and predicates

config/control/harness/scheduler-policy.v1.json
  preserve pre-H0.3 max runtime implementation workers = 1
  permit V0-S1 while H0.2 is VERIFYING/review-only
  forbid two simultaneous mutation workers

scripts/harness/checkpoint_planner.py
  support V0_S1_PLANETARY_OUTPOST
  stop returning UNSUPPORTED_CHECKPOINT for the newly declared checkpoint

tests/harness/test_v0_s1_checkpoint_contract.py
  prove machine route, non-dependencies and concurrency guard
```

Optional prose sync if required by review:

```text
docs/control/DEVELOPMENT_HARNESS_RU.md
```

No gameplay/runtime implementation belongs in the routing change-set.

---

## 8. Machine assertions for the routing patch

The control implementation must mechanically prove at least:

```text
V0_S1 depends on R3 + post-R3 PC0 + C22
V0_S1 does NOT depend on H0_2_PASS
V0_S1 does NOT depend on NX_SOURCE_ACCEPTED
V0_S1 does NOT depend on H0_3_SCHEDULER_ACCEPTED
V0_S3 DOES depend on accepted/integrated network capability
pre-H0.3 mutation worker ceiling == 1
H0.2 verification-only + V0-S1 single implementation is allowed
H0.2 runtime FIX mutation + V0-S1 mutation simultaneously is forbidden
NX acceptance predicates are byte/semantically unchanged by routing patch
no architecture ownership changes
no global foundation introduced
no runtime/gameplay files changed
Project Control NON_RED
```

---

## 9. Expected execution after activation

```text
A. H0.2 / NX.C1
   continue exact runtime verification

B. V0-S1
   create fresh current-main bounded composition branch
   build Planetary Outpost vertical slice immediately
   run restart + 30 min simulation evidence

C. H0.3
   start only after H0_2_PASS + NX SOURCE_ACCEPTED
   enable >1 autonomous runtime implementation worker

D. V0-S2
   landed Ship-0 after V0-S1 is stable

E. V0-S3
   networked slice only after NX network gates
```

Главное изменение процесса:

> После R3 новая инфраструктура проверяется внутри живого V0 мира как можно раньше; сетевые и multi-worker gates блокируют только те сценарии, которым они действительно нужны.
