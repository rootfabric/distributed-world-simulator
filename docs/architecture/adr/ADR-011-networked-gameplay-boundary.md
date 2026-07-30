# ADR-011: Единый semantic gameplay boundary для всех runtime topology

- Статус: принято как решение A2, реализация частично консолидирована
- Дата: 2026-07-30
- Checkpoint: `v16.9.4-architecture-a2-networked-gameplay`

## Контекст

H1 доказал graphical listen-host и полный Item Graph path. H2 доказал ownership/reconnect через отдельный ENet client. H3 доказал два peer, movement replication и contention. Эти этапы используют разные authority fixtures и не должны превратиться в три production domain paths.

## Решение

Во всех topology действует один semantic pipeline:

```text
ClientIntent → VersionedCommand → AuthorityMutation
→ TargetedResult + Snapshot/Delta → ClientReplica → Presentation
```

Topology выбирает только composition и transport adapter:

- listen-host: loopback DTO boundary;
- dedicated: ENet peer;
- future cluster: route к authority через принятые transport/message-bus ports.

Identity, permission, replay, revision, authority и ownership fencing не зависят от topology.

До N3 отдельные H1/H2/H3 authority fixtures должны быть сведены за один `NetworkedGameplayService` contract, а DTO validators вынесены из authority implementations.

## Последствия

- B1 может развивать B0 adapters без изменения gameplay;
- H1 остаётся canonical full gameplay evidence;
- H2/H3 остаются transport/ownership/multiplayer evidence, но не образуют второй домен;
- multi-authority work заблокирован до closure A2-D01…A2-D04;
- production prediction/interpolation остаётся presentation policy, не canonical state.

## Запрещённые обходы

- topology-specific command или aggregate schema;
- прямой client/UI вызов authority/domain service;
- broker subject в domain state;
- transport session как player identity;
- локальная client mutation с последующим «best effort» подтверждением;
- развитие H3 shared-item fixture как отдельного production Item Graph.
