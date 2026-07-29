# B0: Transport-independent Message Bus Contracts

**Checkpoint:** `v16.8.4-data-plane-b0-message-bus-contracts`
**Build ID:** `b0-transport-independent-message-bus-contracts`
**База:** `v16.8.3-network-t1-multi-peer`
**Ветка:** `feature/b0-message-bus-contracts`

## 1. Назначение

B0 отделяет семантику обмена данными от конкретного механизма доставки. Проект больше не должен выбирать между ENet, loopback, NATS, JetStream, HTTP или object storage внутри domain/application-кода.

B0 не подключает брокер. Он определяет устойчивые logical ports и строгие DTO, на которые позднее смогут опираться разные adapters.

```text
application/domain intent
        ↓
semantic port
        ↓
adapter selected by composition root
        ↓
loopback / ENet / NATS / JetStream / HTTP / object storage
```

## 2. Почему один универсальный transport port запрещён

Разные потоки требуют разных гарантий:

| Семантика | Основное свойство |
|---|---|
| request/reply | корреляция запроса и ответа, timeout |
| event stream | append-only порядок, replay/idempotency |
| job queue | claim, attempt, acknowledgement, retry |
| replication | targeted ephemeral delivery и per-peer backpressure |
| bulk transfer | размер, content hash и хранение больших объектов |

Один `send(topic, payload)` скрыл бы несовместимые гарантии и позволил бы случайно использовать job queue как realtime replication либо считать broker ACK authoritative commit.

## 3. Семантические порты

### 3.1 ServiceRequestReplyPort

Используется для:

- service discovery;
- health/capability queries;
- Directory lookup;
- route lookup;
- административных запросов.

Контракт:

```text
request(ServiceRequestEnvelope)
→ BusOperationResult
  └── ServiceResponseEnvelope
```

Timeout выражен отдельным versioned result:

```text
outcome = TIMEOUT
error_code = REQUEST_TIMEOUT
retryable = true
```

### 3.2 EventStreamPort

Используется для append-only событий и будущего audit/outbox stream.

Контракт:

```text
publish(EventEnvelope)
read(stream_id, after_sequence, max_count)
```

B0 in-memory adapters проверяют:

- монотонный sequence;
- exact duplicate event ID;
- conflict при повторном ID с другим содержимым;
- bounded backpressure.

Durability пока не заявляется. JetStream и outbox появятся позже.

### 3.3 JobQueuePort

Используется для фоновых и simulation jobs.

Контракт:

```text
submit(JobEnvelope)
claim(queue_id, worker_id)
acknowledge(delivery_id, worker_id)
reject(delivery_id, worker_id, retryable)
```

Job delivery имеет отдельный `delivery_id`, `worker_id` и `attempt`. Broker delivery не является authority transfer и не даёт worker права менять canonical state.

### 3.4 ReplicationTransportPort

Используется для:

- snapshots;
- deltas;
- ghost state;
- interest updates.

Контракт:

```text
send(ReplicationEnvelope)
poll(target_peer_id, max_count)
```

B0 in-memory adapter реализует targeted per-peer queues. Переполнение peer A не блокирует peer B.

Этот port не заменяет T1. T1 является конкретным realtime transport foundation, а B0 задаёт application-facing replication semantics поверх сменяемых adapters.

### 3.5 BulkTransferPort

Используется для:

- больших snapshots;
- content packages;
- checkpoints;
- asset/package transfer.

Контракт:

```text
store(BulkObjectDescriptor, content_base64)
fetch(object_id)
remove(object_id)
```

Descriptor содержит exact content SHA-256 и размер. Позже adapter может использовать filesystem, HTTP, NATS object store либо S3-compatible storage.

## 4. Общий строгий результат

Все ports возвращают `BusOperationResult v1`:

```text
schema
protocol_version
success
outcome
error_code
retryable
details
```

Успешные outcomes:

```text
ACCEPTED
ACKNOWLEDGED
AVAILABLE
COMPLETED
DELIVERED
EMPTY
```

Ошибочные outcomes:

```text
BACKPRESSURE
FAILED
NOT_FOUND
REJECTED
TIMEOUT
```

Это не позволяет adapters возвращать несовместимые произвольные dictionaries вроде `{ok: true}` или скрывать timeout как обычный null response.

## 5. Adapter metadata запрещена в domain payload

DTO не содержат:

```text
nats_subject
jetstream_stream
jetstream_consumer
broker_id
broker_message_id
enet_channel
transport_session_id
transport_route_id
```

Такие поля являются adapter configuration и должны существовать только внутри composition/deployment слоя.

Canonical identity остаётся независимой:

```text
aggregate_id
entity_id
service_id
stream_id
queue_id
object_id
```

NATS subject либо ENet channel не является domain identity.

## 6. Composition root

`MessageBusCompositionRoot` принимает ровно пять ports и проверяет их `SemanticPortDescriptor`.

Подмена semantic family отклоняется:

```text
EventStreamPort вместо ServiceRequestReplyPort
→ PORT_KIND_MISMATCH
```

Composition snapshot показывает только набор logical port kinds. Он не публикует subjects, channels или broker identifiers.

## 7. In-memory adapters B0

Добавлены две разные реализации request/reply и event semantics:

```text
InMemoryServiceRequestReplyAdapter
RoutedInMemoryServiceRequestReplyAdapter

InMemoryEventStreamAdapter
BufferedInMemoryEventStreamAdapter
```

Одинаковый application workflow выполняется через обе пары и даёт одинаковые canonical response/event DTO.

Также добавлены:

```text
InMemoryJobQueueAdapter
InMemoryReplicationTransportAdapter
InMemoryBulkTransferAdapter
```

Эти adapters предназначены для contract/integration tests и будущего single-process local cluster. Они не заявляют production durability.

## 8. Границы ответственности

### B0 гарантирует

- разделение пяти semantic families;
- versioned strict DTO;
- canonical JSON round-trip;
- explicit timeout/backpressure results;
- exact duplicate/conflict semantics;
- adapter-independent application workflow;
- отсутствие broker SDK в foundation-коде.

### B0 не гарантирует

- NATS connectivity;
- JetStream durability;
- outbox transaction;
- distributed worker scheduling;
- authoritative multi-aggregate commit;
- cross-server Directory/leases;
- production bulk storage.

## 9. Ключевые инварианты

```text
broker ACK ≠ authoritative commit
job delivery ≠ authority ownership
replication queue ≠ durable event stream
NATS subject ≠ aggregate identity
ENet channel ≠ domain operation
adapter route ≠ canonical state
```

## 10. Проверки

```text
BUS-001 adapter-independent request/reply and event round-trip
BUS-002 semantic families cannot be interchanged
BUS-003 payloads reject adapter-specific metadata
BUS-004 timeout/backpressure use strict versioned results
BUS-005 exact duplicate IDs are idempotent; changed content conflicts
BUS-006 per-peer replication backpressure is isolated
BUS-007 bulk transfer verifies size and SHA-256
BUS-008 job claim/ack/retry semantics are explicit
```

## 11. Следующий этап

После B0 основной foundation sequence переходит к:

```text
M0 — Multi-aggregate Transactions and Outbox Foundation
```

M0 должен атомарно связывать authoritative state, operation result, ledger и outbox record. Только после этого durable broker publication сможет быть безопасно подключена.
