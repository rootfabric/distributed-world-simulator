# Ближайшие итерации после M5

Принятый M5: `v16.10.4-testing-m5-graphical-multiplayer-acceptance` (`ACCEPTED`, delivery `fix1`).
Текущий candidate: `v16.10.5-persistence-m6-dedicated-recovery`.

```text
M6 — Dedicated persistence and recovery — current candidate
A3 — Single-server multiplayer audit/freeze — next after acceptance
B1/B2 — after A3
N3–N6 — after B2
```

## Текущая ветка

```text
feature/m6-dedicated-recovery
checkpoint: v16.10.5-persistence-m6-dedicated-recovery
runtime base: v16.10.4-testing-m5-graphical-multiplayer-acceptance
```

M6 интегрирует R3.1 recovery в реальный dedicated runtime: atomic checkpoint до ACK, player/Item Graph/replay/outbox restore, reconnect с новым ownership epoch и exact replay без повторной мутации.

Полный scope и acceptance: `SINGLE_SERVER_MULTIPLAYER_ROADMAP_RU.md`.
