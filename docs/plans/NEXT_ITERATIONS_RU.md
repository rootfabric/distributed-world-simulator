# Ближайшие итерации после M2

Принятый M2: `v16.10.1-runtime-m2-dedicated-graphical-client` (`ACCEPTED_WITH_GATES`).
Текущий candidate: `v16.10.2-runtime-m3-dedicated-graphical-multiplayer`.

```text
M3 — Dedicated + 2 graphical clients — current candidate
M4 — Canonical shared gameplay over ENet — next
M5 — Graphical Multiplayer Acceptance
M6 — Dedicated persistence and recovery
A3 — Single-server multiplayer audit/freeze
B1/B2 — after A3
N3–N6 — after B2
```

## Текущая ветка

```text
feature/m3-dedicated-graphical-multiplayer
checkpoint: v16.10.2-runtime-m3-dedicated-graphical-multiplayer
```

M3 запускает два одновременных graphical clients против headless dedicated server, добавляет `RemotePlayerPresenter`, взаимную authoritative movement/presentation replication, disconnect/reconnect и checksum convergence.

Полный scope и acceptance: `SINGLE_SERVER_MULTIPLAYER_ROADMAP_RU.md`.
