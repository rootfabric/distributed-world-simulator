# RTA0 — Realtime Action Temporal Foundation

Статус: **CONTROL / DESIGN CANDIDATE R1**  
База: `main @ 5b44068d80439deb0f16597ddd36b546d68eebfa`  
Машиночитаемый контракт: `config/control/harness/rta0-realtime-action-temporal-foundation.v1.json`

## 1. Назначение

RTA0 добавляет в текущий план реализации минимальные закладные для быстрых сетевых действий без реализации стрельбы, damage, projectile simulation, historical rewind или anti-cheat runtime.

RTA0 нужен не только потенциальному PvP. Тот же фундамент пригоден для melee, mining, захвата движущегося объекта, tool activation, docking/seat interaction, действий в движущихся reference frames, replay/debugging и будущих cross-authority interactions.

Главное правило:

```text
RTA0 freezes TIME/IDENTITY/AUTHORITY semantics.
RTA0 does NOT implement historical state storage or combat.
```

## 2. Почему checkpoint отдельный

Текущая продуктовая линия уже имеет необходимые опоры:

```text
NX3  fixed authoritative simulation timeline
NX4  local owner prediction/reconciliation
NX5  remote presentation timeline

pre-P6 EG/CWIP  InteractionTime + authority/collision/effect boundaries
P6.2             topology-neutral identities
P6.3             OperationId continuity/idempotency
P6.4             mutation admission boundary
P6.6             route-neutral command/session routing
```

RTA0 не должен менять эти owners и не должен создавать второй network foundation. Он только фиксирует отсутствующие cross-cutting semantics, чтобы позднее fast interaction domain не был вынужден встраивать transport IDs, private clocks или private historical truth.

## 3. Шесть обязательных закладных

### 3.1 Time identity

В проекте должна существовать одна семантика временной идентичности realtime-действия.

Ключевые свойства:

```text
simulation epoch / timeline generation
canonical/server time reference
source local tick or input sequence
mapping revision when timelines are mapped
```

Клиентское время — evidence/claim, а не authority:

```text
CLIENT TIME CLAIM
        |
        v
ACTION AUTHORITY
validate / clamp / reject
```

RTA0 не создаёт конкурирующий DTO времени. Если текущий EG0 `InteractionTime` будет принят, downstream realtime action semantics должны reuse/adapt его или accepted successor. Создание второй независимой canonical clock truth запрещено.

### 3.2 Action identity

Быстрое действие получает topology-neutral `RealtimeActionId` или accepted equivalent.

```text
RealtimeActionId != OperationId
RealtimeActionId != TransportConnectionId
RealtimeActionId != ENetPeerId
RealtimeActionId != socket/process identity
```

`RealtimeActionId` предназначен для bounded dedup/reorder/redundancy окна и не обязан попадать в durable operation ledger.

Если действие создаёт canonical mutation:

```text
RealtimeAction
    action_id = A
        |
        v
Canonical Operation
    operation_id = O
    caused_by_action = A   # optional causal evidence
```

Miss/no-op action может вообще не создавать durable `OperationId`.

### 3.3 Observed-state identity

Быстрое действие может нести read-only ссылку на то состояние, которое реально было представлено клиенту.

Семантика:

```text
subject/domain identity
+ authoritative time reference
+ snapshot/state revision when available
+ ReferenceFrameEvidence when required
```

Это **не** canonical world truth и не разрешение на mutation.

```text
ObservedStateRef = evidence
Projection hit   = candidate
Authority result = truth
```

### 3.4 Route preservation

Gateway/RoutePort/CommandRouter могут добавлять routing metadata, но не переписывают gameplay action semantics.

Обязательное сохранение:

```text
realtime_action_id
actor_id
input_sequence or equivalent
action_time_identity
observed_state_identity
action_type
action_payload
```

Разрешённая отдельно стоящая metadata:

```text
transport connection
logical client session
route binding
authority binding
gateway hop metadata
```

Запрещённый паттерн:

```text
Client Action A
   -> Gateway
   -> Gateway invents gameplay Action B
   -> Authority
```

Требуемый паттерн:

```text
Client Action A
   -> Gateway / Router
   -> Authority receives semantic Action A
```

### 3.5 Authority boundary

Клиент может сообщить intent и evidence, но не canonical result.

```text
CLIENT
  intent + time/observed evidence
          |
          v
ACTION AUTHORITY
  validates action
          |
          v
WORLD AUTHORITY
  validates its own collision/domain truth when required
          |
          v
TARGET EFFECT AUTHORITY
  alone commits canonical effect
```

Gateway не становится gameplay oracle.

Клиент никогда не должен быть единственным источником canonical истины о:

```text
target
collision result
damage/effect
mutation authorization
```

### 3.6 Read-only historical-query concept

RTA0 фиксирует только интерфейсную границу, а не storage.

```text
HistoricalStateQuery
    READ ONLY
    DERIVED
    BOUNDED when implemented
    NON-CANONICAL
    NO MUTATION AUTHORITY
```

RTA0 **не требует**:

```text
history buffers
rewound hitboxes
historical physics world
combat history
server rewind
```

Каждый будущий domain сам решает, нужна ли ему history и какой depth нужен.

Примеры будущих специализаций:

```text
HistoricalPlayerPoseQuery
HistoricalCollisionQuery
HistoricalReferenceFrameQuery
```

## 4. Интеграция в текущий V0/P6 план

RTA0 является маленьким cross-cutting control/design checkpoint и не меняет текущую product sequencing.

```text
CURRENT V0 / PRE-P6 WORK
        |
        +---- RTA0 CONTROL/DESIGN ONLY
        |       freeze six foundations
        |       no runtime authority
        |
        v
EG0 -> EG1 -> EG2 -> EG3 -> EG4 -> EG4.5 -> EG5
        |
        v
EDGE_GATEWAY_FOUNDATION_ACCEPTED
        |
        v
refresh / activate P6
        |
        +-- P6.2 identity consumes topology-neutral rule
        +-- P6.3 keeps RealtimeActionId != OperationId
        +-- P6.4 treats temporal evidence as evidence, not authority
        +-- P6.6 proves semantic route preservation
        |
        v
P6.7 -> P6.11
        |
        v
P6 ACCEPTED
        |
        v
SM1
        |
        v
future NXC / melee / mining / other fast temporal interaction
```

## 5. Stage-specific requirements

### PRE-P6 EG0–EG5

- `InteractionTime` or accepted successor remains the single cross-world time-evidence direction.
- Gateway preserves time/action/observed-state semantics.
- Gateway does not resolve gameplay truth.
- No real damage or combat runtime is added by RTA0.

### P6.2

- actor/action identity does not depend on transport connection, socket or process identity.

### P6.3

- preserve existing durable `OperationId` semantics;
- introduce no durable ledger requirement for every realtime action;
- allow optional causal `RealtimeActionId -> OperationId` linkage.

### P6.4

- temporal evidence may be input to admission validation;
- temporal evidence itself never grants authority.

### P6.6

Add an explicit route-preservation acceptance requirement:

```text
same semantic realtime action
before RoutePort/Gateway
==
same semantic realtime action
after RoutePort/Gateway
```

Route metadata is excluded from this semantic equality.

### P6.7–P6.11

RTA0 does not require history storage, combat, rewind or anti-cheat implementation for P6 acceptance.

### SM1

Authority route changes must preserve action/time/observed-state identity. A changed route must not turn a retry into a new semantic action.

### Future fast-interaction domain

Only here is runtime history instantiated if actually needed.

For future combat this can become:

```text
ShotAction
  -> historical query
  -> authoritative resolution
  -> DamageOperation
```

For mining it may instead remain current-state validation with no historical buffer at all.

## 6. Что RTA0 сознательно НЕ делает

```text
NO weapon runtime
NO damage runtime
NO health domain
NO hitboxes
NO projectile runtime
NO lag-compensation buffer
NO server rewind
NO anti-cheat runtime
NO P6 authority grant
NO SM1 activation
NO EG activation
```

Это важно: checkpoint должен уменьшить будущую стоимость изменений, а не создать преждевременную подсистему.

## 7. Machine exit

RTA0 candidate должен доказать:

```text
RTA0_TIME_IDENTITY_FROZEN
RTA0_ACTION_IDENTITY_FROZEN
RTA0_OBSERVED_STATE_IDENTITY_FROZEN
RTA0_ROUTE_PRESERVATION_FROZEN
RTA0_AUTHORITY_BOUNDARY_FROZEN
RTA0_READ_ONLY_HISTORICAL_QUERY_CONCEPT_FROZEN
RTA0_NO_COMPETING_TIME_OR_ACTION_TRUTH
RTA0_NO_RUNTIME_COMBAT_OR_HISTORY_ACTIVATION
```

После PASS это остаётся architectural foundation, а не runtime feature acceptance.
