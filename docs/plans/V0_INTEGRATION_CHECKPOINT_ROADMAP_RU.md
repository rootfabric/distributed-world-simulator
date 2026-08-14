# V0 Integration Checkpoint Roadmap

**Status:** ACTIVE V0 COMPOSITION / PRODUCT CHECKPOINT  
**Date:** 2026-08-14  
**Repository:** `rootfabric/distributed-world-simulator`  
**Current implementation line:** `feature/v0-s1-networked-planetary-outpost-mvp`  
**Baseline head at activation:** `6c4931f9c44db374b4eb3ab08b51fe1268dce569`

## 1. Решение

V0 перестаёт быть одноразовым минимальным network demo.

V0 фиксируется как **главный интеграционный checkpoint проекта**, в котором уже
принятые и проверенные подсистемы последовательно собираются в один живой runtime.

Это product/composition checkpoint, а не новый architecture owner.

```text
accepted subsystem evidence
        +
current canonical runtime
        ↓
V0 integration checkpoint
        ↓
playable persistent world baseline
        ↓
следующие gameplay/simulation slices развиваются поверх него
```

V0 не имеет права создавать параллельные Item, Construction, Character, Terrain,
Network или Persistence truth.

## 2. Почему меняется роль V0

Проект уже содержит большой объём реализованных частей, но многие из них были
доказаны в отдельных labs, harnesses и acceptance branches.

Продолжать добавлять новые подсистемы, не сводя существующие, создаёт риск, что
проект останется набором успешных foundations без общей развиваемой игры.

Поэтому ближайший приоритет меняется с:

```text
ещё одна isolated capability
```

на:

```text
перенести accepted capability в V0
→ доказать composition
→ оставить её включённой
→ перейти к следующей capability
```

## 3. Зафиксированный текущий baseline

На 2026-08-14 операторски подтверждён первый playable Earth network baseline:

```text
dedicated server boots
2 graphical clients join one Earth world
2 player characters spawn рядом
players see each other
bidirectional movement is visible
Tab/F3 MVP controls can be exercised after the current local baseline patch
```

Known deferred defect:

```text
V0-NET-001
local/remote character presentation remains visibly jittery
```

`V0-NET-001` не исправляется внутри Inventory/Construction convergence.
Если исправление требует protocol / reconciliation / authority semantics, оно
маршрутизируется в NX.

## 4. Integration train

### V0-B0 — Bootable Two-Client Baseline

Цель: сохранить уже работающий executable baseline и не ломать его следующими
переносами.

Acceptance:

```text
server boot
A join
B join
same world identity
mutual visibility
bidirectional movement
spectator remains presentation-only
```

### V0-I1 — Inventory Convergence

Перенести уже существующий network inventory stack в Earth MVP.

Reuse:

```text
M3GraphicalClientRuntime
        ↓
canonical M4 Item Graph replica
        ↓
M5InventoryUiBridge
        ↓
M5NetworkedInventoryShell
        ↓
existing ContainerPanel / HotbarPanel / interaction profiles
```

Не разрешено:

```text
new client-private Item Graph
new inventory persistence
new inventory authority
temporary text-only MVP inventory as final path
```

Первый V0-I1 implementation checkpoint использует уже принятый M5 graphical
network inventory shell и общие production UI components. Он заменяет временное
text-only меню, сохраняя server-owned Item Graph.

После functional convergence допускается отдельный presentation-only polish step
`V0-I1P`, который приблизит chrome/layout к полному `InventoryScreen` без изменения
сетевых или domain contracts.

V0-I1 acceptance:

```text
Tab opens/closes graphical network inventory
hotbar remains visible while inventory is closed
slots 1..8 select canonical network hotbar
item transfer/drop goes through server Item command path
M5 bridge consumes canonical item_graph_updated
movement input is suspended while inventory is open
no duplicate Item authority
```

### V0-I2 — World Item / Container Interaction Convergence

Подключить ранее реализованные camera raycast, `world_interactable`, highlight,
`E` interaction, pickup/drop и external containers к тому же canonical network
Item Graph.

Target loop:

```text
world item
→ E pickup
→ backpack/hotbar
→ external container
→ transfer
→ drop
→ second client observes canonical result
```

### V0-C1 — Canonical Outpost Build Flow

Использовать уже существующие:

```text
MvpEarthOutpostAuthority
ConstructionMultiplayerGateway
M3ConstructionReplicationBridge
ConstructionReplica
```

Первый outpost:

```text
foundation
4 walls
roof
```

Игрок запускает существующий BUILD_STAGE flow; permanent construct возникает
только после server canonical commit.

### V0-C2 — C22/C24 Construction Presentation

Authoritative Construction bundle должен проходить через существующий
Construction runtime projection и C22/C24 proxy path.

Acceptance:

```text
A builds
A sees canonical proxy
B sees same construct/revision/checksum
B receives matching collision
no client-private construction mesh truth
```

### V0-C2A — Canonical Earth Surface Anchoring

Обязательный spatial integration gate, найденный при ручном C2 runtime test.
Construction topology и C22/C24 proxy остаются прежними, но world placement
construct не может зависеть от player/camera/spectator state.

Bounded V0 rule:

```text
stable Earth-fixed surface anchor
        +
current Earth render origin / frame basis
        ↓
derived presentation Transform3D
```

Не разрешено использовать observer planar position, eye height или spectator
translation как canonical construct placement. Перемещение observer меняет только
локальный render transform; anchor остаётся неизменным.

Текущий fixed MVP outpost детерминированно получает Earth surface anchor из
канонической M3 planar позиции. Целевая promotion без изменения C22/C24 path:

```text
root Item
→ WORLD(entity_id)
→ WorldEntity
→ SpatialRef(frame_id = earth.fixed)
→ тот же presentation projector
```

Detailed contract и acceptance:
`docs/plans/V0_C2A_CANONICAL_EARTH_SURFACE_ANCHORING_RU.md`.

V0-C2A acceptance:

```text
foundation remains seated on terrain
walking/jumping never mutates world anchor
detached spectator does not carry the construct
terrain and construct recede together
A and B agree on one Earth-fixed location
Construction revision/checksum do not change from observer movement
```

### V0-C3 — Inventory ↔ Construction Resource Convergence

Убрать MVP-only in-memory resource separation там, где она используется только
как bootstrap fixture, и связать build requirements с canonical gameplay Item
Graph через существующую Construction↔Item boundary.

Target loop:

```text
material/module in inventory
→ select/use
→ build command
→ Item mutation + Construction mutation through canonical contracts
→ both clients converge
```

Cross-domain atomicity не изобретается внутри V0. Если для correctness требуется
новый WorldTransaction contract, работа возвращается в global architecture track.

### V0-R1 — Reconnect Same Live World

Обязательный V0-S1 reconnect:

```text
A + B connected
items changed
outpost changed
B disconnects
A stays online
B reconnects
same live world
Item state converges
Construction state converges
```

Durable server-restart Construction persistence является отдельным gate, пока
существующий production path явно не докажет этот contract.

### V0-A1 — Integrated Acceptance / Soak

Один runner должен пройти весь сценарий:

```text
boot
2 clients
movement
inventory/hotbar
world item interaction
construction
second-client convergence
reconnect
30 minute soak
```

## 5. Что переносится после V0-S1 core

После I/C/R convergence V0 становится постоянной базой, в которую далее
подключаются уже сделанные/принятые vertical slices:

```text
Character/equipment presentation
additional world interaction/equipment
mutable terrain / digging when its canonical boundary ready
materials / matter gameplay composition
AI/agents when server/runtime boundary ready
landed ship
ship interior/cargo
movable ship
space / handoff
```

Каждый следующий slice обязан оставлять предыдущие capabilities работающими.

## 6. Что сейчас намеренно не чинится внутри V0

```text
network smoothing/reconciliation redesign
new protocol family
ownership model redesign
cross-server authority
multi-server handoff
new canonical material ontology
new world transaction foundation
```

V0 является integration detector. Если composition выявляет defect foundation,
он оформляется как bounded requirement соответствующего owner track, а не как
private V0 workaround.

## 7. Branch / mutation rule

До acceptance H0.3 сохраняется правило:

```text
simultaneous autonomous runtime mutation workers <= 1
```

V0 integration changes выполняются последовательно короткими steps:

```text
B0
→ I1
→ I2
→ C1
→ C2
→ C2A
→ C3
→ R1
→ A1
```

Каждый step:

```text
exact base
→ minimal integration diff
→ focused validation
→ full relevant regression
→ human graphical check where required
→ checkpoint
```

## 8. Definition of global V0 checkpoint

V0 становится новой развиваемой product baseline только после одновременного
подтверждения:

```text
procedural planet
2 network clients
playable characters
canonical inventory/hotbar
world item/container loop
canonical Construction outpost
C22/C24 visual + collision convergence
Earth-fixed construct anchoring independent of observer/spectator
reconnect same live world
no duplicate Item/Construction/Character truth
integrated runner
30 minute soak
```

После этого новые gameplay и simulation features должны по умолчанию доказываться
в V0 composition, а isolated labs остаются research/evidence tools, а не новой
production base.
