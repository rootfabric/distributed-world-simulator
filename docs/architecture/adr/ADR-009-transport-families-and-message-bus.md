# ADR-009: Раздельные transport semantics и сменяемые adapters

- Статус: принято в A0
- Дата: 2026-07-29

## Контекст

ENet подходит для realtime client replication. NATS может быть полезен для service discovery, jobs, events и части server-to-server traffic. Один универсальный transport port скроет несовместимые гарантии.

## Решение

Разделить logical ports:

```text
ReplicationTransportPort
ServiceRequestReplyPort
EventStreamPort
JobQueuePort
BulkTransferPort
```

ENet, loopback, NATS Core, JetStream, HTTP или object storage являются adapters. Domain DTO и identities не содержат subjects, channels или broker IDs.

Transport frame маршрутизирует по channel и payload schema, а не по жёсткому списку всех будущих DTO.

## Последствия

- NATS можно добавить или заменить локально;
- realtime и durable traffic не смешиваются;
- для каждого port нужны отдельные timeout/retry/backpressure contracts;
- adapters требуют contract suites.

## Запрещённый обход

Domain/application code не вызывает NATS API и не строит subjects.
