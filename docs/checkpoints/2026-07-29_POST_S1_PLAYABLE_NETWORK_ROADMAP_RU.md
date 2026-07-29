# Решение по дорожной карте после принятия S1

**Дата:** 29 июля 2026 года
**Статус:** **ACCEPTED ROADMAP DECISION**
**Текущая база:** `v16.9.0-simulation-s1-distributed-compute-fix1`

## Решение

S1 Distributed Compute Contracts принят. Следующий основной track переносится с немедленного B1 на доказательство полноценной игровой client/server вертикали.

Утверждён порядок:

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

## Причина

Принятый foundation уже содержит:

- authoritative server/client contracts;
- process harness и crash recovery;
- listen-host composition;
- generic aggregates;
- spatial cells/shards;
- multi-peer transport;
- semantic message-bus ports;
- atomic multi-aggregate transactions/outbox;
- authority-validated distributed compute proposals.

Следующий главный риск находится не в отсутствии ещё одного infrastructure adapter, а в отсутствии полной graphical gameplay vertical slice поверх этих контрактов.

H1–H3 должны доказать:

- один и тот же client/gameplay path в listen-host и dedicated topologies;
- отсутствие прямого доступа presentation к canonical state;
- полноценное движение игрока через authority;
- inventory/container/world interactions через command/result/delta;
- reconnect/replay;
- одновременную игру минимум двух graphical clients;
- deterministic contention за один authoritative объект.

## Архитектурный checkpoint после H3

После принятия H3 выполняется `A2 — Networked gameplay architecture checkpoint`.

A2 фиксирует доказанные контракты Player Aggregate, session identity, movement replication, permissions, contention, reconnect, relevance и единую composition model H1/H2/H3.

A2 является обязательным gate перед B1 и несколькими authority servers. Он не должен добавлять новые gameplay-функции или альтернативный runtime path.

## Изменение прежнего плана

Ранее B1 считался непосредственным этапом после S1. Теперь B1 остаётся обязательным, но начинается после:

```text
H1 → H2 → H3 → A2
```

Это изменение не отменяет B1/B2, P0/D1 или N3–N6 и не ослабляет их dependencies.

## Канонический подробный план

[`../plans/PLAYABLE_NETWORK_MILESTONES_RU.md`](../plans/PLAYABLE_NETWORK_MILESTONES_RU.md)
