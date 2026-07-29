# PlanetSimulator — текущая distributed runtime roadmap

Текущий принятый checkpoint: `v16.9.0-simulation-s1-distributed-compute-fix1`.

```text
N0–N2 accepted
R3.1 accepted
A0 accepted
H0 accepted
A1 accepted
S0 accepted
T1 accepted
B0 accepted
M0 accepted
S1 accepted
```

Утверждён следующий порядок:

```text
S1 ACCEPTED
│
├─ H1  Playable listen-host
├─ H2  Dedicated server + 1 graphical client
├─ H3  Dedicated server + 2 graphical clients
├─ A2  Networked gameplay architecture checkpoint
│
├─ B1  NATS Core adapter
├─ B2  JetStream/outbox delivery
│
├─ P0  Population Field
├─ D1  Remote worker MVP
│
├─ N3  World Directory + 2 authorities
├─ N4  Generic object handoff
├─ N5  Seamless player handoff
└─ N6  Ghosts + interest management
```

Ближайшая цель — не новый broker adapter, а перенос существующей игры на доказанный client/server path. H1–H3 должны последовательно доказать playable listen-host, отдельный dedicated server с одним graphical client и dedicated multiplayer минимум с двумя graphical clients.

После H3 выполняется обязательный `A2` audit/freeze checkpoint. Только затем начинается B1.

Подробности:

- `docs/plans/PLAYABLE_NETWORK_MILESTONES_RU.md`;
- `docs/checkpoints/2026-07-29_POST_S1_PLAYABLE_NETWORK_ROADMAP_RU.md`;
- `docs/plans/DISTRIBUTED_RUNTIME_FOUNDATION_ROADMAP_RU.md`;
- `docs/network/SEAMLESS_WORLD_ROADMAP_RU.md`.
