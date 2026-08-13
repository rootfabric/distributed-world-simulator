# V0 Critical Path Acceleration Proposal — Networked Planetary Outpost First

**Status:** `CONTROL PROPOSAL / NOT CANONICAL UNTIL MAIN ACCEPTANCE`  
**Repository:** `rootfabric/distributed-world-simulator`  
**Proposal base:** `main @ 09714b6f2681e3b5cf3f2f9e28416cf9a7378304`  
**Architecture:** `GLOBAL-P0-2026-08-12-R3-REFRESH-R1`  
**Registry generation at base:** `79`  
**Date:** `2026-08-13`

---

## 1. Product checkpoint

Первый V0 checkpoint должен быть не subsystem-lab и не offline demo.

Он должен доказать минимальный живой сетевой мир:

```text
procedural planet
      +
network server
      +
2 clients
      +
playable characters
      +
network-visible movement
      +
canonical Construction commit
      +
replicated small outpost
      +
reconnect / persistent world state
```

Machine checkpoint to add:

```text
V0_S1_NETWORKED_PLANETARY_OUTPOST
```

Короткая продуктовая формулировка:

> Два клиента подключаются к одному серверу и одной процедурной планете. У каждого есть персонаж. Игроки видят движение друг друга. Игрок строит небольшой объект через canonical Construction path, второй клиент видит тот же результат. После reconnect canonical world state не расходится.

Это первый checkpoint, после которого проект можно оценивать как настоящий интегрированный симулятор, а не только как набор принятых foundations.

---

## 2. Почему network не должен автоматически ждать H0.2/NX.C1 acceptance

H0.2/NX.C1 уже имеет bounded source implementation:

```text
implementation head:
1814ca72c9569ea2aa7e3d1dd4a69eb790888908

lifecycle head:
d1a4466775a6e08192179dfc9af397eafbf574c0
```

Но NX.C1 runtime/source acceptance ещё не доказана.

При этом текущая canonical network runtime уже имеет существующий default locomotion profile:

```text
SERVER_PREDICTED
```

Новый профиль:

```text
OWNER_AUTHORITATIVE_VALIDATED
```

остаётся opt-in и не должен становиться обязательной зависимостью первого V0 только потому, что его verification идёт сейчас.

Поэтому V0-S1 использует сначала существующий canonical network behavior из current main.

```text
V0-S1 network baseline = current canonical SERVER_PREDICTED path

OWNER_AUTHORITATIVE_VALIDATED
  = optional experimental axis only after its exact runtime predicates allow it
```

Это сохраняет HIGH-risk NX.C1 gate без превращения его в глобальный waterfall.

---

## 3. Execution topology

Целевой route:

```text
                                  ┌─ H0.2 / NX.C1 runtime verification
                                  │          ↓
                                  │     H0_2_PASS + NX SOURCE_ACCEPTED
                                  │          ↓
R3 + post-R3 PC0 ─────────────────┼─> H0.3 (>1 mutation workers)
        │                         │
        │                         └─ optional OWNER_AUTHORITATIVE_VALIDATED axis
        │
        └─> V0-S1 NETWORKED PLANETARY OUTPOST
                    ↓
                 V0-S2
              LANDED SHIP-0
                    ↓
                 V0-S3+
           movable ship / space / handoff
```

H0.3 не является gameplay/network capability. До его acceptance сохраняется:

```text
simultaneous autonomous runtime IMPLEMENTATION workers <= 1
```

Verification/review-only activity на уже реализованной NX branch не считается вторым mutation worker.

Если NX снова входит в non-trivial FIX/runtime mutation, Director обязан сериализовать её с V0 mutation work.

---

## 4. Preconditions V0-S1

Обязательны:

```text
H0_1_PASS
C22_MAIN_INTEGRATED
GLOBAL_P0_R3_CANONICAL
POST_R3_STANDARD_PC0_NON_RED
POST_R3_DIRECTIONAL_PC0_NON_RED
CANONICAL_MAIN_KNOWN
NO_GLOBAL_PROJECT_RED
PRE_H0_3_RUNTIME_IMPLEMENTATION_WORKERS_LE_1
CANONICAL_NETWORK_RUNTIME_PRESENT
```

Не являются обязательными precondition:

```text
H0_2_PASS
NX_SOURCE_ACCEPTED
OWNER_AUTHORITATIVE_VALIDATED_ACCEPTED
H0_3_SCHEDULER_ACCEPTED
NX_C1_RUNTIME_MERGED
```

V0-S1 должен стартовать от exact then-current canonical main.

Нельзя создавать его как продолжение длинной legacy branch lineage.

---

## 5. Bounded runtime scope

V0-S1 должен **собрать**, а не переизобрести существующие owners.

```text
canonical procedural planetary surface
            +
existing dedicated/listen server runtime
            +
existing client connection/session path
            +
canonical Character/Player runtime
            +
current canonical locomotion/replication profile
            +
existing Construction placement/commit truth
            +
C22 representation/runtime path
            +
existing persistence/recovery where already canonical
```

Главная задача V0 implementation branch — composition/glue, launch mode, scenario fixtures и missing bounded adapters.

Она не получает права создавать private terrain/network/construction/player truth.

---

## 6. Exact user scenario

Acceptance runtime должен механически или операторски пройти один и тот же сценарий.

### Start

1. Запустить dedicated server V0-S1.
2. Сервер создаёт/загружает одну canonical procedural planet/world instance.
3. Подключить Client A.
4. Подключить Client B.
5. Оба клиента оказываются на одной планете в одной world/session identity.

### Character

6. У Client A есть playable character.
7. У Client B есть playable character.
8. A видит B.
9. B видит A.
10. A двигается — B получает корректное remote movement.
11. B двигается — A получает корректное remote movement.
12. Нет постоянного teleport/jitter loop, duplicate character bodies или divergent player identities.

### Construction

13. Client A входит в существующий Construction placement flow.
14. A ставит foundation/floor/wall или другой минимальный набор существующих building pieces.
15. Commit проходит через canonical server/Construction path.
16. Сервер принимает одну canonical construct mutation.
17. Client A видит подтверждённую постройку.
18. Client B получает тот же construct/revision и видит ту же постройку.
19. После replication нет private client-only building truth.
20. Client B может подойти к построенному объекту и наблюдать/коллидировать с тем же canonical result.

Минимальный outpost:

```text
1 foundation/floor
+ 2-4 walls or equivalent existing pieces
+ optional roof only if already cheap to compose
```

Checkpoint не требует развитой строительной игры. Нужен только доказанный cross-client canonical construct.

### Reconnect

21. Отключить Client B.
22. Client A остаётся в мире.
23. Подключить B снова с корректной session/player identity policy.
24. B снова видит существующий outpost без его повторного создания.
25. B видит актуальное положение/состояние A по canonical network path.

### Restart evidence

Если canonical persistence path этого runtime уже поддерживает server restart для construction/world state:

26. Завершить server runtime.
27. Запустить тот же world/session persistence fixture снова.
28. Проверить восстановление outpost.

Если текущая production persistence boundary ещё не обещает именно этот restart contract для данного Construction path, server-restart persistence фиксируется как следующий bounded checkpoint, а **reconnect persistence внутри живого server world остаётся обязательным для V0-S1**.

### Soak

29. Выполнить минимум 30 минут двухклиентного bounded soak:

```text
movement
construction observation
approach/leave area
reconnect at least once
normal camera/gameplay use
```

30. Не должно быть unbounded queue growth, repeated authority rejection loop, duplicate construct identity или canonical state corruption.

---

## 7. Required predicates

Checkpoint predicates:

```text
V0_S1_EXACT_CURRENT_MAIN_BASE
V0_S1_RISK_CLASSIFIED_HIGH
V0_S1_DESIGN_BRIEF_READY
V0_S1_SINGLE_RUNTIME_IMPLEMENTATION_WORKER_PASS

V0_S1_SERVER_BOOT_PASS
V0_S1_PROCEDURAL_PLANET_PASS
V0_S1_TWO_CLIENT_JOIN_SAME_WORLD_PASS
V0_S1_TWO_PLAYABLE_CHARACTERS_PASS
V0_S1_REMOTE_CHARACTER_VISIBILITY_PASS
V0_S1_BIDIRECTIONAL_MOVEMENT_REPLICATION_PASS

V0_S1_CONSTRUCTION_PLACEMENT_PASS
V0_S1_CANONICAL_CONSTRUCTION_COMMIT_PASS
V0_S1_SECOND_CLIENT_CONSTRUCTION_REPLICATION_PASS
V0_S1_NO_CLIENT_PRIVATE_CONSTRUCTION_TRUTH_PASS
V0_S1_CONSTRUCTION_COLLISION_CONVERGENCE_PASS

V0_S1_RECONNECT_SAME_WORLD_PASS
V0_S1_RECONNECT_CONSTRUCTION_STATE_PASS
V0_S1_30_MIN_TWO_CLIENT_SOAK_PASS

V0_S1_NO_DUPLICATE_CANONICAL_TRUTH_PASS
FULL_WORLD_CORE_REGRESSION_PASS
POST_BUILD_CRITIQUE_COMPLETED
EVIDENCE_MAP_COMPLETE
INDEPENDENT_REVIEWER_PASS
INDEPENDENT_VERIFIER_PASS
REVIEW_HEAD_EXACT_AND_FRESH
TESTED_HEADS_EXACT_AND_FRESH
STANDARD_PC0_NON_RED
DIRECTIONAL_PC0_NON_RED_FOR_CRITICAL_HITS
CRITICAL_CROSS_BRANCH_OVERLAP_ZERO
HUMAN_ATTENTION_QUEUE_EMPTY_OR_RESOLVED
DRAFT_PR_OPEN
V0_S1_CHECKPOINT_PROPOSED
```

Risk floor = `HIGH`, потому что checkpoint доказывает networked canonical mutation/composition даже если production patch в основном состоит из adapters/scene glue.

Human runtime merge gate остаётся отдельным от checkpoint proposal по существующей Harness policy.

---

## 8. Network policy for V0-S1

### Required baseline

V0-S1 использует уже присутствующий на canonical main network path.

Не требуется для первого PASS:

```text
new protocol message family
new authority foundation
cross-server authority
server handoff
new ownership registry
OWNER_AUTHORITATIVE_VALIDATED profile
```

### NX.C1 optional axis

После exact NX.C1 focused/runtime evidence один и тот же V0-S1 scenario должен стать особенно полезным A/B fixture:

```text
Profile A:
SERVER_PREDICTED

Profile B:
OWNER_AUTHORITATIVE_VALIDATED
```

Но Profile B не может считаться PASS только потому, что V0 работает на Profile A.

NX.C1 сохраняет собственные обязательные predicates:

```text
OWNER_AUTHORITY_FOCUSED_PASS
PHYSICS_PRESENTATION_SINGLE_WRITER_PASS
ITEM_ROLLBACK_PICKUP_DROP_PASS
CLIENT_TICK_FUZZ_PASS_IF_TOUCHED
FULL_WORLD_CORE_REGRESSION_PASS
TWO_CLIENT_PASS
IMPAIRED_NETWORK_PASS
RECONNECT_OWNERSHIP_EPOCH_PASS
POST_BUILD_CRITIQUE_COMPLETED
EVIDENCE_MAP_COMPLETE
INDEPENDENT_REVIEWER_PASS
REVIEW_HEAD_EXACT_AND_FRESH
TESTED_HEADS_EXACT_AND_FRESH
STANDARD_PC0_NON_RED
DIRECTIONAL_PC0_NON_RED_FOR_CRITICAL_HITS
CH_TO_NX_DIRECTIONAL_REVALIDATION_PASS
```

---

## 9. Fail-closed boundary

V0 branch не имеет права «починить сеть у себя», если для сценария нужен новый authority/network contract.

Если current canonical `SERVER_PREDICTED` path не способен закрыть V0-S1 без изменения:

```text
network protocol
locomotion authority semantics
ownership epoch semantics
reconciliation contract
canonical Character ownership
```

то результат:

```text
V0_S1_BLOCKED_REQUIRES_NX
```

и конкретный defect/requirement переводится в H0.2/NX work.

Запрещено:

```text
private V0 network protocol
private V0 movement authority
client-authoritative Construction truth
V0-only ownership epoch
special-case duplicate player registry
```

Это позволяет использовать V0 как integration detector без превращения его в новый foundation owner.

---

## 10. Construction authority boundary

Construction результат считается принятым только после canonical commit path.

Допустимая client presentation:

```text
ghost / preview
pending presentation
```

Canonical result:

```text
server accepted mutation
    -> canonical construct revision
    -> replicated representation to A and B
```

Недопустимо:

```text
A locally creates permanent building
B receives presentation-only RPC
server has no matching canonical construct revision
```

V0-S1 обязан доказать именно shared canonical construct, а не визуальную синхронизацию двух клиентов.

---

## 11. Forbidden ownership / non-goals

V0-S1 — composition consumer и не владеет:

```text
ITEM_IDENTITY_AND_GRAPH
CONSTRUCTION_TRUTH
PERSISTENCE_DURABILITY
NETWORK_REPLICATION_POLICY
AUTHORITY_FOUNDATION
CHARACTER_IDENTITY
WORLD_QUERY_FABRIC
WORLD_TRANSACTION_MODEL
SPATIAL_DOMAIN_FABRIC
MATERIAL_ONTOLOGY
WORLD_WORK_BUDGET
DEVELOPMENT_HARNESS
```

Не входят в checkpoint:

```text
ship
ship flight
orbit
planet <-> space transition
server handoff
multi-server world
terrain deformation
advanced ecology
AI population
complex inventory loop
fabrication
combat
large 100k/1M construction scale
new material ontology
```

Это намеренно маленькая вертикаль.

---

## 12. H0.3 boundary

H0.3 остаётся development scheduler checkpoint.

```text
H0.3 = safe >1 concurrent autonomous runtime mutation workers
H0.3 != network gameplay feature
H0.3 != prerequisite for one V0 runtime branch
```

До H0.3:

```text
runtime mutation workers <= 1
```

Разрешено одновременно:

```text
1 V0 implementation worker
+
NX verification/review-only activity
```

Не разрешено одновременно:

```text
V0 runtime mutation
+
NX non-trivial runtime FIX mutation
```

Director обязан сериализовать второй случай.

---

## 13. Next slices

После V0-S1:

### V0-S2 — Networked Landed Ship-0

```text
same networked planet
+ same two-client baseline
+ landed persistent ship/large construct
+ enter/exit interior
+ cargo/container only if existing canonical path composes cheaply
```

Не требует flight.

### V0-S3 — Movable Ship

```text
ship movement
player inside moving reference frame
network ownership policy
reconciliation
persistence
```

### V0-S4 — Planet <-> Space

```text
reference-frame transition
planet departure
space travel baseline
landing
```

### Later

```text
server handoff
multi-zone
large populations
ECO production integration
terrain deformation
```

---

## 14. Atomic control activation change-set

Этот proposal сам по себе ещё не меняет canonical machine route.

Activation должна быть одним согласованным control change-set от exact then-current main.

Обязательные файлы:

```text
docs/plans/H_PRIMARY_EXECUTION_ROADMAP_RU.md
  replace generic H0.3-before-any-V0 waterfall
  declare V0-S1 NETWORKED PLANETARY OUTPOST
  keep NX.C1 independent acceptance lane

docs/control/CURRENT_PROJECT_FRONTIERS_RU.md
  expose V0-S1 as first product runtime checkpoint
  show canonical SERVER_PREDICTED baseline

config/control/project-program-registry.v1.json
  bump registry generation
  update stale R3/H0.2 facts
  replace global V0_RUNTIME_START <- H0_3 block
  add V0_S1_NETWORKED_PLANETARY_OUTPOST transition
  register fail-closed V0_S1_BLOCKED_REQUIRES_NX boundary

config/control/harness/project-goals.v1.json
  add V0_S1_NETWORKED_PLANETARY_OUTPOST product goal

config/control/harness/checkpoint-catalog.v1.json
  add machine checkpoint and exact predicates from this document

config/control/harness/scheduler-policy.v1.json
  preserve pre-H0.3 mutation worker ceiling = 1
  permit NX verification-only alongside V0 implementation
  forbid V0 + NX simultaneous mutation workers

scripts/harness/checkpoint_planner.py
  support V0_S1_NETWORKED_PLANETARY_OUTPOST

tests/harness/test_v0_s1_networked_checkpoint_contract.py
  prove dependencies, non-dependencies, concurrency and fail-closed NX boundary
```

No gameplay/runtime implementation belongs in this routing activation commit.

---

## 15. Machine assertions for routing patch

Control implementation must mechanically prove:

```text
V0_S1 requires R3 + post-R3 PC0 + C22
V0_S1 requires canonical network runtime presence
V0_S1 does NOT require H0_2_PASS
V0_S1 does NOT require NX_SOURCE_ACCEPTED
V0_S1 does NOT require H0_3_SCHEDULER_ACCEPTED
V0_S1 defaults to canonical SERVER_PREDICTED network path
V0_S1 cannot introduce new network/authority foundation
V0_S1 fails closed to NX if authority/protocol changes become necessary
pre-H0.3 mutation worker ceiling == 1
NX verification-only + one V0 mutation worker is allowed
NX FIX mutation + V0 mutation simultaneously is forbidden
NX.C1 acceptance predicates remain unchanged
no architecture ownership changes
no global foundation introduced
no runtime/gameplay files changed by routing patch
Project Control NON_RED
```

---

## 16. Immediate execution after activation

После принятия control route:

```text
1. create fresh V0-S1 branch from exact then-current main
2. inventory existing planet/server/player/construction entry points
3. compose minimal server launch + V0 world fixture
4. get Client A + Client B into same procedural world
5. prove remote character movement
6. wire canonical network Construction commit/replication
7. prove shared outpost
8. reconnect B
9. run 30 min two-client soak
10. full regression + evidence + independent review
11. propose V0_S1_NETWORKED_PLANETARY_OUTPOST
```

Параллельно H0.2/NX.C1 продолжает exact runtime verification.

Если новый owner-authoritative profile становится готов, этот же V0-S1 scenario используется как реальный A/B network composition fixture вместо создания отдельного искусственного demo.

---

## 17. Product meaning of PASS

`V0_S1_NETWORKED_PLANETARY_OUTPOST PASS` означает:

> У проекта есть одна реально запускаемая процедурная планета, сервер, минимум два сетевых игрока и shared canonical строительство. Игроки могут находиться в одном мире, видеть друг друга и построить общий маленький outpost без расхождения canonical state.

Именно после этого имеет смысл быстро наращивать Ship-0, ресурсы, ECO, AI, terrain mutation и более сложную сеть внутри уже существующего живого simulator world.
