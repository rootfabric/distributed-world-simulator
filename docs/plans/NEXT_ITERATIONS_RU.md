# Ближайшие итерации после M6

Принятый M6: `v16.10.5-persistence-m6-dedicated-recovery` (`ACCEPTED`, delivery `fix1`).
Текущий candidate: `v16.10.6-architecture-a3-single-server-multiplayer`.

```text
A3 — Single-server multiplayer audit/freeze — current candidate
B1 — NATS Core server-to-server adapter — next after A3 acceptance
B2 — JetStream/outbox delivery — after B1
N3–N6 — after A3 and B2
```

## Текущая ветка

```text
feature/a3-single-server-multiplayer-architecture
checkpoint: v16.10.6-architecture-a3-single-server-multiplayer
runtime base: v16.10.5-persistence-m6-dedicated-recovery
```

A3 проверяет, что M1–M6 образуют один production gameplay path без topology-specific forks: единый service, общие contracts, LOOPBACK/ENet equivalence, graphical replica boundary, contention, reconnect, durable recovery и exact replay.

Полный scope и acceptance: `SINGLE_SERVER_MULTIPLAYER_ROADMAP_RU.md`.
