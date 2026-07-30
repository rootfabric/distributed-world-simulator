# Ближайшие итерации после A2

Текущий roadmap candidate: `v16.9.5-roadmap-single-server-multiplayer-first`.

```text
M1 — Unified Networked Gameplay Core — next
M2 — Dedicated + 1 graphical client
M3 — Dedicated + 2 graphical clients
M4 — Canonical shared gameplay over ENet
M5 — Graphical Multiplayer Acceptance
M6 — Dedicated persistence and recovery
A3 — Single-server multiplayer audit/freeze
B1/B2 — after A3
N3–N6 — after B2
```

## Следующая ветка

```text
feature/m1-unified-networked-gameplay-core
checkpoint: v16.10.0-runtime-m1-unified-networked-gameplay-core
```

M1 должен объединить `PlayableListenHostAuthority`, `PlayerOwnershipRegistry` и `MultiplayerGameplayAuthority` за одним production `NetworkedGameplayService`, выделить shared DTO/validators и перевести H1–H3 tests на общий service.

Полный scope и acceptance: `SINGLE_SERVER_MULTIPLAYER_ROADMAP_RU.md`.
