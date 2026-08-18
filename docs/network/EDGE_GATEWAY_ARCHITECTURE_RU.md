# Multi-Region Edge Gateway Architecture

**Дата:** 2026-08-18  
**Статус:** RESEARCH / ARCHITECTURE PLAN / НЕ PRODUCTION ACTIVATION  
**Ветка:** `research/edge-gateway-architecture`  
**Base:** `main @ c58339c30e6d7e708a06c41e59208bd45f0709a4`  
**Назначение:** зафиксировать целевую клиентскую сетевую границу для бесшовного distributed world с несколькими geographically distributed proxy/gateway процессами.

Этот документ не активирует новый production runtime, не заменяет Project Control, не изменяет ownership semantics и не разрешает перенос SM0 research-кода напрямую в product line. SM0 используется как semantic/evidence donor для authority handoff, projection, fault/recovery и multi-authority view composition.

---

## 1. Решение

Клиент не должен знать физическую topology simulation servers и не должен переключать соединение при переходе между authority regions.

Целевая форма:

```text
                           World Directory / Route Resolver
                          /            |             \
                         /             |              \
                        v              v               v
                 Authority A     Authority B      Authority C
                      ^               ^                ^
                      |               |                |
                 projection       PRIMARY        projection
                      \               |                /
                       \              |               /
                        +-----------------------------+
                        |        EDGE GATEWAY         |
                        |  non-authoritative runtime  |
                        +-----------------------------+
                                      |
                             one stable session
                                      |
                                    Client
```

В production topology Edge Gateway не один. Несколько gateway разворачиваются в разных географических регионах реальной планеты:

```text
                Global Gateway Discovery
                    /       |       \
                   /        |        \
            Gateway EU  Gateway US  Gateway AP
                |           |           |
             clients     clients      clients
                \           |           /
                 \          |          /
                  distributed authorities
```

Клиент выбирает лучший доступный gateway прежде всего по реальному RTT, но выбор должен учитывать health, packet loss, load/capacity и hysteresis, чтобы соединение не переключалось из-за случайных колебаний ping.

После выбора gateway клиент работает только с ним. Gateway самостоятельно:

- поддерживает необходимые connections к authority servers;
- получает route/ownership information;
- маршрутизирует commands;
- агрегирует read-only projections;
- выполняет client-facing interest/LOD/bandwidth composition;
- переключает PRIMARY/OBSERVER routes после committed authority handoff;
- скрывает physical authority changes от клиента.

---

## 2. Главный invariant

```text
Gateway знает:
- ЧТО клиент должен видеть;
- КУДА должна быть направлена операция;
- КАКОЙ authority route сейчас действителен.

Gateway НЕ решает:
- КТО canonically владеет state;
- КОГДА ownership transfer считается committed;
- КАК gameplay изменяет canonical state.
```

Gateway никогда не становится:

- вторым Item Graph;
- вторым gameplay state store;
- physics authority;
- Construction/Matter/Ecology authority;
- источником AuthorityEpoch;
- источником ownership truth.

Canonical ownership остаётся у Directory + authority protocol.

---

## 3. Почему gateway должен быть отдельной сущностью

Без gateway seamless player handoff легко превращается в client networking handoff:

```text
Client -> Server A
          crossing
Client -> Server B
```

Это смешивает две разные операции:

1. смену canonical writer;
2. смену client transport endpoint.

Целевая модель разделяет их:

```text
Authority handoff:
A/epoch 71 -> B/epoch 72

Client connection:
Gateway session remains unchanged
```

Следствие: authority может меняться без reconnect screen, без пересоздания UI, без изменения player identity и без потери input sequence.

---

## 4. Multi-gateway как базовое требование

Gateway architecture с самого начала должна считать, что gateway процессов много.

Новые базовые identifiers:

```text
GatewayId
GatewayRegionId
ClientSessionId
GatewaySessionId
AuthorityId
AuthorityEpoch
EntityId
OperationId
TransferId
RouteRevision
```

`ClientSessionId` не должен быть производным от `GatewayId`. Это позволяет в будущем перенести клиентскую session на другой gateway после crash, draining или сильной деградации сети без изменения canonical player/entity identity.

### 4.1 Gateway Catalog

Bootstrap/discovery возвращает клиенту список кандидатов:

```text
GatewayCandidate
{
    gateway_id
    region_id
    public_endpoint
    protocol_version
    health_epoch
    capacity_class
    signed_metadata
}
```

Client не доверяет произвольному gateway address. Catalog должен быть authenticatable/signed.

### 4.2 Выбор gateway

Минимальный production-oriented flow:

```text
1. Client получает 3-5 здоровых candidates.
2. Параллельно делает короткий probe.
3. Измеряет RTT + loss/jitter.
4. Учитывает advertised load/capacity.
5. Выбирает лучший healthy candidate.
6. Открывает stable session.
7. Не переключается при небольших колебаниях ping.
```

Primary signal — RTT.

Рекомендуемая conceptual score:

```text
score = smoothed_rtt_ms
      + loss_penalty
      + jitter_penalty
      + load_penalty
```

Конкретные коэффициенты являются отдельным tuning checkpoint и не должны вшиваться в domain contracts.

### 4.3 Hysteresis

Gateway switching не должен происходить, если новый gateway лишь немного быстрее текущего.

Необходимы:

- minimum improvement threshold;
- minimum dwell time;
- health override;
- explicit draining override.

Иначе мобильный клиент может постоянно прыгать между двумя edge regions.

---

## 5. Gateway connection model

Нельзя повторять topology `one client -> every backend server`.

Gateway открывает upstream relationship только при реальной необходимости:

- authority является PRIMARY хотя бы для одного local client;
- authority предоставляет OBSERVER projection;
- существует handoff candidate;
- существует cross-authority interaction;
- нужен boundary/reference-frame stream.

Целевая форма:

```text
10000 clients on Gateway EU

Gateway EU <---- one/shared transport ----> Authority A
           <---- one/shared transport ----> Authority B
           <---- one/shared transport ----> Authority C

inside transport:
- logical client routes
- projection subscriptions
- command streams
- handoff/control streams
```

Physical transport session и logical client route являются разными сущностями.

Это позволяет держать physical connection count ближе к:

```text
O(active gateway-authority pairs)
```

а не:

```text
O(clients * authorities)
```

---

## 6. Route model

Для каждого client/entity gateway поддерживает logical routes.

```text
ClientAuthorityRoute
{
    client_session_id
    entity_id
    authority_id
    authority_epoch
    route_revision
    role
    route_state
    interest_anchor
    reference_frame_id
    last_input_sequence
}
```

Минимальные роли:

```text
PRIMARY
OBSERVER
```

Возможные lifecycle states:

```text
RESOLVING
CONNECTING
WARM
ACTIVE
DEGRADED
DRAINING
CLOSED
```

PRIMARY означает только: текущий route для authoritative operations данного subject/scope.

PRIMARY не является отдельной ownership truth. Он должен быть производным от подтверждённого Directory/AuthorityEpoch state.

---

## 7. Gateway-mediated authority handoff

Пример player `player/42`, owner A epoch 71, crossing A -> B.

### До crossing

```text
Directory:
player/42 owner=A epoch=71

Gateway:
A = PRIMARY
B = OBSERVER/WARM
```

### Phase 1 — prewarm

B заранее получает необходимые immutable/projection/context данные.

### Phase 2 — canonical handoff

Authority protocol выполняет доказанный SM0-подобный transfer:

```text
A FREEZE
A -> B PREPARE
Directory commit A/71 -> B/72
A RETIRE
B ACTIVATE
```

Точные durability/fault semantics остаются authority-layer responsibility.

### Phase 3 — route flip

Только после подтверждённого committed ownership state Gateway принимает route update:

```text
player/42
primary_authority = B
authority_epoch = 72
route_revision = N+1
```

и меняет роли:

```text
A PRIMARY  -> OBSERVER
B OBSERVER -> PRIMARY
```

### Client-visible result

```text
client connection changes: 0
client session changes:    0
player identity changes:   0
UI recreation:             0
```

---

## 8. Command routing

Gateway не должен broadcast gameplay operation всем authorities.

Client operation должна сохранять end-to-end identity:

```text
OperationEnvelope
{
    operation_id
    client_session_id
    subject_entity_id
    expected_authority_id
    expected_authority_epoch
    expected_state_revision
    operation_kind
    payload
    payload_hash
}
```

Gateway:

1. валидирует transport/session envelope;
2. resolve/fence route;
3. отправляет operation ровно нужному authority;
4. сохраняет `operation_id` end-to-end;
5. не меняет domain payload semantics;
6. возвращает deterministic stale-route result или выполняет bounded reroute только по формально разрешённому contract.

Authority остаётся единственным местом, которое решает, разрешена ли gameplay mutation.

---

## 9. Multi-authority client view

SM0 P5/P10 используется как donor.

Gateway получает несколько read-only streams:

```text
Authority A projection
Authority B projection
Authority C representation
        |
        v
Gateway View Store / Composer
        |
        + dynamic entities
        + coarse/fine representations
        + priority
        + distance
        + bandwidth budget
        + cache
        + degraded/stale-safe presentation
        |
        v
Client
```

Gateway View Store должен быть:

```text
READ_ONLY
DERIVED
EPHEMERAL
RECONSTRUCTIBLE
NON-CANONICAL
```

Каждый foreign source fence'ится минимум по:

```text
source_authority_id
source_authority_epoch
projection_sequence/state_revision
checksum/hash
```

Presentation object никогда не становится mutation target.

---

## 10. Interest и upstream subscriptions

Gateway не подписывается на весь мир.

Interest pipeline:

```text
client camera/player/reference-frame interest
            |
            v
Gateway Interest Planner
            |
      +-----+------+
      |            |
      v            v
Authority A     Authority B
fine entities  coarse reps
```

Gateway может агрегировать interest нескольких клиентов перед отправкой upstream subscription, чтобы не создавать тысячи одинаковых subscriptions.

Нужны как минимум:

- client interest budget;
- authority subscription budget;
- priority classes;
- distance/visibility/reference-frame filters;
- coarse/fine representation selection;
- cache-aware artifact delivery;
- backpressure isolation.

---

## 11. Gateway failure и rehome

Даже если первый runtime checkpoint не реализует gateway migration, contracts должны не запрещать его.

Целевая future flow:

```text
Client -> Gateway EU-1
          crash
Client -> Gateway EU-2
```

При этом:

```text
ClientSessionId same
PlayerEntityId same
Authority ownership same
AuthorityEpoch same or monotonically advanced by authority only
OperationId dedup remains valid
```

Gateway не должен хранить единственную durable копию данных, необходимых для восстановления canonical session/gameplay state.

Для fast rehome допустим отдельный resumable gateway-session token, но token не должен давать gateway право самостоятельно создавать ownership state.

---

## 12. Gateway draining и load balancing

Gateway может перейти в `DRAINING`:

- новые clients его не выбирают;
- существующие sessions либо завершаются естественно, либо получают controlled rehome;
- authority routes продолжают обслуживаться до завершения migration;
- draining не меняет canonical world ownership.

Load signal используется как вторичный фактор выбора gateway, чтобы клиенты не концентрировались на одном географически близком, но перегруженном endpoint.

---

## 13. Security boundary

Gateway становится публичной edge-границей и должен считаться untrusted относительно canonical authority.

Минимальные принципы:

- authenticated client session;
- authenticated gateway identity;
- mutually authenticated upstream gateway-authority transport;
- signed/authenticated gateway catalog;
- replay-safe `OperationId`;
- end-to-end preservation of AuthorityEpoch/EntityId/OperationId;
- gateway не может mint ownership lease;
- gateway не может повышать AuthorityEpoch;
- malformed/stale route updates fail closed;
- per-client rate limiting и abuse isolation;
- observability для spoof/replay/stale-route attempts.

Конкретный transport/TLS/QUIC/ENet implementation является отдельным решением. High-level semantics не должны зависеть от одного transport.

---

## 14. Observability

Gateway обязательно публикует metrics минимум по четырём уровням.

### Client edge

```text
client_rtt_ms
client_jitter_ms
client_loss
client_session_age
gateway_selection_score
```

### Gateway runtime

```text
active_clients
active_logical_routes
active_upstream_authorities
queue_depth
bytes_in/out
cpu/load indicator
```

### Authority routes

```text
primary_routes
observer_routes
route_resolve_latency
route_revision
stale_route_rejections
handoff_route_flip_latency
```

### Correctness

```text
identity_changes
split_brain_observations
duplicate_operation_commits
same_epoch_mutation_conflicts
projection_epoch_rollbacks
```

Correctness counters, кроме ожидаемых test injections/rejections, должны оставаться нулевыми.

---

## 15. Предлагаемый roadmap EG0-EG8

### EG0 — Contract Freeze

Только contracts/design/tests skeleton:

- GatewayId/RegionId;
- ClientSessionId independent from GatewayId;
- GatewayCatalog;
- route roles/states;
- route update fencing;
- operation envelope;
- no production authority mutation.

### EG1 — Single Gateway / Single Authority Transparent Path

```text
Client -> Gateway -> Authority A
```

Client больше не подключается непосредственно к authority, но gameplay result эквивалентен direct path.

### EG2 — Multi-Authority View Composition

```text
A PRIMARY
B OBSERVER
```

Один client session получает единую presentation из двух authorities; foreign state остаётся read-only.

### EG3 — Gateway-Mediated Handoff

```text
A PRIMARY -> OBSERVER
B OBSERVER -> PRIMARY
```

Route flip только после committed higher AuthorityEpoch. Client transport не меняется.

### EG4 — Multi-Gateway Discovery and RTT Selection

Три gateway процесса с разными latency/loss/load profiles. Client автоматически выбирает лучший healthy endpoint и сохраняет stickiness.

### EG5 — Gateway Failure / Session Rehome

Активный gateway аварийно завершается. Client подключается к alternate gateway, сохраняет ClientSessionId/PlayerEntityId и не создаёт duplicate canonical mutation.

### EG6 — Shared Upstream Pooling and Multiplexing

Много clients используют общий gateway-authority transport. Проверяются bounded physical connections, per-client isolation и backpressure.

### EG7 — Geo/WAN Matrix and Load-Aware Selection

Несколько gateways + authorities под controlled latency/jitter/loss/reorder/bandwidth. Проверяется выбор edge endpoint, route latency, handoff и failover.

### EG8 — Production Convergence / Framework Boundary

После доказанной semantics:

- generic gateway contracts -> reusable network runtime;
- simulator-specific adapters остаются в simulator layer;
- SM0 остаётся frozen evidence donor;
- production N3-N6 roadmap корректируется отдельным approved control checkpoint.

---

## 16. Что не делать

Без отдельного Work Order не следует:

- переносить SM0 implementation напрямую в main;
- переписывать N3-N6 production runtime;
- создавать второй World Directory;
- создавать gateway-owned canonical player state;
- подключать gateway ко всем authorities мира;
- hardcode географию Earth в generic gateway core;
- привязывать contracts к конкретному cloud provider;
- делать framework extraction до доказанной runtime semantics.

---

## 17. Связь с существующим проектом

Этот design уточняет будущий seamless track:

```text
старое conceptual N5:
Client active route A + warm route B

новое target N5/EG3:
Client stable route -> Gateway
Gateway primary route A + observer/warm route B
```

Неизменными остаются:

- single writer;
- stable entity identity;
- authority epoch fencing;
- replay-safe transfer;
- read-only foreign replicas;
- presentation != canonical state;
- transport-neutral high-level semantics.

Связанные donors:

- `docs/network/SEAMLESS_WORLD_ROADMAP_RU.md`;
- `docs/plans/DISTRIBUTED_RUNTIME_FOUNDATION_ROADMAP_RU.md`;
- SM0 PR #102 and its P5/P7/P8/P9/P10/P11 evidence;
- future Network Framework-Ready policy after controlled promotion into the active product line.

External architecture inspiration: Unreal Engine 5.8 `MultiServerReplication` / `UProxyNetDriver` / `UMultiServerNode`, использованные только как источник архитектурных идей. Код Unreal не копируется.

---

## 18. Архитектурный критерий успеха

Система считается идущей в правильном направлении, если одновременно верны четыре утверждения:

```text
1. Client знает один stable gateway endpoint, а не simulation topology.
2. Gateway может видеть много authorities, но не владеет canonical world state.
3. Authority handoff не требует client reconnect.
4. Количество gateway-authority physical connections определяется реальным interest/routing need, а не числом clients * числом world servers.
```
