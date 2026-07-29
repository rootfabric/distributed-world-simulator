# Ближайшие итерации: приёмка H1 и переход к H2

## Текущая точка

```text
accepted checkpoint: v16.9.0-simulation-s1-distributed-compute-fix1
candidate checkpoint: v16.9.1-runtime-h1-playable-listen-host
accepted domain base: v16.8.5-domain-m0-aggregate-transactions
accepted transport base: v16.8.3-network-t1-multi-peer
architecture base: v16.7.1-architecture-a0-distributed-runtime
```

S1 завершил foundation-последовательность:

```text
A0 → H0 → A1 → S0 → T1 → B0 → M0 → S1
```

H1 уже реализует graphical listen-host vertical slice и ожидает независимой приёмки. Следующая кодовая задача после PASS — H2 с отдельным headless server и graphical client.

## Утверждённый ближайший порядок

```text
H1 — Playable listen-host (candidate)
→ H2 — Dedicated server + 1 graphical client
→ H3 — Dedicated server + 2 graphical clients
→ A2 — Networked gameplay architecture checkpoint
→ B1 — NATS Core adapter
→ B2 — JetStream/outbox delivery
→ P0 — Population Field
→ D1 — Remote worker MVP
→ N3 — World Directory + 2 authorities
→ N4 — Generic object handoff
→ N5 — Seamless player handoff
→ N6 — Ghosts + interest management
```

## H1 — текущий candidate gate

```text
checkpoint: v16.9.1-runtime-h1-playable-listen-host
branch: feature/h1-playable-listen-host
status: candidate
```

H1 переводит основной F5/gameplay path на embedded authority + graphical client. Movement, inventory, containers, pickup/drop, stack/split и mount interactions должны проходить через command/result/delta и отображаться из client replicas.

## H2

```text
proposed checkpoint: v16.9.2-runtime-h2-dedicated-single-player
branch: feature/h2-dedicated-single-player
```

Тот же graphical client работает против отдельного headless server с connect, initial state, reconnect и persistence recovery.

## H3

```text
proposed checkpoint: v16.9.3-runtime-h3-dedicated-multiplayer
branch: feature/h3-dedicated-multiplayer
```

Один server обслуживает минимум два graphical clients. Оба игрока видят movement друг друга, имеют отдельные inventories и получают deterministic result при конфликте за один item/container/mount.

## A2 после H3

```text
proposed checkpoint: v16.9.4-architecture-a2-networked-gameplay
branch: feature/a2-networked-gameplay-architecture
```

A2 фиксирует доказанную H1–H3 архитектуру и является gate перед B1. Кодовые gameplay-функции в A2 не добавляются.

## Правило фокуса

До принятия H3 и A2:

- не создавать отдельный gameplay implementation для каждой topology;
- не переносить canonical state в presentation;
- не начинать production NATS/JetStream integration в основном track;
- не начинать World Directory и cross-server handoff;
- не ослаблять authority/replay/session fences ради UI;
- не считать transport-level multi-peer достаточным доказательством multiplayer gameplay.

Исследования следующих этапов допустимы только без parallel production path.

Полный план: [`PLAYABLE_NETWORK_MILESTONES_RU.md`](PLAYABLE_NETWORK_MILESTONES_RU.md).
