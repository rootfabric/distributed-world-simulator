# ADR-012: Full single-server multiplayer before server mesh

- Статус: proposed by post-A2 roadmap checkpoint
- Дата: 2026-07-30
- Base decision: ADR-011 / A2 `FROZEN_WITH_GATES`

## Контекст

A2 подтвердил правильную semantic architecture, но оставил четыре P1-разрыва: разные gameplay authority implementations, coupled validators, отсутствие двух graphical clients с canonical Item Graph и отсутствие dedicated crash/restart proof.

B1/NATS архитектурно допустим, но не закрывает эти разрывы. Для realtime graphical traffic одного dedicated server уже принят ENet.

## Решение

Основной production order:

```text
M1 → M2 → M3 → M4 → M5 → M6 → A3 → B1 → B2 → N3–N6
```

До A3 основной поток не реализует server mesh. NATS применяется только через B0 semantic ports для server/service communication и не заменяет ENet.

## Следствия

Положительные:

- пользовательский multiplayer proof появляется до инфраструктурного расширения;
- H1/H2/H3 консолидируются вместо размножения fixtures;
- canonical Item Graph и recovery проверяются до handoff;
- A3 получает реальную production evidence base.

Стоимость:

- B1/B2 откладываются;
- потребуется graphical process harness с renderer/virtual display;
- H1/H2/H3 тесты придётся мигрировать на общий service.

## Запрещённые обходы

- отдельный domain path для listen-host, dedicated или tests;
- NATS как graphical gameplay transport;
- headless protocol clients как единственное доказательство M5;
- reduced shared-item fixture вместо canonical Item Graph после M4;
- начало production N3–N6 до принятия A3.
