# PlanetSimulator — current network and multiplayer roadmap

Принятая architecture-база: `v16.9.4-architecture-a2-networked-gameplay`.
Принятый roadmap checkpoint: `v16.9.5-roadmap-single-server-multiplayer-first`.
Текущий runtime candidate: `v16.10.0-runtime-m1-unified-networked-gameplay-core`.

```text
A0 → H0 → A1 → S0 → T1 → B0 → M0 → S1 accepted
H1 → H2 → H3 → A2 accepted
M1 current candidate
M2 next after M1
M3 → M4 → M5 → M6 → A3 planned
B1/B2 deferred until A3
N3–N6 blocked until A3 and B2
```

## M1

H1/H2/H3 сведены к одной production composition root:

```text
NetworkedGameplayService
├─ PlayerRegistry / PlayerOwnershipService / PlayerMovementService
├─ ItemGraphService / ContainerInteractionService / MountInteractionService
├─ CommandResultRouter
└─ ReplicationPublisher
```

H1 и H3 являются adapters над одним сервисом; H2 использует его общий ownership component. Wire validators вынесены из authority implementations. `A2-D01` и `A2-D02` закрыты. `A2-D03` и `A2-D04` остаются gates M3–M6.

Следующий этап после принятия M1 — `M2 Dedicated server + one graphical client`.

Authoritative sources:

- `config/network/network-roadmap.v1.json`;
- `config/network/networked-gameplay-core.v1.json`;
- `config/network/networked-gameplay-architecture.v1.json`;
- `config/network/single-server-multiplayer-roadmap.v1.json`;
- `docs/architecture/M1_UNIFIED_NETWORKED_GAMEPLAY_CORE_RU.md`.
