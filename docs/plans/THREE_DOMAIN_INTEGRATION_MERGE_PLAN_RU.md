# Корректирующий план объединения сети, предметов/строительства и изменяемой поверхности

**Дата решения:** 3 августа 2026 года  
**Репозиторий:** `rootfabric/distributed-world-simulator`  
**Назначение:** зафиксировать уровни остановки трёх активных направлений и безопасный порядок их объединения в одну дальнейшую линию разработки.

## 1. Решение

Три активные линии разработки продолжаются независимо только до следующих контрольных точек:

```text
Construction / Items: C24 ACCEPTED
Network:              NX6 ACCEPTED
Matter / Surface:     MW10 + RL3 ACCEPTED
```

После достижения этих уровней независимое функциональное развитие веток останавливается. Дальнейшие крупные этапы выполняются только поверх общей интеграционной базы.

Целевая композиция:

```text
C24
+ NX6
+ MW10
+ RL3
= Three-Domain Integration Base
```

## 2. Почему выбраны именно эти уровни

### 2.1 Construction / Items — остановка на C24

C24 завершает необходимую перед интеграцией вертикаль предметов и строительства:

- Item Graph и `ConstructSnapshot` остаются источниками истины;
- строительство выполняется через authoritative operations;
- имеются multiplayer commands, exact replay и optimistic fences;
- реализованы distributed construction authority и handoff;
- крупные конструкции получают shell/section/interior HLOD;
- конструкция из 10 000 частей не раскрывает все дочерние identities дальнему клиенту;
- C24 материализует реальные `ArrayMesh`-proxy, packed buffers и shared GPU cache;
- C23 добавляет production hardening, recovery, security и bounded observability.

Текущая ветка:

```text
feature/c24-gpu-ready-proxy-mesh-backend
```

Условие остановки:

```text
C24 independent acceptance PASS
C23 regression PASS
C22 regression PASS
C2B Item Graph regression PASS
C9 damage regression PASS
Network N0–M4 regression PASS
World regression PASS
Main-scene gate PASS
Git diff check PASS
```

После принятия C24:

- поставить checkpoint/tag;
- зафиксировать head commit;
- заморозить ветку для новых функций;
- разрешать только критические исправления, которые затем обязательно переносятся в интеграционную ветку.

До объединения не начинать отдельный C25. Triangle decimation, impostors, production material catalog, surface attachments и дальнейший HLOD должны развиваться уже в общей ветке.

### 2.2 Network — остановка на NX6

Текущая ветка:

```text
feature/nx2-realtime-traffic-separation
```

До интеграции сеть должна пройти:

```text
NX3 Fixed-Tick Authoritative Simulation
→ NX4 Client Prediction and Reconciliation
→ NX5 Remote Player Interpolation
→ NX6 Predicted Item Interactions
```

#### NX3 — Fixed Tick

Обязательные результаты:

- authoritative movement на фиксированном server tick;
- packet arrival time не используется как simulation delta;
- per-player input queue;
- sequence window и input age limits;
- `last_processed_input_sequence`;
- deterministic recovery при loss/reorder;
- jump и другие transitions передаются как edges.

#### NX4 — Prediction and Reconciliation

Обязательные результаты:

- единый movement kernel для server и predicted client path;
- bounded input/state ring buffer;
- немедленная локальная реакция;
- authoritative correction;
- replay неподтверждённых inputs;
- bounded smoothing и correction telemetry.

#### NX5 — Remote Interpolation

Обязательные результаты:

- snapshot buffer;
- server-tick render timeline;
- interpolation delay;
- bounded extrapolation;
- teleport/reset marker;
- корректное отображение remote movement modes.

#### NX6 — Predicted Item Interactions

Обязательные результаты:

- pending pickup presentation;
- optimistic inventory transaction;
- predicted drop с `prediction_id`;
- local placement ghost;
- server-confirmed canonical spawn;
- deterministic rejection rollback;
- отсутствие дубликатов и unresolved predictions.

NX6 выбран как точка остановки, потому что он завершает полный gameplay gate персонажа и предметов. После него сеть уже способна принять construction и matter traffic без переделки базовой клиентской модели.

После принятия NX6:

- поставить checkpoint/tag;
- зафиксировать head commit;
- заморозить ветку для новых функций.

До объединения не выполнять NX7–NX9 отдельно. Physics authority, общий interest management и production persistence обязаны учитывать конструкции, matter regions и representation artifacts, поэтому разрабатываются только после merge.

### 2.3 Matter / Surface — остановка на MW10 + RL3

Текущая ветка:

```text
feature/rl1-matter-summary-pyramid
```

До интеграции поверхность должна пройти:

```text
RL1 acceptance
→ MW9 Durable Distributed Handoff
→ MW10 Cross-Region Matter Transactions
→ RL2 Matter Multiresolution Meshing
→ RL3 Representation-Aware Network Artifact Streaming
```

#### MW9 — Durable Distributed Handoff

Обязательные результаты:

- durable authority directory;
- lease timeout;
- fencing token;
- transfer journal;
- crash-safe `PREPARING/COMMIT` transition;
- split-brain rejection;
- exact replay после recovery.

#### MW10 — Cross-Region Transactions

Обязательные результаты:

- deterministic region ordering;
- prepare/commit/rollback;
- distributed mass ledger;
- exact operation replay;
- atomic revision frontier;
- representation invalidation только после global commit.

#### RL2 — Multiresolution Meshing

Обязательные результаты:

- coarse SDF levels;
- regional и macro meshes;
- cross-level transitions без cracks;
- local ancestor rebuild;
- collision promotion для близкой области;
- bounded rebuild fan-out.

#### RL3 — Network Artifact Streaming

Обязательные результаты:

- representation-aware subscriptions;
- artifact manifests;
- content-addressed transfer;
- progressive coarse-first loading;
- cancellation при смене interest;
- per-client memory и bandwidth budgets;
- reconnect cache reuse;
- stale artifact rejection и resync.

RL3 выбран как точка остановки, потому что после него поверхность имеет тот же необходимый уровень зрелости, что C24: authority, persistence, HLOD/mesh representation и сетевую доставку производных artifacts.

После принятия MW10 и RL3:

- поставить checkpoints/tags;
- зафиксировать head commit;
- заморозить ветку для новых функций.

До объединения не выполнять RL4 и последующие этапы отдельно. Существующий C24 backend должен подключаться к общим representation contracts, а не дублироваться новым construction HLOD.

## 3. Правила заморозки веток

После достижения целевого checkpoint для каждого направления:

1. Зафиксировать точный head SHA.
2. Записать checkpoint, build ID, branch и результаты тестов.
3. Запретить новые функциональные этапы на старой ветке.
4. Разрешить только блокирующие fixes.
5. Каждый fix обязан иметь отдельный commit и список затронутых файлов.
6. Fix после начала интеграции одновременно переносится в общую ветку.
7. Не переписывать историю и не выполнять force-push.
8. Не merge-ить старые ветки напрямую в `main` по отдельности.

## 4. Интеграционная ветка

После достижения всех трёх уровней создать ветку:

```text
integration/c24-nx6-mw10-rl3
```

Базой выбрать актуальный `main` на момент начала интеграции.

Перед merge зафиксировать manifest:

```text
main_base_sha
construction_branch
construction_head_sha
network_branch
network_head_sha
matter_branch
matter_head_sha
required_checkpoints
required_test_profiles
```

## 5. Порядок merge

Рекомендуемый порядок:

```text
main
→ Network NX6
→ Matter MW10 + RL3
→ Construction C24
→ Integration adapters and conflict resolution
```

### 5.1 Сначала Network NX6

Причина:

- сеть определяет общий runtime и physical/logical transport boundary;
- NX3–NX6 меняют M3 server/client runtime;
- остальные домены должны подключаться к уже стабильным fixed-tick, prediction и item interaction semantics.

После merge NX6 выполнить полный сетевой профиль до добавления остальных веток.

### 5.2 Затем Matter MW10 + RL3

Причина:

- matter уже использует существующие command/replication envelopes;
- RL3 должен быть подключён к логическим traffic classes NX6;
- поверхность затрагивает M3 graphical runtime и replica stores, но меньше зависит от construction UI.

После merge matter-ветки выполнить:

- полный NX0–NX6 regression;
- MW0–MW10 regression;
- RL0–RL3 regression;
- dedicated server + два клиента;
- reconnect/full-resync;
- network-condition profiles.

### 5.3 Затем Construction C24

Причина:

- construction опирается на Item Graph и predicted placement NX6;
- C24 artifacts должны подключаться к уже существующему RL3 streaming boundary;
- construction имеет наибольшее число общих runtime и regression runner изменений, поэтому добавляется после стабилизации сети и matter.

После merge C24 выполнить полный combined regression, не выбирая одну версию общих runtime-файлов целиком.

## 6. Общие файлы нельзя разрешать стратегией `ours/theirs`

Особое внимание требуется к:

```text
scripts/runtime/networked_gameplay/m3/m3_graphical_client_runtime.gd
scripts/runtime/networked_gameplay/m3/m3_dedicated_server_runtime.gd
scripts/items/presentation/item_gameplay_controller.gd
scripts/runtime/host_client/multiplayer_gameplay_replica_store.gd
scripts/app/simulator_app.gd
RUN_WORLD_REGRESSION_TESTS.ps1
PROJECT_MANIFEST.txt
README_RU.md
AGENTS.md
```

Для runtime-файлов запрещено слепо принимать `ours` или `theirs`. Их изменения должны быть разложены на композиционные adapters.

Целевая декомпозиция клиента:

```text
GraphicalClientRuntime
├── PlayerRealtimeAdapter
├── ItemGraphClientAdapter
├── ConstructionClientAdapter
├── MatterClientAdapter
└── RepresentationClientAdapter
```

Целевая декомпозиция сервера:

```text
DedicatedServerRuntime
├── FixedTickPlayerRuntime
├── ItemGraphServerAdapter
├── ConstructionServerAdapter
├── MatterServerAdapter
└── RepresentationStreamingAdapter
```

## 7. Последовательность интеграционных checkpoint

### INT0 — Canonical Integration Base

- объединить три frozen heads;
- разрешить manifests, documentation и runners;
- добиться editor import;
- сохранить все прежние focused test profiles;
- не добавлять междоменные функции.

Acceptance:

```text
Editor import PASS
NX0–NX6 PASS
C1–C24 PASS
MW0–MW10 PASS
RL0–RL3 PASS
World regression PASS
Main-scene gate PASS
Git diff check PASS
```

### INT1 — Runtime Decomposition

- вынести player/item/construction/matter/representation adapters;
- убрать прямое разрастание M3 runtime;
- закрепить lifecycle order и failure isolation;
- проверить независимое включение/отключение adapters.

### INT2 — Unified Traffic Classes

Ввести логические классы:

```text
CONTROL
PLAYER_INPUT
MOVEMENT_SNAPSHOT
ITEM_COMMAND
ITEM_DELTA
CONSTRUCTION_COMMAND
CONSTRUCTION_EVENT
MATTER_COMMAND
MATTER_DELTA
REPRESENTATION_MANIFEST
REPRESENTATION_ARTIFACT
FULL_RESYNC
TELEMETRY
```

Для каждого класса закрепить:

- delivery mode;
- ordering;
- coalescing;
- priority;
- fragmentation policy;
- bandwidth budget;
- resync behavior.

### INT3 — Unified Authority Directory

Создать фасад:

```text
WorldAuthorityDirectory
```

Маршрутизация:

```text
PLAYER        → session/player authority
ITEM_GRAPH    → item authority
CONSTRUCT     → ConstructionAuthorityRegistry
MATTER_REGION → MatterAuthorityDirectory
```

Фасад не заменяет доменные registries. Он унифицирует lookup, epoch, lease/fencing, migration status, route errors и telemetry.

### INT4 — Matter-to-Item Transaction

Первый обязательный cross-domain vertical slice:

```text
matter excavation
→ committed mass removal
→ material batch creation
→ Item Graph insertion
→ inventory replication
```

Нужен durable coordinator:

```text
PREPARED
MATTER_COMMITTED
ITEM_COMMITTED
COMPLETED
COMPENSATING
```

Инварианты:

- материал не создаётся дважды;
- matter не удаляется без terminal outcome;
- retry использует тот же operation ID;
- reconnect возвращает exact result;
- crash между commits восстанавливается детерминированно.

### INT5 — Construction on Mutable Matter

Добавить versioned `SurfaceAttachment`:

```text
construct_id
matter_body_id
support_region_ids
local_anchor
contact_bounds
matter_revision_frontier
construct_revision
checksum
```

Проверить:

- placement на matter surface;
- изменение поверхности под основанием;
- structural invalidation;
- проседание, потерю опоры или разрушение;
- re-anchor/repair;
- matter handoff при сохранении construction authority.

### INT6 — Unified Interest and Streaming

Объединить:

- player relevance;
- Item Graph relevance;
- construction proxy relevance;
- matter representation relevance;
- artifact build priority;
- per-client network budget;
- per-client memory budget;
- cancellation и starvation protection.

Этот этап заменяет отдельную разработку NX8/RL5 до merge.

### INT7 — Unified World Checkpoint

Добавить `WorldCheckpointManifest`:

```text
world_checkpoint_id
player revisions
item_graph_revision
construction_generation
matter_region_frontiers
authority_epochs
operation_journals
representation_manifests
protocol_version
```

`Mesh`, `ArrayMesh`, `RID`, runtime nodes и GPU resources не входят в canonical checkpoint и восстанавливаются из source state/artifact cache.

### INT8 — Three-Domain Acceptance

Обязательный сценарий:

```text
two clients connect
→ player prediction/interpolation works
→ approach asteroid with progressive surface streaming
→ excavate matter
→ receive material in Item Graph
→ build item-backed construct
→ observe C24 proxy at distance
→ mutate supporting surface
→ receive structural reaction
→ perform regional handoff
→ disconnect/reconnect
→ restart server
→ recover identical canonical state
```

Проверять под профилями:

```text
LOCAL
GOOD_BROADBAND
AVERAGE_BROADBAND
MOBILE
BAD_MOBILE
LAG_SPIKE
```

## 8. Что разрабатывать только после объединения

Следующие направления не должны выполняться независимо в старых ветках:

- NX7 physics authority profiles;
- NX8 interest management;
- NX9 async persistence hardening;
- unified representation scheduler/cache warming;
- construction surface attachments;
- matter-backed construction;
- detached/fractured matter bodies;
- production Moon/planet integration;
- common asset/material catalog;
- shared impostor/decimation pipeline;
- server-to-server production transport для объединённых доменов.

## 9. Критерий готовности к merge в main

Интеграционная ветка может быть перенесена в `main` только после:

```text
INT0–INT8 PASS
all legacy focused suites PASS
all combined process suites PASS
no duplicate item/material outcomes
no split-brain authority
no unresolved predictions
no stale close-collision artifact
bounded memory/network queues
restart checksum equivalence
main scene PASS
Git diff check PASS
```

## 10. Краткая карта исполнения

```text
CONSTRUCTION
C24 implementation
→ independent acceptance
→ freeze

NETWORK
NX2
→ NX3
→ NX4
→ NX5
→ NX6
→ acceptance
→ freeze

MATTER / SURFACE
RL1
→ acceptance
→ MW9
→ MW10
→ RL2
→ RL3
→ acceptance
→ freeze

INTEGRATION
INT0 canonical composition
→ INT1 runtime decomposition
→ INT2 traffic classes
→ INT3 authority facade
→ INT4 matter-to-item transaction
→ INT5 construction on mutable matter
→ INT6 unified interest/streaming
→ INT7 world checkpoint
→ INT8 acceptance
→ main
```

## 11. Неподвижные архитектурные правила

- сервер остаётся источником истины;
- Item Graph, `ConstructSnapshot` и matter state являются отдельными canonical domains;
- mesh и representation artifacts не являются world state;
- один resource имеет одного authoritative writer и authority epoch;
- handoff использует fencing и exact replay;
- cross-domain effects проходят через durable operations;
- клиентская prediction не изменяет canonical state;
- крупные конструкции и поверхность передаются по interest/LOD, а не полной детализацией;
- общий runtime строится через adapters, а не через один монолитный controller;
- старые feature branches не merge-ятся в `main` по отдельности после начала INT0.
