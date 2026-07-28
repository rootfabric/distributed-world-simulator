# ADR-007: Runtime topology и listen-host

- Статус: принято в A0
- Дата: 2026-07-29
- Runtime-база: `v16.7.0-repository-r3.1-authoritative-recovery`

## Контекст

Текущий `offline` объединяет authority, presentation и input в одном процессе и допускает прямой локальный application path. Это удобно, но не проверяет сетевую семантику. Одновременно проект должен запускаться без выделенного сервера и позднее масштабироваться на несколько процессов.

## Решение

Ввести понятие runtime topology. Основной локальный gameplay-режим — `listen-host`:

```text
RegionAuthorityRuntime
↕ Loopback DTO boundary
ClientRuntime + ClientReplicaStore + Presentation
```

ClientRuntime не имеет прямого доступа к authoritative aggregates/services. Одинаковые command/snapshot/delta contracts используются в loopback и ENet.

`offline` сохраняется для tools, domain tests, generators, migrations и diagnostics.

Также поддерживается `local-dedicated`: отдельные server/client процессы на localhost.

## Последствия

Плюсы:

- один F5 остаётся возможным;
- network-first gameplay semantics;
- один client path для local/dedicated/cluster;
- быстрые breakpoints и loopback tests.

Цена:

- необходим ClientReplicaStore;
- нельзя использовать shared Dictionary/Object references;
- UI должен обновляться только из client replica;
- composition root становится сложнее.

## Запрещённый обход

Любая ссылка от client/presentation к server aggregate или domain service в listen-host считается архитектурной ошибкой.
