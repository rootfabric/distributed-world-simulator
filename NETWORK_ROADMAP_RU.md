# PlanetSimulator — current network and multiplayer roadmap

Принятая architecture-база: `v16.9.4-architecture-a2-networked-gameplay`.
Принятый roadmap checkpoint: `v16.9.5-roadmap-single-server-multiplayer-first`.
Принятый runtime checkpoint: `v16.10.0-runtime-m1-unified-networked-gameplay-core`.
Текущий runtime candidate: `v16.10.1-runtime-m2-dedicated-graphical-client`.

```text
A0 → H0 → A1 → S0 → T1 → B0 → M0 → S1 accepted
H1 → H2 → H3 → A2 → M1 accepted
M2 current candidate
M3 next after M2
M4 → M5 → M6 → A3 planned
B1/B2 deferred until A3
N3–N6 blocked until A3 and B2
```

## M2

```text
headless dedicated server
        │ ENet
ordinary graphical Godot client
```

Dedicated использует единый M1 `NetworkedGameplayService`. Graphical client содержит только transport, command gateway, replica store, `LunarPlayer` presentation и local input. Movement, inventory и hotbar проходят authoritative path; disconnect/reconnect сохраняет `player/local-astronaut` и увеличивает ownership epoch.

Автоматическая process-проверка запускает настоящий graphical client через X11/renderer, а не `--headless`, и повторяет запуск против того же server для проверки reconnect.

Следующий этап после принятия M2 — `M3 Dedicated server + two graphical clients` с remote player presentation и interpolation.

Authoritative sources:

- `config/network/network-roadmap.v1.json`;
- `config/network/dedicated-graphical-client.v1.json`;
- `config/network/networked-gameplay-core.v1.json`;
- `config/network/single-server-multiplayer-roadmap.v1.json`;
- `docs/architecture/M2_DEDICATED_GRAPHICAL_CLIENT_RU.md`.
