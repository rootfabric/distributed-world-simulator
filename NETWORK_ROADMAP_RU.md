# PlanetSimulator — current network and multiplayer roadmap

Принятая architecture-база: `v16.9.4-architecture-a2-networked-gameplay`.
Принятый roadmap checkpoint: `v16.9.5-roadmap-single-server-multiplayer-first`.
Принятый runtime checkpoint: `v16.10.1-runtime-m2-dedicated-graphical-client` (`ACCEPTED_WITH_GATES`).
Текущий runtime candidate: `v16.10.2-runtime-m3-dedicated-graphical-multiplayer`.

```text
A0 → H0 → A1 → S0 → T1 → B0 → M0 → S1 accepted
H1 → H2 → H3 → A2 → M1 accepted
M2 accepted with gates
M3 current candidate
M4 next after M3
M5 → M6 → A3 planned
B1/B2 deferred until A3
N3–N6 blocked until A3 and B2
```

## M3

```text
headless dedicated server
        │ ENet
        ├── graphical client A: LunarPlayer + remote B presenter
        └── graphical client B: LunarPlayer + remote A presenter
```

Dedicated использует единый M1 `NetworkedGameplayService`. Оба клиента содержат только transport, command gateway, replica store и presentation. `RemotePlayerPresenter` не имеет input authority, интерполирует authoritative transform и применяет replicated orientation/flashlight state.

Автоматическая process-проверка запускает два обычных graphical Godot процесса через X11/renderer, подтверждает взаимное движение, disconnect A без остановки B, reconnect A к прежней entity с ownership epoch `1 → 2` и checksum convergence server/A/B.

Следующий этап после принятия M3 — `M4 Canonical shared gameplay over ENet` с полным H1 Item Graph и двухклиентским contention.

Authoritative sources:

- `config/network/network-roadmap.v1.json`;
- `config/network/dedicated-graphical-multiplayer.v1.json`;
- `config/network/dedicated-graphical-client.v1.json`;
- `config/network/networked-gameplay-core.v1.json`;
- `config/network/single-server-multiplayer-roadmap.v1.json`;
- `docs/architecture/M3_DEDICATED_GRAPHICAL_MULTIPLAYER_RU.md`.
