# PlanetSimulator — current network and multiplayer roadmap

Принятая runtime-база: `v16.9.3-runtime-h3-dedicated-multiplayer`.
Принятая architecture-база: `v16.9.4-architecture-a2-networked-gameplay`.
Текущий roadmap candidate: `v16.9.5-roadmap-single-server-multiplayer-first`.

```text
A0 → H0 → A1 → S0 → T1 → B0 → M0 → S1 accepted
H1 → H2 → H3 → A2 accepted
M1 next
M2 → M3 → M4 → M5 → M6 → A3 planned
B1/B2 deferred until A3
N3–N6 blocked until A3 and B2
```

## Утверждённый основной порядок

```text
A2
└─ M1 Unified Networked Gameplay Core
   └─ M2 Dedicated + 1 graphical client
      └─ M3 Dedicated + 2 graphical clients
         └─ M4 Canonical shared gameplay over ENet
            └─ M5 Graphical multiplayer acceptance
               └─ M6 Dedicated persistence/recovery
                  └─ A3 Single-server multiplayer freeze
                     └─ B1 → B2 → N3 → N4 → N5 → N6
```

M1–M6 закрывают A2-D01…D04. B1 остаётся допустимым B0 adapter, но переносится после A3. NATS не используется для обычного graphical realtime traffic и не создаёт новый gameplay path.

Authoritative sources:

- `config/network/network-roadmap.v1.json`;
- `config/network/single-server-multiplayer-roadmap.v1.json`;
- `docs/plans/SINGLE_SERVER_MULTIPLAYER_ROADMAP_RU.md`.
