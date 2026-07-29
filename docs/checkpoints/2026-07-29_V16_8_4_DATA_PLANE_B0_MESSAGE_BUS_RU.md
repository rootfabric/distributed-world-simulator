# Checkpoint v16.8.4 — B0 Transport-independent Message Bus Contracts

**Дата:** 2026-07-29
**Ветка:** `feature/b0-message-bus-contracts`
**База:** `v16.8.3-network-t1-multi-peer`
**Build ID:** `b0-transport-independent-message-bus-contracts`

## Реализовано

- пять отдельных semantic ports;
- `SemanticPortDescriptor v1`;
- `BusOperationResult v1` со строгими timeout/backpressure outcomes;
- request/response, event, job/delivery, replication и bulk DTO;
- `MessageBusCompositionRoot` с fail-closed port-kind validation;
- две request/reply реализации;
- две event-stream реализации;
- in-memory job, replication и bulk adapters;
- запрет adapter metadata в semantic payload;
- contract и integration suites;
- Windows/Linux runners.

## Основной vertical gate

Один application workflow выполняется через:

```text
Direct service + direct event adapters
```

и через:

```text
Routed service + buffered event adapters
```

Application layer не меняется. Canonical response и event совпадают.

## Отдельные fences

- event нельзя submit как job;
- job нельзя send как replication;
- semantic ports нельзя поменять местами в composition root;
- timeout и backpressure не маскируются как generic failure;
- exact duplicate IDs replay-safe;
- same ID с другим content отклоняется;
- replication backpressure peer A не блокирует peer B;
- bulk object проверяет размер и SHA-256.

## Не входит

- NATS SDK;
- JetStream;
- outbox publisher;
- production durability;
- distributed compute;
- World Directory.

## Следующий checkpoint

```text
M0 — v16.8.5-domain-m0-aggregate-transactions
feature/m0-aggregate-transactions
```
