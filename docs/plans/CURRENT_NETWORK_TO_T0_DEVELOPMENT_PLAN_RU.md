# Текущий план разработки: Network Minimum → T0 → параллельные Construction / Matter labs

**Дата фиксации:** 2026-08-08
**Репозиторий:** `rootfabric/distributed-world-simulator`
**База на момент решения:** `main @ 25a156638aaf74d136ecf299ebe0d96c0f30897a`
**Назначение:** зафиксировать, когда сеть перестаёт быть блокирующей стадией и становится параллельно развиваемой инфраструктурой для Item, Construction и Matter.

---

## 1. Текущее состояние сети

Актуальный `config/network/network-experience-roadmap.v1.json` на `main` фиксирует:

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

Следствие: архитектурный минимум для начала gameplay-validation уже достигнут по сетевому roadmap. Текущая задача — не ждать идеальной плавности и не ждать NX7–NX9, а формально подтвердить `Network Minimum ACCEPTED` на текущей композиции и открыть T0.

---

## 2. Основное решение

С этого момента необходимо разделять два понятия:

```text
NETWORK CORRECTNESS / CONTRACTS
и
NETWORK FEEL / TUNING
```

`Network Minimum ACCEPTED` означает, что сеть достаточно корректна архитектурно, чтобы Item, Construction и Matter могли развиваться независимо от дальнейшего тюнинга сети.

Это НЕ означает, что multiplayer уже обязан быть идеально плавным.

После прохождения minimum gate сеть становится горизонтальным инфраструктурным потоком:

```text
NETWORK: NX6 → NX7 → NX8 → NX9 → дальнейший tuning
                    │
                    ├──────────── развивается параллельно
                    │
GAMEPLAY:      T0 → T1/T3 → T2/T4 → T5 → T6 → T7
```

---

## 3. Последовательность развития проекта

Зафиксированная последовательность:

```text
ТЕКУЩАЯ СЕТЕВАЯ ЗАДАЧА
Network Minimum ACCEPTED
        │
        ▼
T0 — Item / Playground Acceptance
        │
        ├────────────────────────┐
        │                        │
        ▼                        ▼
T1 Construction Lab       T3 Matter Excavation Lab
        │                        │
        ▼                        ▼
T2 Construction Scale     T4 Matter Streaming
        │                        │
        └──────────┬─────────────┘
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

Это является текущей управляющей последовательностью для дальнейшей разработки gameplay-веток.

---

## 4. Network Minimum Acceptance Gate

Перед формальным `Network Minimum ACCEPTED` необходимо подтвердить не визуальную идеальность, а следующие инварианты:

```text
[PASS] server authority сохранён
[PASS] stable player/entity/item identity
[PASS] fixed authoritative simulation tick
[PASS] input / operation sequence semantics устойчивы
[PASS] duplicate delivery не применяет действие дважды
[PASS] stale state можно отличить от нового
[PASS] domain revisions сходятся
[PASS] explicit accept / reject semantics работают
[PASS] reconnect не создаёт новую конфликтующую identity
[PASS] gameplay domain не зависит от packet-arrival timing
[PASS] gameplay domain не зависит напрямую от конкретного transport/RPC
[PASS] предыдущие accepted network contracts не регрессировали в композиции
```

Минимальный проверочный профиль должен включать:

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

Если эти инварианты проходят, `Network Minimum` принимается даже при наличии заметного визуального tuning debt.

---

## 5. Что НЕ блокирует T0

Следующие проблемы после Network Minimum считаются tuning / quality debt и могут исправляться параллельно:

- небольшое дёрганье remote player;
- заметные, но корректные reconciliation corrections;
- неидеальный interpolation delay;
- snapshot rate, требующий настройки;
- input send rate, требующий настройки;
- jitter-buffer tuning;
- extrapolation tuning;
- quantization и delta compression;
- bandwidth optimization;
- priority / replication-budget tuning;
- отсутствие максимально быстрого optimistic presentation;
- задержка UI на время server confirmation, если состояние остаётся корректным.

Такие дефекты не должны автоматически возвращать проект в режим «занимаемся только сетью».

---

## 6. Что остаётся блокером

Следующие дефекты являются основанием остановить gameplay-ветку и исправлять network/domain contract:

- потеря предмета;
- дублирование предмета;
- двойное применение одной операции;
- divergent authoritative state между клиентами;
- неверный ownership / authority;
- потеря durable state после reconnect;
- невозможность определить stale revision;
- зависание lifecycle/ready state, из-за которого peer не входит в валидную сессию;
- protocol/source-contract regression;
- бизнес-логика, зависящая от порядка прихода пакетов;
- gameplay-код, напрямую завязанный на ENet/RPC вместо domain command;
- невозможность воспроизвести операцию через offline/test/server path без сетевого транспорта.

Главный критерий:

```text
визуальный лаг допустим;
расхождение канонического состояния — нет.
```

---

## 7. T0 — Item / Playground Acceptance

T0 является следующим gameplay checkpoint после Network Minimum.

Цель T0 — доказать, что предметная система живёт поверх сетевого фундамента без зависимости от дальнейшего сетевого тюнинга.

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
2. A кладёт предмет в контейнер → оба клиента видят одинаковую container revision.
3. A переносит stack → операция применяется ровно один раз.
4. Duplicate/reorder transport не дублирует действие.
5. A disconnect → authoritative item state остаётся корректным.
6. A reconnect → получает тот же Item Graph / revisions.
7. Offline/local execution использует тот же domain operation path.
8. Reject операции не оставляет predicted/visual ghost как canonical state.

### T0 acceptance

```text
[PASS] no duplication
[PASS] no item loss
[PASS] authoritative ownership
[PASS] stable item identity
[PASS] idempotent operations
[PASS] revisions converge
[PASS] reconnect restores state
[PASS] two clients converge on the same result
[PASS] offline path uses the same domain rules
```

Следующее не блокирует T0:

```text
[WARN] UI latency
[WARN] lack of perfect optimistic prediction
[WARN] animation delay
[WARN] remote interpolation polish
[WARN] snapshot/bandwidth tuning debt
```

---

## 8. Роль NX6

NX6 `Predicted Item Interactions` остаётся важным текущим сетевым этапом, но его роль после достижения Network Minimum уточняется.

NX6 должен улучшать:

- optimistic item presentation;
- predicted pickup/drop/transfer presentation;
- dependent-operation completion;
- authoritative rejection rollback;
- playground lifecycle cleanup;
- perceived item interaction latency.

Но Item Domain не должен требовать NX6 для своей базовой корректности.

Правило:

```text
Network Minimum подтверждает возможность начать T0.
NX6 может приниматься параллельно с T0.
T0 не должен зависеть от идеальности prediction UX.
```

Если NX6 выявляет нарушение canonical correctness, это блокер.
Если NX6 выявляет только плохой feel/presentation, это tuning debt.

---

## 9. После T0 — обязательное распараллеливание

После `T0 ACCEPTED` разработка разделяется минимум на два независимых gameplay-потока.

### T1 → T2: Construction

```text
T1 Construction Lab
    ↓
T2 Construction Scale
```

Construction должен использовать domain operations и authoritative state, но не знать snapshot/interpolation details.

### T3 → T4: Matter

```text
T3 Matter Excavation Lab
    ↓
T4 Matter Streaming
```

Matter excavation должна быть транзакционной операцией мира, а не прямым RPC типа `remove_voxel(x,y,z)`.

Рекомендуемый логический контракт:

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
- reject reason when rejected
```

Конкретная wire serialization может изменяться независимо от этого domain contract.

---

## 10. Simulation Operation Protocol как архитектурное правило

Новые gameplay-системы должны стремиться к общей модели world/domain operations, а не к RPC-driven domain logic.

Пример семейства операций:

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

Одна и та же операция должна быть пригодна для вызова из:

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

---

## 11. T5–T7

### T5 — Matter + Construction Composition

Проверяет совместное изменение Matter и Construction без расхождения ownership, revisions, physics/projection и persistence.

### T6 — Recovery / Reconnect Composition

Проверяет recovery уже не одной subsystem, а композиции:

```text
player
items
containers
construction
matter
```

После reconnect каноническое состояние должно сходиться без duplication и без потери принятых durable operations.

### T7 — Asteroid Surface Lab

Объединяет:

- локомоцию;
- item interactions;
- excavation;
- construction;
- matter streaming;
- representation/LOD;
- reconnect;
- multiplayer observation.

T7 должен быть gameplay/validation lab перед переходом к полноценным seamlessness, handoff и large-world сценариям.

---

## 12. Правило перехода к Seamlessness / Handoff / Large World

К большой распределённой композиции не следует переходить только потому, что отдельные subsystem tests зелёные.

До этого должны быть приняты validation labs:

```text
T0 Item / Playground
T1 Construction Lab
T2 Construction Scale
T3 Matter Excavation Lab
T4 Matter Streaming
T5 Matter + Construction Composition
T6 Recovery / Reconnect Composition
T7 Asteroid Surface Lab
```

После этого seamlessness/handoff решают уже задачу распределения работающей симуляции, а не пытаются одновременно исправлять базовые semantics предметов, строительства и Matter.

---

## 13. Текущий порядок действий

На момент этой фиксации порядок следующий:

```text
1. Формально подтвердить Network Minimum на текущей main-композиции.
   - опираться на уже accepted NX0–NX5;
   - проверить correctness/reconnect/composition invariants;
   - не требовать идеальной плавности.

2. Не ждать NX7–NX9 перед T0.

3. Вести NX6 fix3 acceptance параллельно с подготовкой/прогоном T0.

4. Принять T0 по canonical item correctness, а не по идеальности UX latency.

5. После T0 открыть две параллельные ветки:
   T1 Construction Lab
   T3 Matter Excavation Lab

6. Продолжать network tuning горизонтально, не меняя domain contracts.

7. Любой новый gameplay network integration строить через domain operations/revisions/authority, а не через transport-specific RPC semantics.
```

---

## 14. Неизменяемое решение

Пока не обнаружен новый correctness blocker, стратегия проекта следующая:

> Сеть больше не должна доводиться до визуального идеала до начала предметов, строительства и копания. После подтверждения Network Minimum дальнейший сетевой тюнинг идёт параллельно gameplay-разработке. Блокируют развитие только нарушения authority, identity, idempotency, revisions, persistence/reconnect, protocol contracts и convergence канонического состояния.

Это правило следует использовать при выборе следующей задачи и при acceptance review будущих T0–T7 этапов.
