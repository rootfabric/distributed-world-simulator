# Post-MVP — расширение бесшовности и иерархические миры

Статус: **POST-MVP ROADMAP AMENDMENT / NOT ACTIVATED / NO CURRENT MVP SCOPE EXPANSION**

Этот план определяет первый крупный этап после принятия `V0_PLAYABLE_SEAMLESS_PLANET_COMPOSITION_ACCEPTANCE`. Он не является текущим Work Order, не расширяет acceptance первого MVP и не разрешает преждевременно начинать post-MVP runtime mutation.

## 1. Цель

После того как текущий MVP докажет бесшовность между соседними authority domains одного игрового мира, следующий шаг должен доказать, что тот же фундамент масштабируется на **иерархию вложенных миров и reference frames**.

Эталонная композиция:

```text
Space World
   |
   | REFERENCE_FRAME_CHILD / CONTAINS
   v
Planet World
   |
   +---- POI World
   |       |
   |       +---- Dungeon World
   |
   +---- neighboring surface regions
```

Игрок проходит:

```text
Space -> Planet -> POI -> Dungeon -> POI -> Planet -> Space
```

при сохранении одной логической клиентской сессии.

## 2. Основной контракт

Минимальные инварианты этапа:

```text
ONE_CLIENT_WORLD_CONNECTION
STABLE_PLAYER_ID
STABLE_PLAYER_ENTITY_ID
NO_NORMAL_GAMEPLAY_RECONNECT
NO_RESPAWN_ON_WORLD_TRANSITION
ONE_ACTIVE_CANONICAL_WRITER_PER_DOMAIN
CANONICAL_ITEMS_AND_CARRYING_PRESERVED
WORLD_GRAPH_DRIVES_TOPOLOGY
CLIENT_DOES_NOT_SELECT_SIMULATION_SERVER
REFERENCE_FRAME_TRANSFORMS_ARE_VERSIONED
STALE_ROUTE_OR_TRANSFORM_EVIDENCE_FAILS_CLOSED
```

World identity и server identity не должны смешиваться. `WorldId` описывает логический world/domain, а Directory/AUTHORITY определяет, какой server instance в данный момент является его canonical owner.

## 3. Иерархия WorldGraph

Переиспользовать существующие отношения WorldGraph:

```text
NEIGHBOR
OVERLAP
CONTAINS
REFERENCE_FRAME_PARENT
REFERENCE_FRAME_CHILD
PORTAL_OR_TRANSITION
VISUALLY_RELEVANT
```

Обязательный reference case:

```text
W0 Space
  -> W1 Planet
      -> W2 Surface POI
          -> W3 Dungeon
```

Нужно доказать не только линейный `A <-> B`, но переходы между уровнями вложенности.

## 4. Этапы

### HS1 — Hierarchical WorldGraph Composition

Создать versioned topology для минимум четырёх logical worlds:

- Space;
- Planet;
- POI;
- Dungeon.

Проверить:

- parent/child relationships;
- contains/portal relationships;
- topology revisions;
- stale relation revision rejection;
- Gateway read-only topology cache;
- отсутствие canonical gameplay writes в Gateway.

### HS2 — Reference Frame Chain

Доказать преобразования:

```text
Space frame
  -> Planet frame
      -> Local POI frame
          -> Dungeon frame
```

Проверить position, orientation и, где применимо, velocity при переходах.

Нельзя передавать cross-world координаты как голый `Vector3` без provenance. Любое межмировое преобразование должно быть связано с versioned reference-frame evidence.

### HS3 — Hierarchical Seamless Handoff

Запустить реальную multi-process композицию и пройти:

```text
Planet -> POI -> Planet
Planet -> Dungeon -> Planet
```

Затем полный маршрут:

```text
Space -> Planet -> POI -> Dungeon -> POI -> Planet -> Space
```

Обязательные результаты:

```text
client transport count = 1
normal reconnects = 0
respawns = 0
PlayerId changes = 0
PlayerEntityId changes = 0
canonical ACTIVE writers per domain = 1
```

### HS4 — Nested View / Projection

Gateway/View Planner должен показывать только необходимые представления соседних/родительских/дочерних worlds.

Примеры:

- на поверхности планеты виден macro/celestial Space source;
- возле POI заранее появляется projection/WARM source;
- внутри Dungeon не требуется держать полную detailed simulation всей планеты;
- известность тысячи worlds не означает тысячу upstream connections.

Проверить bounded active/warm/projection set и cleanup старых subscriptions.

### HS5 — Items and Construction Across Nested Boundaries

Проверить сохранение canonical item/carrying state через вложенные переходы.

Дополнительно использовать уже принятую после MVP Construction-модель для хотя бы одного boundary case:

- объект/Construction возле границы Planet/POI или двух surface authorities;
- один canonical result;
- два клиента сходятся;
- collision/projection не расходятся;
- replay не создаёт duplicate mutation.

Не создавать отдельные inventory, Item Graph или Construction truth для child world.

### HS6 — Cross-World Interaction

Активировать существующий Cross-World Interaction Protocol только после доказанного базового handoff.

Reference cases:

- действие из одного world воздействует на entity другого world;
- collision path может пересекать несколько world domains;
- каждая authority проверяет только свой collision domain;
- target effect authority единственная коммитит canonical effect;
- retry с тем же `OperationId`/`InteractionId` не создаёт второй эффект.

### HS7 — Persistence / Restart Matrix

Проверить поочерёдный restart child authorities без разрушения общей сессии/истины:

```text
restart Dungeon authority
restart POI authority
restart Planet authority
```

После recovery:

- topology revision согласована;
- player placement восстановлен;
- item/carrying state не потерян и не дублирован;
- Construction/world mutations сохранены;
- stale authority epoch fenced.

### HS8 — Four-Level Acceptance

Финальный пользовательский proof:

```text
Client A + Client B
        |
        v
Space
  -> Planet
      -> POI
          -> Dungeon
      <- POI
  <- Planet
<- Space
```

Во время маршрута выполняются реальные world operations: item interaction, mutation/Construction operation и хотя бы одно cross-world или cross-boundary observable действие.

## 5. Что этот этап не должен делать

Hierarchical Seamlessness не должен автоматически втягивать:

- полный WORLDGEN1;
- полноценную галактическую генерацию;
- production-scale ecology;
- FABRIC adaptive fidelity;
- все WORLD PACKS;
- dynamic autoscaling/Kubernetes;
- тысячи одновременных игроков.

Цель — сначала доказать **общность seamless topology/authority/reference-frame mechanism** на маленькой четырёхуровневой композиции.

## 6. Порядок после текущего MVP

Рекомендуемая post-MVP последовательность:

```text
CURRENT MVP ACCEPTED
        |
        v
HS1-HS8 HIERARCHICAL SEAMLESS WORLDS
        |
        v
WORLDGEN1 / PLANET-SCALE WORLD GENERATION
        |
        v
NX7/NX8/RF/NX9 / REPLICATION AND SCALE
        |
        v
MULTI-PLANET / LARGE-WORLD COMPOSITION
        |
        +---- WORLD FILL / WORLD PACKS
        +---- ECO integration
        +---- FABRIC integration
        |
        v
PRODUCTION-SCALE DISTRIBUTED WORLD
```

Причина такого порядка: если `Space -> Planet -> POI -> Dungeon` работает на маленьком стенде, дальнейшее расширение количества планет, регионов, станций, подземелий и серверов становится масштабированием уже доказанного механизма, а не новой сетевой архитектурой.

## 7. Activation rule

Этот roadmap становится исполняемым только после:

1. `V0_PLAYABLE_SEAMLESS_PLANET_COMPOSITION_ACCEPTANCE` принят;
2. current MVP Work Order закрыт;
3. создан отдельный post-MVP activation/epoch;
4. выпущен bounded Work Order для первого HS checkpoint;
5. определена exact accepted base.

До этого документ является направлением развития и не меняет текущий scheduler.
