# PlanetSimulator — current network and multiplayer roadmap

Принятая architecture-база: `v16.9.4-architecture-a2-networked-gameplay`.
Принятый roadmap checkpoint: `v16.9.5-roadmap-single-server-multiplayer-first`.
Принятый runtime checkpoint: `v16.10.4-testing-m5-graphical-multiplayer-acceptance` (`ACCEPTED`, delivery `fix1`).
Текущий checkpoint-кандидат: `v16.10.5-persistence-m6-dedicated-recovery` поверх принятого M5.

```text
A0 → H0 → A1 → S0 → T1 → B0 → M0 → S1 accepted
H1 → H2 → H3 → A2 → M1 → M2 → M3 → M4 → M5 accepted
M6 candidate implemented
A3 planned
B1/B2 deferred until A3
N3–N6 blocked until A3 and B2
```

## M6 dedicated persistence and recovery

M6 связывает R3.1 atomic authoritative checkpoint с реальным dedicated `NetworkedGameplayService`. JOIN/MOVE/PRESENTATION/ITEM_COMMAND/LEAVE подтверждаются только после durable commit. Checkpoint восстанавливает player identities/state, ownership epochs, revision/tick, canonical Item Graph, replay ledgers и committed outbox.

Transport sessions, peer mapping, open-container access и cursor/drag overlay остаются transient. После restart players disconnected; reconnect привязывает новую session к прежней entity и увеличивает ownership epoch. Exact committed replay возвращается с `replay=true`, не мутирует state и не создаёт второй checkpoint.

M5 Graphical Multiplayer Acceptance принят delivery `fix1`; M6 является текущим candidate и закрывает `A2-D04` только после локального double-precision acceptance.

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

- `config/network/dedicated-persistence-recovery.v1.json`;
- `docs/architecture/M6_DEDICATED_PERSISTENCE_RECOVERY_RU.md`;
- `docs/checkpoints/2026-07-31_V16_10_5_PERSISTENCE_M6_DEDICATED_RECOVERY_RU.md`;
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
