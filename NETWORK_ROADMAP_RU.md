# PlanetSimulator — current network and multiplayer roadmap

Принятая architecture-база: `v16.9.4-architecture-a2-networked-gameplay`.
Принятый roadmap checkpoint: `v16.9.5-roadmap-single-server-multiplayer-first`.
Принятый runtime checkpoint: `v16.10.3-domain-m4-canonical-shared-gameplay`.
Текущий checkpoint-кандидат: M5 Graphical Multiplayer Acceptance поверх pre-M5 boundary и `main @ 2879fdb`.

```text
A0 → H0 → A1 → S0 → T1 → B0 → M0 → S1 accepted
H1 → H2 → H3 → A2 → M1 → M2 → M3 → M4 accepted
M5 candidate implemented
M6 → A3 planned
B1/B2 deferred until A3
N3–N6 blocked until A3 and B2
```

## M5 graphical multiplayer acceptance

Подготовительный слой связывает существующий inventory UI с canonical M4 Item
Graph только через `ITEM_COMMAND` и replica snapshots. Он включает read-only
projection, command adapter, transient cursor/pending overlay, networked
inventory shell и изолированные user-data/MCP settings.

M5 доказывает UI-driven действия двух graphical clients,
contention, reconnect и checksum convergence.

## Историческая M3/M4 база

```text
headless dedicated server
        │ ENet
        ├── graphical client A: LunarPlayer + remote B presenter
        └── graphical client B: LunarPlayer + remote A presenter
```

Dedicated использует единый M1 `NetworkedGameplayService`. Оба клиента содержат только transport, command gateway, replica store и presentation. `RemotePlayerPresenter` не имеет input authority, интерполирует authoritative transform и применяет replicated orientation/flashlight state.

Автоматическая process-проверка запускает два обычных graphical Godot процесса через X11/renderer, подтверждает взаимное движение, disconnect A без остановки B, reconnect A к прежней entity с ownership epoch `1 → 2` и checksum convergence server/A/B.

Исторически M3 подготовил presentation/ownership vertical, а принятый M4 добавил canonical Item Graph, authoritative item commands и двухклиентский contention. M5 использует подготовленную UI/replica boundary и не открывает новый gameplay path.

Authoritative sources:

- `config/network/network-roadmap.v1.json`;
- `config/network/m5-graphical-acceptance-preparation.v1.json`;
- `config/network/canonical-shared-gameplay.v1.json`;
- `config/network/dedicated-graphical-multiplayer.v1.json`;
- `config/network/dedicated-graphical-client.v1.json`;
- `config/network/networked-gameplay-core.v1.json`;
- `config/network/single-server-multiplayer-roadmap.v1.json`;
- `docs/architecture/M5_GRAPHICAL_MULTIPLAYER_ACCEPTANCE_RU.md`;
- `docs/architecture/M5_GRAPHICAL_ACCEPTANCE_PREPARATION_RU.md`;
- `docs/architecture/M4_PRE_M5_HANDOFF_RU.md`;
- `docs/architecture/M3_DEDICATED_GRAPHICAL_MULTIPLAYER_RU.md`.
