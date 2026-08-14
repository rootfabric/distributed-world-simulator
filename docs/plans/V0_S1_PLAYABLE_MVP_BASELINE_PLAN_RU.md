# V0-S1 — PLAYABLE MVP BASELINE PLAN

Status: **EXECUTION PLAN / PRODUCT ACCEPTANCE BOUNDARY**

Этот документ фиксирует кратчайший путь к первому реально запускаемому сетевому MVP и ограничивает scope до вертикального среза, достаточного для проверки уже построенной системы в целом.

Он НЕ является runtime acceptance evidence сам по себе и НЕ заменяет точные Work Order / Project Control / runtime verification.

## 1. Product goal

Целевой checkpoint:

`V0_S1_NETWORKED_PLANETARY_CONSTRUCTION_MVP`

Минимальный пользовательский сценарий:

1. запускается dedicated server;
2. два графических клиента подключаются к одному live world;
3. оба находятся на одной планете в одной фиксированной тестовой локации;
4. у каждого клиента есть собственный playable character;
5. оба игрока могут двигаться и видеть движение друг друга;
6. второй клиент инициирует одну реальную Construction-команду;
7. server применяет mutation через canonical Construction commit path;
8. оба клиента видят один и тот же canonical construct;
9. второй клиент отключается и подключается обратно без создания второго мира, ghost-player или duplicate construction;
10. сценарий проходит чистые повторные прогоны и bounded soak.

После выполнения этих условий должен быть выставлен продуктовый результат:

```text
V0_S1_RUNTIME_ACCEPTED
PLAYABLE_MVP_BASELINE
```

После этого V0-S1 считается закрытым. Новые gameplay capability не должны расширять acceptance этого checkpoint задним числом.

## 2. Основной принцип scope

V0-S1 должен доказать **композицию существующих production subsystems**, а не запускать новые фундаментальные программы.

Если изменение не требуется для одного из обязательных predicates этого документа, оно не является blocker для MVP.

До `PLAYABLE_MVP_BASELINE` запрещено превращать scope в разработку:

- terrain deformation;
- mining;
- resource economy;
- crafting;
- полноценного inventory-driven construction;
- десятков building pieces;
- structural integrity;
- combat;
- AI;
- vehicles;
- ships;
- multiple planets;
- server handoff;
- нового streaming architecture;
- нового network authority profile;
- нового procedural-generation programme;
- graphical polish.

H0.3 multi-worker scheduler не является gameplay prerequisite для этого MVP. До H0.3 достаточно одного runtime mutation worker; review/verification-only работа может выполняться параллельно только в рамках действующей control policy.

## 3. Network baseline

Первый MVP использует текущий canonical:

`SERVER_PREDICTED`

`OWNER_AUTHORITATIVE_VALIDATED` / NX.C1 не является prerequisite для V0-S1.

Любое изменение protocol, authority model, reconciliation semantics или canonical Character ownership, необходимое для выполнения этого плана, должно fail closed в отдельную NX/control работу, а не незаметно раздувать V0-S1.

## 4. Exact precondition before runtime implementation

Текущий planning baseline на момент фиксации документа:

```text
main = 09714b6f2681e3b5cf3f2f9e28416cf9a7378304
PR #98 candidate = f8184472d5245afd29ef7502d150eaa127944164
```

PR #98 является control-plane activation candidate и не содержит gameplay/runtime implementation.

Перед созданием runtime Work Order после принятия #98 обязательно заново определить:

- exact canonical main;
- registry generation;
- post-main Project Control result;
- разрешённый runtime mutation slot;
- exact production entry points;
- exact canonical Godot build identity.

Нельзя использовать SHA выше как будущую runtime authorization без fresh resolution.

## 5. Critical path

```text
PR #98 ACCEPT
    ↓
post-main Project Control + fresh epoch resolution
    ↓
fresh V0-S1 runtime Work Order
    ↓
Godot runtime smoke
    ↓
dedicated server + one planetary test location
    ↓
two playable characters
    ↓
two-way SERVER_PREDICTED movement
    ↓
Client B canonical Construction command
    ↓
server/A/B persistent-state fingerprint convergence
    ↓
Client B reconnect/resync
    ↓
5 consecutive clean E2E runs
    ↓
30-minute bounded two-client soak
    ↓
V0_S1_RUNTIME_ACCEPTED
PLAYABLE_MVP_BASELINE
```

## 6. Stage 1 — Godot runtime smoke

Нужно отдельно доказать сам Godot runtime, а не только Project Control/harness.

Минимальный smoke gate:

- exact canonical Godot 4.7.1 double build;
- project import/load;
- отсутствие parser/resource errors на production entry points;
- production dedicated-server boot;
- production client boot;
- clean controlled shutdown.

Рекомендуемые единые runners:

```text
RUN_V0_RUNTIME_SMOKE.ps1
RUN_V0_RUNTIME_SMOKE.sh
```

После локального подтверждения тот же smoke должен стать отдельным CI gate рядом с Project Control.

Required predicates:

```text
GODOT_RUNTIME_SMOKE_PASS
SERVER_BOOT_PASS
CLIENT_BOOT_PASS
```

## 7. Stage 2 — one planet, one bounded test location

V0-S1 не должен ждать нового поколения procgen.

Использовать существующий production world/planet path и зафиксировать:

```text
V0_WORLD_SEED
V0_PLANET_ID
V0_TEST_LOCATION
V0_SPAWN_A
V0_SPAWN_B
V0_BUILD_ANCHOR
```

Нужны только следующие свойства:

- одна одинаковая планета у server/A/B;
- одна готовая область поверхности;
- collision;
- gravity;
- два spawn point рядом;
- deterministic identity для теста.

Required predicates:

```text
SAME_WORLD_ID_PASS
SAME_PLANET_PASS
TEST_LOCATION_READY_PASS
TERRAIN_COLLISION_PASS
```

## 8. Stage 3 — two playable characters

Для каждого peer должна существовать однозначная цепочка:

```text
peer/session
  -> player identity
  -> character entity
  -> movement body
  -> local input/camera only for owner
```

Обязательные инварианты:

```text
active_player_count == 2
controlled_character(A) != controlled_character(B)
```

Remote character не может получать local input/camera authority.

Для MVP не требуются финальная модель, animation graph, stamina, equipment и gameplay UI.

Required predicates:

```text
TWO_PLAYERS_PASS
LOCAL_OWNERSHIP_PASS
NO_REMOTE_INPUT_PASS
LOCAL_CAMERA_PASS
```

## 9. Stage 4 — two-way movement

Использовать существующий `SERVER_PREDICTED` path.

Нужно доказать оба направления:

```text
A input -> server -> A + B projection
B input -> server -> A + B projection
```

Required predicates:

```text
PLAYER_A_MOVEMENT_PASS
PLAYER_B_MOVEMENT_PASS
BIDIRECTIONAL_REMOTE_VISIBILITY_PASS
NO_DUAL_POSITION_WRITER_PASS
```

Идеальная latency compensation и новый reconciliation profile не входят в этот stage.

После этого stage уже существует первая playable network build: два человека могут одновременно находиться и двигаться в одном planetary world.

## 10. Stage 5 — one canonical construction

Construction должна инициироваться **вторым удалённым клиентом**, а не server-side test helper.

Обязательный путь:

```text
Client B action
  -> network command
  -> server validation/authorization
  -> canonical Construction commit path
  -> canonical world revision
  -> replication
  -> Client A + Client B projection
```

Construction scope намеренно минимален.

Допустим один фиксированный test blueprint или минимальный набор canonical Construction elements в `V0_BUILD_ANCHOR`.

До MVP не требуются:

- ghost placement UI;
- snapping UX;
- rotation UX;
- resources/cost;
- crafting;
- inventory requirement;
- demolition;
- building catalogue.

### Minimal duplicate safety

Единственная обязательная command-hardening проверка до MVP: повторная доставка того же `command_id` не должна создавать второй construct.

Required predicates:

```text
CLIENT_B_CONSTRUCTION_COMMAND_PASS
CANONICAL_CONSTRUCTION_COMMIT_PASS
ONE_CONSTRUCTION_ONLY_PASS
CLIENT_A_CONSTRUCTION_VISIBLE_PASS
CLIENT_B_CONSTRUCTION_VISIBLE_PASS
SAME_CONSTRUCT_ID_PASS
SAME_CONSTRUCT_REVISION_PASS
DUPLICATE_COMMAND_NO_DUPLICATE_PASS
```

Полная матрица stale/invalid/unauthorized/malformed commands выполняется после MVP, если она не требуется для исправления реального V0-S1 defect.

## 11. Stage 6 — bounded canonical state fingerprint

Для первого MVP нужен маленький deterministic fingerprint, а не новый универсальный serialization programme.

Fingerprint должен включать только устойчивое canonical state, нужное для V0-S1:

```text
world_id
planet_id
world_revision
player identity set
construct_id
construct type
construct canonical transform
construct revision
```

Перед hashing:

- deterministic field order;
- deterministic entity ordering;
- canonical serialization;
- SHA-256 или другой уже canonical deterministic digest mechanism.

На synchronisation checkpoint:

```text
server_fingerprint == client_a_fingerprint == client_b_fingerprint
```

Realtime moving character transforms не должны обязательно входить в этот digest: их корректность проверяется отдельными movement predicates, чтобы нормальная snapshot latency не создавала ложный divergence.

Required predicate:

```text
CANONICAL_V0_STATE_FINGERPRINT_PASS
```

## 12. Stage 7 — reconnect/resync

Reconnect остаётся частью MVP, потому что он дёшево проверяет, что live world действительно server-authoritative и не создаёт вторую истину.

Sequence:

```text
server + A + B
  -> movement
  -> B creates construction
  -> convergence checkpoint
  -> B disconnect
  -> A and server continue
  -> B reconnect
  -> resync
  -> convergence checkpoint
```

После reconnect:

```text
active_players == 2
construction_count == 1
world_id unchanged
construct_id unchanged
construct revision canonical
fingerprint converged
```

Required predicates:

```text
RECONNECT_PASS
NO_GHOST_PLAYER_PASS
NO_DUPLICATE_CONSTRUCTION_PASS
POST_RECONNECT_CONVERGENCE_PASS
```

## 13. Stage 8 — one executable E2E acceptance runner

После ручного functional PASS должен существовать один основной acceptance runner, а не набор несвязанных ручных инструкций.

Recommended names:

```text
RUN_V0_S1_MVP.ps1
RUN_V0_S1_MVP.sh
```

Минимальная последовательность runner:

1. создать fresh temporary runtime/world state;
2. запустить server и дождаться `READY`;
3. запустить Client A и дождаться `JOINED`;
4. запустить Client B и дождаться `JOINED`;
5. проверить world/planet identity;
6. выполнить движение A и доказать projection на B;
7. выполнить движение B и доказать projection на A;
8. Client B выполняет canonical Construction action;
9. доказать ровно один construct на server/A/B;
10. сравнить canonical V0 fingerprints;
11. отключить B;
12. подключить B заново;
13. доказать отсутствие ghost-player/duplicate construct;
14. снова сравнить fingerprints;
15. сохранить structured evidence;
16. корректно завершить процессы.

Required artifacts:

```text
server.log
client_a.log
client_b.log
v0_s1_result.json
v0_s1_summary.txt
```

Evidence обязательно содержит:

```text
source_sha
godot_build
world_id
seed
final_revision
final_fingerprint
```

## 14. Repetition gate before MVP acceptance

До первого MVP не требуется 20–50 clean runs.

Required initial gate:

```text
5 consecutive fresh E2E runs
```

Любой functional/flaky failure сбрасывает серию. После исправления серия начинается заново.

После пяти последовательных PASS выполнить:

```text
30-minute two-client bounded soak
```

Во время soak должны оставаться истинными минимум:

- оба клиента остаются подключаемыми и управляемыми;
- movement path продолжает работать;
- canonical construction не дублируется и не исчезает;
- выполняется как минимум один reconnect;
- server остаётся healthy/ready;
- нет fatal/script/runtime invariant errors;
- нет очевидного unbounded queue/entity growth.

Required predicates:

```text
5_CONSECUTIVE_E2E_PASS
30_MIN_SOAK_PASS
```

20/50-run determinism, impaired-network matrix и расширенный soak являются post-MVP hardening, а не блокером первого `PLAYABLE_MVP_BASELINE`.

## 15. Final MVP acceptance contract

Минимальный machine/human-readable результат:

```text
V0_S1_RUNTIME_ACCEPTED

SOURCE_SHA=<exact runtime target>
GODOT_BUILD=<exact canonical build>
WORLD_SEED=<fixed seed>

GODOT_RUNTIME_SMOKE_PASS
SERVER_BOOT_PASS

TWO_CLIENT_JOIN_PASS
SAME_WORLD_PASS
TWO_PLAYERS_PASS

PLAYER_A_MOVEMENT_PASS
PLAYER_B_MOVEMENT_PASS
BIDIRECTIONAL_REMOTE_VISIBILITY_PASS
NO_DUAL_POSITION_WRITER_PASS

CLIENT_B_CONSTRUCTION_COMMAND_PASS
CANONICAL_CONSTRUCTION_COMMIT_PASS
ONE_CONSTRUCTION_ONLY_PASS
DUPLICATE_COMMAND_NO_DUPLICATE_PASS

CANONICAL_V0_STATE_FINGERPRINT_PASS

RECONNECT_PASS
NO_GHOST_PLAYER_PASS
POST_RECONNECT_CONVERGENCE_PASS

5_CONSECUTIVE_E2E_PASS
30_MIN_SOAK_PASS

NO_FATAL_RUNTIME_ERRORS_PASS

PLAYABLE_MVP_BASELINE
```

Ни один predicate нельзя объявлять PASS по source review, Project Control или design evidence вместо фактического runtime execution.

## 16. Suggested implementation increments

Чтобы не создавать новый waterfall, runtime work рекомендуется удерживать в четырёх узких инкрементах.

### Increment A — production multiplayer boot

Scope:

- Godot runtime smoke;
- dedicated server production boot;
- graphical client production boot;
- bounded planetary test location;
- two character spawn;
- local input/camera ownership.

Exit:

```text
SERVER + CLIENT A + CLIENT B
same planetary location
both characters present
```

### Increment B — two-player movement

Scope:

- existing `SERVER_PREDICTED` integration;
- A movement;
- B movement;
- remote presentation;
- single-writer checks.

Exit:

```text
TWO_PLAYER_PLAYABLE_BUILD
```

### Increment C — canonical construction

Scope:

- Client B build request;
- canonical Construction commit;
- replication to A/B;
- one fixed simple structure;
- V0 state fingerprint;
- minimal duplicate command protection.

Exit:

```text
NETWORKED_CONSTRUCTION_VERTICAL_SLICE_PASS
```

### Increment D — reconnect and acceptance

Scope:

- reconnect/resync;
- executable E2E runner;
- five clean consecutive runs;
- 30-minute soak;
- runtime CI wiring;
- evidence package.

Exit:

```text
V0_S1_RUNTIME_ACCEPTED
PLAYABLE_MVP_BASELINE
```

## 17. Explicit post-MVP work

Следующие capability должны начинаться **после** `PLAYABLE_MVP_BASELINE`, используя уже доказанный двухклиентный мир как постоянную integration fixture:

1. cold server restart + persistence proof;
2. stale/invalid/unauthorized command hardening;
3. impaired-network validation;
4. mining / terrain mutation;
5. inventory-driven interaction;
6. manual construction UX;
7. containers;
8. resource/crafting loops;
9. simple vehicle;
10. first ship;
11. larger streaming/handoff/scale work по мере появления реального gameplay pressure.

Принцип дальнейшей разработки:

```text
PLAYABLE MVP
  -> add one gameplay capability
  -> execute it through real server + two-client world
  -> prove convergence/reconnect
  -> keep it
```

Иными словами, после V0-S1 архитектура должна в первую очередь обслуживать gameplay, а следующие gameplay scenarios — выявлять реальные архитектурные проблемы.

## 18. Product boundary decision

Этот документ фиксирует ключевое решение:

> До первого MVP проект оптимизируется не под максимальную полноту архитектуры, а под минимальный доказанный вертикальный сетевой срез.

Достаточная первая точка:

```text
one planetary location
+ dedicated server
+ two players
+ two-way movement
+ one client-authored canonical construction
+ reconnect
= PLAYABLE_MVP_BASELINE
```

Все дальнейшие усложнения строятся от этой работающей точки.