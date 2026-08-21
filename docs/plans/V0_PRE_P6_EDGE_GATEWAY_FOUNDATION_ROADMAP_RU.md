# V0 — PRE-P6 Edge Gateway Foundation Roadmap

Статус: **CONTROL CANDIDATE / CURRENT EXECUTION ORDER / P6 RUNTIME BLOCKED**

Canonical planning base:

`main @ 1d9de3c479c60045d613660b2a5c5db0374963f8`

Accepted P5 product lineage / future P6 product base remains:

`491ca7d058690d3de5fcea5e41aaee230a31b3ab`

Нормативные сетевые документы:

- `docs/network/EDGE_GATEWAY_FABRIC_SPEC_RU.md`
- `docs/network/EDGE_GATEWAY_TEST_IMPLEMENTATION_PLAN_RU.md`
- `config/control/harness/v0-edge-gateway-fabric-test-plan.v1.json`
- `config/control/harness/v0-p6-seamless-execution-roadmap.v1.json`

Этот roadmap меняет **порядок выполнения**, а не ownership проекта.

Главное решение:

```text
P6 RUNTIME НЕ НАЧИНАЕМ.

Сначала реализуем и принимаем PRE-P6 Edge Gateway Foundation:
EG0 -> EG1 -> EG2 -> EG3 -> EG4 -> EG5.

Только после EDGE_GATEWAY_FOUNDATION_ACCEPTED разрешается
обновить P6 preactivation / Work Order и активировать P6 runtime.
```

P6 product base не меняется. Edge Gateway lab не становится product ancestry.

---

## 1. Почему Gateway Foundation идёт перед P6

P6 должен наращивать persistent multiplayer gameplay поверх правильной transport/session границы.

Если начать P6 до проверки Gateway, возникает риск закрепить в gameplay коде неверные предположения:

```text
peer_id == PlayerId
socket == gameplay owner
client connected directly to simulation server
server endpoint == authority identity
one backend connection == one player
projection source == separate client socket
```

После роста P6 это затронет movement, inventory, equipment, Construction, mining, reconnect, tests и recovery.

Поэтому до P6 требуется исполняемое доказательство базовой Gateway-модели, а не только документация.

---

## 2. Целевая базовая сеть

Для клиента мир имеет один client-facing transport:

```text
Client
  |
  | one WorldConnection
  v
Nearest Healthy Edge Gateway
  |
  +---- shared/multiplexed link pool ---- Authority A
  +---- shared/multiplexed link pool ---- Authority B
  +---- projection subscription --------- Macro / other sources
  |
  v
Directory / AUTHORITY + IAM / Session / Placement
```

Нормальный клиент:

```text
client_active_world_transports == 1
client_connects_directly_to_simulation_servers == false
```

Gateway скрывает:

- server discovery;
- auth/session attachment;
- placement;
- backend server topology;
- projection fan-in;
- будущий ACTIVE/WARM/DRAIN pivot.

Gateway не становится canonical owner.

---

## 3. Edge selection

Должно существовать много Gateway POP/instances.

Клиент выбирает ближайший **healthy network path**, а не просто географически ближайший узел.

MVP:

```text
EdgeLocator
  -> bounded candidate list
  -> client probes
  -> deterministic score
  -> connect best healthy Gateway
```

Score учитывает минимум:

- RTT;
- loss;
- jitter;
- health;
- capacity/load hint;
- hysteresis/fallback.

Simulation authority выбирается независимо от Gateway.

Пример:

```text
Client Texas -> Gateway Dallas -> Authority Frankfurt
Client Germany -> Gateway Frankfurt -> тот же Authority Frankfurt
```

Gateway selection != world ownership selection.

---

## 4. Shared Gateway -> Server links

Default `one player = one backend connection` запрещён как базовая архитектура.

MVP обязан доказать:

```text
Client A --\
Client B --- Gateway G1 === one physical backend link === Sim A
Client C --/
```

Logical multiplexing использует ephemeral routing identity, например `session_slot`, но:

```text
session_slot != PlayerId
session_slot != PlayerEntityId
backend_peer_id != PlayerId
```

Production допускает `1..K` backend tunnels на пару GatewayInstance/ServerInstance для ограничения failure/congestion domain.

Обязательны:

- per-session queues;
- per-link queues;
- fairness;
- priorities;
- backpressure;
- bounded memory;
- cross-session isolation;
- metrics.

---

## 5. Projection aggregation

V0 baseline:

```text
Client <-> Gateway only

Authority A ACTIVE ------\
Projection B -------------> Gateway -> same WorldConnection -> Client
Macro projection --------/
```

Direct `ProjectionPublisher -> Client` transports не входят в baseline до acceptance single-connection architecture.

Projection traffic:

- read-only;
- lower priority than session/control and canonical operations;
- stale unreliable projection may be dropped;
- projection loss must not disconnect gameplay;
- projection grant is never mutation authority.

---

## 6. PRE-P6 mandatory implementation: EG0-EG5

### EG0 — Contracts and fixtures

Нужно зафиксировать и протестировать:

- `ClientWorldFrame`;
- `GatewayIngressEnvelope`;
- `GatewayEgressEnvelope`;
- `GatewaySessionBinding`;
- `GatewayRouteBinding`;
- `ProjectionSubscription`;
- `GatewayDescriptor`;
- channel semantics;
- canonical fixtures / schema validation.

Exit:

```text
TOPOLOGY_NEUTRAL_DTOS_PASS
```

### EG1 — Single Gateway pass-through

```text
Client -> Gateway G1 -> Sim A
```

Доказать:

- real Gateway process;
- movement/input/world operations проходят через Gateway;
- direct baseline и Gateway path дают один canonical result;
- Gateway canonical writes = 0;
- Gateway ownership decisions = 0.

Exit:

```text
DIRECT_GATEWAY_CANONICAL_EQUIVALENCE_PASS
```

### EG2 — Auth / Session / Placement

Полный flow:

```text
discover/probe Gateway
-> connect Gateway
-> authenticate
-> create/resume ClientSession
-> resolve world/player placement
-> resolve current Authority
-> ensure shared backend link
-> attach logical session
-> WorldReady
```

Hard rule:

```text
client receives no simulation-server endpoint
```

Exit:

```text
WORLD_READY_WITHOUT_SERVER_ENDPOINT_DISCLOSURE
```

### EG3 — Shared multiplexed backend tunnel

Минимум два клиента должны использовать один physical Gateway->Authority link.

Проверить:

- multiplex/demultiplex;
- session slot lifecycle/reuse;
- reliable operations;
- input/snapshots;
- disconnect одного клиента без закрытия tunnel для остальных;
- slow/flooding client isolation;
- queue bounds;
- no cross-session leakage.

Exit:

```text
MULTI_CLIENT_ONE_BACKEND_LINK_PASS
```

### EG4 — Projection aggregation

```text
             A ACTIVE
            /
Client -> Gateway
            \
             B PROJECTION
```

Один graphical client должен одновременно видеть authoritative A и projection B через один WorldConnection.

Проверить:

- `client transport count == 1`;
- projection dropout не рвёт gameplay;
- projection cannot mutate;
- channel/backpressure priority работает.

Exit:

```text
MULTI_SOURCE_SINGLE_CLIENT_TRANSPORT_PASS
```

### EG5 — Multi-Gateway nearest-edge selection

Минимум три Gateway candidate.

Через `tc/netem` моделируются разные RTT/loss/jitter/health.

Проверить:

- выбирается лучший healthy path;
- unhealthy best candidate корректно заменяется fallback;
- geographic hint не имеет authority над измеренным bad path;
- routine future A->B authority handoff не требует Gateway rehome.

Exit:

```text
NEAREST_HEALTHY_EDGE_SELECTION_PASS
```

---

## 7. EDGE_GATEWAY_FOUNDATION_ACCEPTED — gate перед P6

P6 runtime activation запрещена, пока не выполнены все условия:

```text
[PASS] EG0 reviewed + verified
[PASS] EG1 reviewed + verified
[PASS] EG2 reviewed + verified
[PASS] EG3 reviewed + verified
[PASS] EG4 reviewed + verified
[PASS] EG5 reviewed + verified

[PASS] normal client world transport count = 1
[PASS] no direct simulation server endpoint required by client
[PASS] multi-client shared backend tunnel proven
[PASS] per-session isolation / queue bounds proven
[PASS] auth/session/placement through Gateway proven
[PASS] multi-source projection fan-in through Gateway proven
[PASS] nearest healthy Edge selection proven
[PASS] Gateway canonical writes = 0
[PASS] Gateway ownership decisions = 0
[PASS] topology-neutral identity semantics proven
[PASS] OperationId survives Gateway forwarding unchanged semantically
[PASS] DirectAdapter and GatewayAdapter converge on same gameplay/domain path
[PASS] no unresolved NX / AUTHORITY ownership conflict
[PASS] exact-candidate Project Control SUCCESS
[PASS] fresh independent critical review PASS
[PASS] independent verification PASS
```

Только после этого создаётся отдельная main-owned acceptance record:

```text
EDGE_GATEWAY_FOUNDATION_ACCEPTED
```

Этот record является обязательной precondition для P6 runtime activation.

---

## 8. Что происходит сразу после EG Foundation acceptance

Последовательность:

```text
EDGE_GATEWAY_FOUNDATION_ACCEPTED
        |
        v
refresh/replace stale P6 preactivation PR #182
        |
        v
refresh/rebase/replace P6.1 candidate PR #184
        |
        v
new exact P6 Work Order binds accepted EG contracts
        |
        v
rotate V0 runtime mutation lease to P6
        |
        v
create fresh P6 runtime branch from exact accepted P5 product lineage
        |
        v
P6 runtime implementation starts
```

Нельзя активировать P6 через старый R1 Work Order, если он не содержит новый pre-P6 Gateway acceptance dependency.

---

## 9. P6 после Gateway Foundation

P6 по-прежнему остаётся product checkpoint:

```text
P6.1  canonical ownership map
P6.2  topology-neutral identities
P6.3  OperationId continuity/idempotency
P6.4  mutation admission boundary
P6.5  PlayerAuthorityDomain-ready closure
P6.6  GatewayIngress-compatible gameplay surface
P6.7  persistent shared outpost
P6.8  restart/recovery
P6.9  WARM read-only compatibility
P6.10 fault/race matrix
P6.11 repeat/soak/closure
```

Но P6 уже работает с доказанной сетевой границей:

```text
TransportAdapter
    -> ClientGameplayPort
    -> SessionBinding
    -> MutationAdmission
    -> DomainCommand
```

И два transport paths обязаны сходиться сюда:

```text
DirectAdapter ------\
                     -> ClientGameplayPort -> same domain semantics
GatewayIngressAdapter/
```

---

## 10. EG6-EG9 после запуска P6 — параллельный поток

После `EDGE_GATEWAY_FOUNDATION_ACCEPTED` и запуска P6 Gateway-направление не останавливается.

Параллельно:

### EG6 — ACTIVE/WARM backend pivot

```text
Client <-> Gateway stable
Gateway -> A ACTIVE
Gateway -> B WARM
Directory commit A -> B
Gateway backend route pivot
A DRAIN
B ACTIVE
```

Hard invariants:

- explicit input/command barrier;
- authority epoch monotonic;
- route revision monotonic;
- no client reconnect;
- same PlayerId / PlayerEntityId;
- exact OperationId retry safety;
- stale A traffic fenced.

### EG7 — Gateway failure/rehome

```text
Client -> G1 -> A
kill G1
Client resume -> G2 -> A
```

Gateway failure — отдельное recovery событие, не normal world handoff.

### EG8 — WAN fault matrix

Раздельные network legs:

```text
Client <-> Gateway
Gateway <-> Authority A
Gateway <-> Authority B / projection
Authority <-> Directory
```

Проверяются latency/jitter/loss/duplicate/reorder/asymmetry/bandwidth/disconnect.

### EG9 — scale/fairness/soak

Минимум:

```text
2 graphical clients
32 bots
1+ Gateways
2 simulation authorities
shared backend link pool
30 minutes
```

По возможности расширять до 64/128+ bots.

---

## 11. Что НЕ является pre-P6 blocker

Перед P6 не требуется завершать:

- production QUIC selection;
- production BGP Anycast;
- zero-packet-loss Gateway failover;
- EG6 production authority handoff;
- EG7 production rehome;
- полный EG8 WAN matrix;
- EG9 production-scale capacity SLO;
- dynamic world split/merge;
- production autoscaling.

Они не должны превращать Gateway Foundation в бесконечную инфраструктурную программу.

Pre-P6 cutoff строго:

```text
EG0 + EG1 + EG2 + EG3 + EG4 + EG5
```

---

## 12. Новая primary roadmap

```text
P5 ACCEPTED
    |
    v
EDGE GATEWAY CONTROL/SPEC ACCEPTED
    |
    v
EG0 contracts
    |
    v
EG1 Client -> Gateway -> Server
    |
    v
EG2 Auth / Session / Placement
    |
    v
EG3 Shared multiplexed backend tunnel
    |
    v
EG4 Projection aggregation / one client transport
    |
    v
EG5 Multi-Gateway nearest healthy Edge
    |
    v
EDGE_GATEWAY_FOUNDATION_ACCEPTED
    |
    +------------------------------+
    |                              |
    v                              v
P6 runtime                    EG6 A<->B pivot
P6.1 -> P6.11                -> EG7 rehome
    |                         -> EG8 WAN faults
    |                         -> EG9 scale/soak
    +--------------+---------------+
                   |
                   v
              P6 ACCEPTED
                   |
                   v
              ACTIVATE V0-SM1
                   |
                   v
Production Edge Gateway + Directory + A/B
                   |
                   v
real seamless A <-> B behind one WorldConnection
                   |
                   v
                  P7
                   |
                   v
                  P8
```

---

## 13. Current control state

На момент этой sequencing-фиксации:

- P6 runtime mutation остаётся **FORBIDDEN**;
- PR #182 / #184 считаются stale относительно новой pre-P6 Gateway dependency;
- они не должны давать runtime authority до `EDGE_GATEWAY_FOUNDATION_ACCEPTED`;
- Edge Gateway lab остаётся donor/research lineage и не становится product base;
- NX остаётся владельцем общего transport/network foundation;
- AUTHORITY/Directory остаётся owner authority truth;
- Item Graph / Construction / persistence owners не меняются.

Final rule:

```text
FIRST PROVE THE WORLD CONNECTION.
THEN BUILD P6 ON TOP OF IT.
```
