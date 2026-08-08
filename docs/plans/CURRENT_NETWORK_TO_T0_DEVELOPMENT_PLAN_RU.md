# Текущий план разработки: Network Minimum → T0 → T1A/T1B + T3/T4 → T2 → T5–T7

**Дата первоначальной фиксации:** 2026-08-08
**Обновление:** 2026-08-08 — добавлен Complex Construct Demo Lab и разделение Construction на T1A/T1B перед T2.
**Репозиторий:** `rootfabric/distributed-world-simulator`
**База решения:** актуальный `main`, включающий интегрированный C24 construction stack.
**Детальный план T1:** `docs/plans/T1_COMPLEX_CONSTRUCT_DEMO_LAB_RU.md`.

## 1. Текущее состояние сети

Актуальный `config/network/network-experience-roadmap.v1.json` фиксирует:

```text
NX0 Observability Baseline                  accepted
NX1 Network Condition Simulator             accepted
NX2 Realtime Traffic Separation             accepted
NX3 Fixed-Tick Authoritative Simulation     accepted
NX4 Owner Prediction / Reconciliation       accepted
NX5 Remote Interpolation                    accepted
NX6 Predicted Item Interactions             fix3 implemented candidate
NX7 Physics Authority Profiles              planned
NX8 Interest Management / Replication       planned
NX9 Async Persistence / Hardening            planned
```

Тот же roadmap задаёт:

```text
first_playable_gate      = NX4_PLUS_NX5
first_full_gameplay_gate = NX6
current_stage            = NX6
```

Следствие: архитектурный минимум для начала gameplay-validation уже достигнут. Не требуется ждать идеальной плавности, NX7–NX9 или полного network tuning до начала Item/Construction/Matter labs.

## 2. Основное решение

Разделяются два понятия:

```text
NETWORK CORRECTNESS / CONTRACTS
и
NETWORK FEEL / TUNING
```

`Network Minimum ACCEPTED` означает, что сеть достаточно корректна архитектурно, чтобы gameplay-домены развивались независимо от дальнейшего тюнинга.

Это не означает, что multiplayer уже обязан быть идеально плавным.

После minimum gate сеть становится горизонтальным инфраструктурным потоком:

```text
NETWORK: NX6 → NX7 → NX8 → NX9 → дальнейший tuning
                    │
                    ├──────────────── развивается параллельно
                    │
GAMEPLAY:      T0 → T1A/T1B + T3/T4 → T2 → T5 → T6 → T7
```

## 3. Актуальная последовательность развития проекта

```text
ТЕКУЩАЯ СЕТЕВАЯ ЗАДАЧА
Network Minimum ACCEPTED
        │
        ▼
T0 — Item / Playground Acceptance
        │
        ├─────────────────────────────────────┐
        │                                     │
        ▼                                     ▼
T1A Complex Construct Demo             T3 Matter Excavation Lab
        │                                     │
        ▼                                     ▼
T1B Construct Composition              T4 Matter Streaming
        │                                     │
        ▼                                     │
T2 Construction Scale                         │
        │                                     │
        └──────────────────┬──────────────────┘
                           ▼
T5 Matter + Construction Composition
                           │
                           ▼
T6 Recovery / Reconnect Composition
                           │
                           ▼
T7 Asteroid Surface Lab
                           │
                           ▼
VALIDATION LABS ACCEPTED
                           │
                           ▼
SEAMLESSNESS / HANDOFF / LARGE WORLD
```

### Важное уточнение для T1

Экспериментальную разработку `T1A/T1B` разрешено начинать **до формального T0 acceptance**, потому что Construction C1–C24 и playable network foundation уже позволяют искать composition defects.

Но gate остаётся строгим:

```text
T1A/T1B implementation may start before T0;
T1 cannot be declared ACCEPTED before T0 ACCEPTED.
```

Это позволяет не простаивать и одновременно сохраняет правильный порядок formal acceptance.

## 4. Network Minimum Acceptance Gate

Перед формальным `Network Minimum ACCEPTED` подтверждаются не визуальные ощущения, а инварианты:

```text
[PASS] server authority сохранён
[PASS] stable player/entity/item identity
[PASS] fixed authoritative simulation tick
[PASS] input / operation sequence semantics устойчивы
[PASS] duplicate delivery не применяет действие дважды
[PASS] stale state можно отличить от нового
[PASS] domain revisions сходятся
[PASS] explicit accept / reject semantics работают
[PASS] reconnect не создаёт конфликтующую identity
[PASS] gameplay domain не зависит от packet-arrival timing
[PASS] gameplay domain не зависит напрямую от transport/RPC
[PASS] accepted network contracts не регрессировали в композиции
```

Минимальный профиль:

```text
LOCAL
latency 50 ms
latency 150 ms
latency 300 ms
loss 1%
loss 5%
duplicate
reorder
disconnect / reconnect
```

## 5. Что не блокирует gameplay labs

После Network Minimum следующие проблемы считаются tuning / quality debt:

- небольшое дёрганье remote player;
- reconciliation corrections при сохранённой correctness;
- неидеальный interpolation delay;
- snapshot/input send-rate tuning;
- jitter/extrapolation tuning;
- quantization/delta compression;
- bandwidth optimization;
- replication priority tuning;
- задержка UI на server confirmation;
- HLOD pop;
- asset/material polish;
- draw-call optimization debt, если canonical state корректен.

Они не должны автоматически возвращать проект в режим «занимаемся только сетью».

## 6. Что остаётся блокером

Следующие дефекты останавливают gameplay-ветку и возвращаются в network/domain layer:

- потеря предмета;
- дублирование предмета;
- двойное применение одной операции;
- divergent authoritative state между клиентами;
- неверный ownership / authority;
- потеря durable state после reconnect;
- невозможность определить stale revision;
- lifecycle/ready deadlock;
- protocol/source-contract regression;
- бизнес-логика, зависящая от порядка прихода пакетов;
- gameplay-код, напрямую завязанный на ENet/RPC вместо domain command;
- невозможность воспроизвести операцию через offline/test/server path без транспорта.

Главный критерий:

```text
визуальный лаг допустим;
расхождение канонического состояния — нет.
```

## 7. T0 — Item / Playground Acceptance

T0 доказывает, что Item Domain живёт поверх сетевого фундамента без зависимости от дальнейшего network tuning.

### Минимальный Playground

```text
Player A
Player B
Backpack
Container A
Container B
Loose stackable item
Loose non-stackable item
Container item
```

### Обязательные действия

```text
pickup
drop
transfer
split
stack
move between containers
open external container
reconnect and restore authoritative state
```

### Обязательные multiplayer scenarios

1. A подбирает предмет → B видит тот же authoritative result.
2. A кладёт предмет в контейнер → оба клиента видят одинаковую revision.
3. A переносит stack → операция применяется ровно один раз.
4. Duplicate/reorder не дублирует действие.
5. Disconnect не меняет authoritative item state.
6. Reconnect возвращает тот же Item Graph/revisions.
7. Offline/local execution использует тот же domain operation path.
8. Reject не оставляет predicted/visual ghost как canonical state.

### T0 acceptance

```text
[PASS] no duplication
[PASS] no item loss
[PASS] authoritative ownership
[PASS] stable item identity
[PASS] idempotent operations
[PASS] revisions converge
[PASS] reconnect restores state
[PASS] two clients converge
[PASS] offline path uses the same domain rules
```

Следующее не блокирует T0:

```text
[WARN] UI latency
[WARN] lack of perfect optimistic prediction
[WARN] animation delay
[WARN] remote interpolation polish
[WARN] bandwidth tuning debt
```

## 8. Роль NX6

NX6 улучшает optimistic presentation и perceived item latency, но Item Domain не должен требовать NX6 для базовой correctness.

```text
Network Minimum подтверждает возможность начать T0.
NX6 acceptance может идти параллельно с T0 и T1A preparation.
T0 не должен зависеть от идеальности prediction UX.
```

Если NX6 выявляет canonical correctness defect — это блокер.
Если только presentation/feel defect — это tuning debt.

## 9. T1A — Complex Construct Demo

После достижения playable network foundation и принятого Construction stack больше нет смысла проверять только отдельные столы/роботы/дома. Нужен первый сложный объект, объединяющий подсистемы.

Контрольный объект:

```text
Lunar Engineering Outpost
├── habitat
├── airlock
├── workshop
├── storage
├── utility room
└── exterior cargo/rover area
```

T1A доказывает одновременно:

```text
Item Graph
Construction semantics
rooms/openings
utilities
machines
runtime geometry/physics
multiplayer authority
streaming/HLOD
```

Масштаб:

```text
D0  50–100 parts     composition skeleton
D1  300–500 parts    playable outpost
```

Обязательные пункты T1A:

- deterministic fixture/CompositeDefinition/BuildPlan;
- PartVisualProfile presentation boundary;
- structural shell;
- door/window/room semantics;
- real containers/items;
- generator/battery/lights/console/fabricator utility chain;
- two-client experimental multiplayer;
- reconnect;
- runtime purge/rebuild;
- near/mid/far representation;
- inspector/telemetry.

Подробный execution plan: `docs/plans/T1_COMPLEX_CONSTRUCT_DEMO_LAB_RU.md`.

## 10. T1B — Construct Composition / Failure Demo

T1B проверяет причинные цепочки между независимыми facets.

Обязательные сценарии:

### Utility break

```text
remove cable
→ authoritative construction mutation
→ utility graph rebuild
→ lamp/fabricator OFF
→ room identity SAME
→ unrelated structural state SAME
```

### Structural damage

```text
damage/remove support
→ C9 topology change
→ C14 load recompute
→ deterministic degraded/broken result
→ optional split/salvage
→ runtime/proxy update
→ clients converge
```

### Space/opening

```text
open/close door
remove wall/window bond
→ C7 enclosure/space state changes
→ unrelated facets remain valid
→ repair restores original item identities
```

### HLOD round trip

```text
FULL near
→ DISTANT_SHELL far
→ authoritative mutation
→ return near
→ rebuild latest revision
```

### Recovery

```text
disconnect after authoritative commit
→ reconnect
→ same item/construct state
→ no duplicate operation
```

T1 acceptance требует formal T0 acceptance.

## 11. Hybrid Representation research line

T1A/T1B должны вскрыть реальные presentation limits C24, но это не причина откладывать D0.

Параллельно после D0 разрешается исследовать:

```text
Representation Router
├── StructuralGreedyBackend   # существующий C22/C24
├── ArbitraryMeshBackend      # сложные static meshes
├── InstanceBatchBackend      # повторяющиеся детали
└── InteractiveBackend        # stateful/interactive parts
```

Правила:

- Merging Meshes-подобные решения используются только как algorithmic reference;
- imported Node3D не становится authoritative source;
- visual catalog не меняет Construct/Item checksum;
- headless сервер не обязан загружать art assets;
- Quaternius/другой Sci-Fi pack подключается через PartVisualProfile, а не напрямую в domain.

## 12. T2 — Construction Scale

После принятия композиции объект масштабируется:

```text
D2  1 000–2 000 semantic parts
D3  10 000+ semantic parts
optional 100 000 stress
```

T2 должен проверять масштаб, а не заново чинить semantics.

Основные цели:

- dirty-section incremental rebuild;
- HLOD performance;
- content-addressed proxy reuse;
- instance batching;
- arbitrary static mesh batching;
- bounded SceneTree/resources;
- network interest/child identity suppression;
- reconnect/soak на реальной сложной базе.

## 13. T3 → T4: Matter

Matter развивается параллельно Construction после T0.

```text
T3 Matter Excavation Lab
    ↓
T4 Matter Streaming
```

Matter excavation является транзакционной domain operation, а не прямым RPC `remove_voxel(x,y,z)`.

Рекомендуемый logical contract:

```text
MiningOperation
- operation_id
- actor_id
- tool_id
- body_id
- region/chunk identity
- local position / direction
- requested effect parameters
- base_revision
- client_tick when available

MiningResult
- operation_id
- accepted / rejected
- old_revision
- new_revision
- canonical matter delta reference
- produced item operations
- reject reason
```

Wire serialization может изменяться независимо от domain contract.

## 14. Simulation Operation Protocol

Новые gameplay-системы используют world/domain operations, а не RPC-driven business logic.

```text
WorldOperation
├── MoveItemOperation
├── SplitStackOperation
├── PickupOperation
├── DropOperation
├── MiningOperation
├── PlaceConstructionOperation
├── RemoveConstructionOperation
├── DamageOperation
└── UseItemOperation
```

Общие свойства, где применимо:

```text
operation_id
actor_id
target identity
base_revision
authority context
accept/reject status
result revision
server ordering/tick metadata
```

Одна semantics должна вызываться из:

```text
player input
AI
offline/local mode
network server
server-to-server path
replay
automated test
```

Transport доставляет операцию, но не определяет её бизнес-смысл.

## 15. T5–T7

### T5 — Matter + Construction Composition

Совместное изменение Matter и Construction без расхождения ownership, revisions, physics/projection и persistence.

### T6 — Recovery / Reconnect Composition

Проверяет recovery композиции:

```text
player
items
containers
construction
matter
```

После reconnect состояние сходится без duplication и потери accepted durable operations.

### T7 — Asteroid Surface Lab

Объединяет:

- locomotion;
- item interactions;
- excavation;
- construction;
- matter streaming;
- representation/LOD;
- reconnect;
- multiplayer observation.

T7 является gameplay/validation lab перед seamlessness/handoff/large-world.

## 16. Gate перед Seamlessness / Handoff / Large World

До большой распределённой композиции должны быть приняты:

```text
T0 Item / Playground
T1A Complex Construct Demo
T1B Construct Composition
T2 Construction Scale
T3 Matter Excavation
T4 Matter Streaming
T5 Matter + Construction Composition
T6 Recovery / Reconnect Composition
T7 Asteroid Surface Lab
```

Только после этого seamlessness/handoff распределяют уже работающую симуляцию, а не одновременно исправляют базовые semantics.

## 17. Текущий порядок действий

```text
1. Формально подтвердить Network Minimum на актуальной main-композиции.

2. Продолжать T0 Item/Playground acceptance.

3. Не ждать NX7–NX9.

4. Вести NX6 acceptance/tuning параллельно.

5. Уже сейчас вести feature/t1-complex-construct-demo-lab:
   - T1A.0 baseline/fixtures;
   - T1A.1 PartVisualProfile boundary;
   - T1A.2 D0 outpost;
   - T1A.3 item integration;
   - T1A.4 utilities/machines;
   - T1A.5 two-client experimental profile;
   - T1A.6 inspector/telemetry.

6. После D0/D1 перейти к T1B controlled failures/recovery.

7. Формально принять T1 только после T0 ACCEPTED.

8. После T1 перейти к T2 D2/D3 real-base scale.

9. Параллельно после T0 вести T3/T4 Matter.

10. Network tuning остаётся горизонтальным потоком и не меняет domain contracts.
```

## 18. Неизменяемое решение

Пока не обнаружен новый correctness blocker, стратегия проекта следующая:

> Сеть больше не должна доводиться до визуального идеала до начала предметов, строительства и копания. После подтверждения Network Minimum дальнейший сетевой тюнинг идёт параллельно gameplay-разработке. Блокируют развитие только нарушения authority, identity, idempotency, revisions, persistence/reconnect, protocol contracts и convergence канонического состояния.

Для Construction добавляется второе правило:

> После принятия строительного фундамента новые фундаментальные слои не должны добавляться только ради теории. Сложный demo-object используется как архитектурный экзамен: найденные composition defects исправляются в исходном domain, а performance/visual debt развивается параллельно.
