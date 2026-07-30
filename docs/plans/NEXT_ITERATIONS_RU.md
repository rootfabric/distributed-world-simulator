# Ближайшие итерации после M1

Принятый M1: `v16.10.0-runtime-m1-unified-networked-gameplay-core`.
Текущий candidate: `v16.10.1-runtime-m2-dedicated-graphical-client`.

```text
M2 — Dedicated + 1 graphical client — current candidate
M3 — Dedicated + 2 graphical clients — next
M4 — Canonical shared gameplay over ENet
M5 — Graphical Multiplayer Acceptance
M6 — Dedicated persistence and recovery
A3 — Single-server multiplayer audit/freeze
B1/B2 — after A3
N3–N6 — after B2
```

## Текущая ветка

```text
feature/m2-dedicated-graphical-client
checkpoint: v16.10.1-runtime-m2-dedicated-graphical-client
```

M2 запускает обычный graphical Godot client против headless dedicated server, проводит join/ownership handshake, authoritative movement, replica inventory/hotbar и reconnect к той же player entity.

Полный scope и acceptance: `SINGLE_SERVER_MULTIPLAYER_ROADMAP_RU.md`.
