# EG0 — Edge Gateway Contracts / DTO / Fixtures — Design Brief

Статус: **STACKED HIGH-RISK IMPLEMENTATION CANDIDATE / NOT ACCEPTED / NO P6 AUTHORITY**

Зависимость: draft control PR `#185`.

Exact stacked base:

`c5d7d0d682181f0a796d0e059508a1fdfe91b6e1`

Branch:

`feature/eg0-edge-gateway-contracts-r1`

## Проблема

До реального `Client -> Gateway -> Server` процесса необходимо зафиксировать transport-independent DTO, иначе EG1 рискует смешать transport peer/session identity с PlayerId, authority ownership и gameplay semantics.

Опасные равенства, которые EG0 обязан не допустить:

```text
TransportConnectionId != GatewaySessionId
GatewaySessionId       != ClientSessionId
ClientSessionId        != PlayerId
PlayerId               != PlayerEntityId
session_slot            != PlayerId
backend_peer_id         != PlayerId
RouteRevision           != AuthorityEpoch
```

## Текущее состояние

Проект уже имеет JSON-safe network DTO utilities и transport-independent message-bus contracts. Edge Gateway contract family отсутствует. Draft #185 определяет будущую модель одного клиентского `WorldConnection`, shared Gateway->Server links и Gateway projection fan-in.

## Требуемое состояние

EG1 должен получить строгий, versioned и тестируемый contract surface:

- `ClientWorldFrame`;
- `GatewayIngressEnvelope`;
- `GatewayEgressEnvelope`;
- `GatewaySessionBinding`;
- `GatewayRouteBinding`;
- `ProjectionSubscription`;
- `GatewayDescriptor`;
- channel/direction/role enums;
- canonical JSON fixtures.

## Рассмотренные варианты

1. Проксировать существующие Godot RPC без project envelope — отклонено: transport metadata станет частью gameplay semantics.
2. Разбирать и заново собирать gameplay operation внутри Gateway — отклонено: Gateway сможет случайно заменить `OperationId`/input sequencing.
3. Сразу перейти на opaque binary/QUIC wire contract — отклонено: слишком много переменных до доказательства semantics.
4. Versioned project DTO поверх существующих canonical JSON utilities — выбран.

## Выбранный дизайн

`ClientWorldFrame` — клиентская семантическая единица. `GatewayIngressEnvelope` и `GatewayEgressEnvelope` добавляют только route/session metadata снаружи frame.

Hard rule:

```text
Gateway routes the frame.
Gateway does not reinterpret canonical gameplay identity.
```

Для `WORLD_OPERATION` canonical `operation_id` находится внутри `ClientWorldFrame.payload` и проходит Gateway без замены.

`WORLD_PROJECTION` разрешён только как `WORLD_TO_CLIENT` read-only поток от `PROJECTION` source.

## Владельцы и зависимости

- NX — transport/replication foundation;
- AUTHORITY/Directory — authority ownership/epoch truth;
- IAM — account/client-session identity;
- domain owners — canonical gameplay mutation;
- EG0 — только transport-neutral gateway contract donor, не новый owner.

## Non-goals EG0

- реальный Gateway process;
- ENet listener/backend tunnel;
- auth implementation;
- Directory mutation/ownership decision;
- shared tunnel scheduler;
- A->B handoff;
- Gateway rehome;
- QUIC selection;
- P6 runtime mutation;
- acceptance `EDGE_GATEWAY_FOUNDATION_ACCEPTED`.

## Риски

- identity aliasing;
- Gateway route metadata becoming mutation authority;
- projection write path;
- replacing OperationId during forwarding;
- accidental transport-specific fields in domain payload;
- protocol drift before EG1.

## Validation plan

1. strict exact-field validation;
2. canonical ID namespaces;
3. canonical JSON round-trip;
4. runtime-object rejection;
5. OperationId preservation;
6. ACTIVE-only ingress for mutating client channels;
7. PROJECTION-only `WORLD_PROJECTION` egress;
8. explicit read-only projection subscription;
9. descriptor rejects simulation-server endpoint leakage;
10. fixture suite validates all canonical examples.

## Review gate

Это HIGH-risk public protocol candidate. Implementer не может self-accept.

До перехода EG0 в accepted требуется:

```text
#185 canonical dependency resolved
focused tests PASS on exact head
Project Control SUCCESS
fresh independent Reviewer PASS
independent Verifier PASS
Director verdict
```

До этого EG1 не получает canonical dispatch.
