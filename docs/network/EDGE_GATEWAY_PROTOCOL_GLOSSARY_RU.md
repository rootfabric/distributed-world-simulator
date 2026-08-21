# Edge Gateway Protocol Glossary — EG0 supplement

Статус: **EG0 CANDIDATE TERMINOLOGY / NOT CANONICAL UNTIL REVIEWED**

## WorldConnection

Единственный логический client-facing world transport в V0 baseline. Физический endpoint относится к Edge Gateway, а не к simulation authority.

## GatewaySessionId

Ephemeral/logical identity attachment клиента к Gateway fabric. Не является `ClientSessionId`, `PlayerId` или `PlayerEntityId`.

## ClientWorldFrame

Versioned transport-neutral frame между client-facing WorldConnection и Gateway routing boundary. Содержит channel, sequence и versioned payload.

## GatewayIngressEnvelope

Server-side routing envelope для frame направления `CLIENT_TO_WORLD`. Добавляет Gateway/session/backend-route metadata, но не меняет gameplay payload.

## GatewayEgressEnvelope

Server-side routing envelope для frame направления `WORLD_TO_CLIENT`. Используется для authoritative response/snapshot и projection fan-in.

## session_slot

Короткий ephemeral multiplex key внутри shared Gateway->Server link. Может переиспользоваться только после корректного detach/fencing. Никогда не является player identity.

## BackendLinkId

Identity физического/логического Gateway->Server transport link. Один link может обслуживать много `GatewaySessionId`.

## RouteRevision

Монотонная ревизия Gateway routing binding. Не является `AuthorityEpoch` и сама не даёт mutation authority.

## GatewayRouteBinding

Ephemeral mapping `GatewaySessionId -> observed authority/server route`. Это cache/routing metadata, а не ownership truth.

## ProjectionSubscription

Read-only запрос Gateway к projection source для конкретного session interest. `read_only=true` обязателен.

## GatewayDescriptor

Locator-facing описание Gateway candidate: Gateway instance, POP, endpoint identity, health/capacity hints и locator revision. Не раскрывает simulation-server endpoint.

## WORLD_PROJECTION

Client-facing read-only channel, через который Gateway агрегирует neighboring/macro presentation data в тот же `WorldConnection`.

## Главное правило

```text
GatewaySessionId != PlayerId
RouteRevision != AuthorityEpoch
Gateway routing metadata != mutation authority
Projection != canonical gameplay truth
```
