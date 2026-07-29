# T1 — Multi-peer Transport v2

**Checkpoint:** `v16.8.3-network-t1-multi-peer`
**Build ID:** `t1-multi-peer-transport-v2`
**База:** `v16.8.2-simulation-s0-spatial-substrate`
**Ветка:** `feature/t1-multi-peer-transport-v2`

## 1. Назначение

T1 устраняет главное ограничение N1: transport boundary больше не является состоянием одного глобального peer. Один listener одновременно обслуживает несколько независимых peer sessions, а подключение, reconnect или отключение одного peer не меняет lifecycle остальных и не переводит server listener из `LISTENING`.

T1 остаётся transport foundation. Он не реализует World Directory, NATS, gameplay routing или authority handoff.

## 2. Разделённые lifecycle

Listener:

```text
STOPPED → STARTING → LISTENING → DRAINING → STOPPED
```

Client-side transport может находиться в `ACTIVE`, но server listener остаётся `LISTENING` при любом числе готовых peers.

Peer session:

```text
CONNECTING
→ TRANSPORT_CONNECTED
→ HANDSHAKING
→ SYNCHRONIZING
→ READY
→ DRAINING
→ CLOSED
```

`FAILED` является peer-scoped состоянием. Ошибка или stale session одного peer не должна автоматически останавливать listener.

## 3. ProtocolFrame v2

Transport core маршрутизирует небольшое число каналов:

```text
CONTROL
COMMAND
STATE
EVENT
JOB
BULK
```

Точный DTO определяется полем `payload_schema`. ENet и будущий NATS adapter не должны содержать allowlist всех domain message types.

Frame содержит:

```text
frame_id
transport session ID
monotonic sequence
channel
delivery mode
payload schema
payload
payload checksum
```

Поддерживаемые delivery modes:

```text
RELIABLE_ORDERED
RELIABLE_UNORDERED
UNRELIABLE_SEQUENCED
```

## 4. NetworkTransportEvent v2

Port возвращает только строгие события:

```text
LISTENER_STARTED
PEER_CONNECTED
PEER_DISCONNECTED
MESSAGE_RECEIVED
SEND_FAILED
TRANSPORT_ERROR
LISTENER_DRAINING
LISTENER_STOPPED
```

Событие содержит peer ID, transport session ID, sequence, optional frame, error code и JSON-safe details. Adapter-specific события не проходят boundary.

## 5. Route и authority

T1 формально разделяет:

```text
authority_owner_id + authority_epoch
= право authoritative write

route_id + route_generation
= свежесть адреса доставки к тому же writer
```

Смена endpoint, ENet session или будущего NATS subject у того же authority owner не требует повышения authority epoch. Она требует монотонного `route_generation`.

Инварианты:

```text
new route + same generation             REJECT
route generation rollback               REJECT
new transport session + stale generation REJECT
new transport session + higher generation ACCEPT
old transport session after reconnect   REJECT
```

## 6. Per-peer queue semantics

Очереди и backpressure учитываются отдельно для каждого peer:

```text
queued messages
queued bytes
maximum pending messages
maximum pending bytes
```

Жизненный цикл записи в boundary-очереди:

```text
queued → dispatched
       ↘ retained-for-retry при ошибке adapter
```

`send_to_peer()` означает только принятие frame в per-peer FIFO. Метрики `queued_messages` и `queued_bytes` остаются занятыми, пока `flush_outbound()` или следующий `poll_events()` не передаст head записи transport adapter. Лимит освобождается только после успешного adapter enqueue. При ошибке отправки запись остаётся head очереди для повторной попытки.

Переполнение peer A не блокирует peer B: у каждого peer независимы FIFO, лимиты, метрики и dispatch. Тестовый gate заполняет очередь peer A до `PEER_QUEUE_MESSAGE_LIMIT`, после чего peer B всё равно принимает и отправляет собственный frame.

Outgoing sequence фиксируется только после успешного boundary enqueue. Frame, отклонённый по лимиту до enqueue, не потребляет sequence; frame, уже принятый в очередь, сохраняет sequence до успешного dispatch или явного удаления вместе с session.

## 7. ENet multi-peer adapter

`EnetMultiPeerTransportPort` поддерживает до 32 одновременных peers и три физических ENet channel:

```text
0 — CONTROL / COMMAND
1 — STATE / EVENT
2 — JOB / BULK
```

Logical peer ID и transport session отделены от ENet numeric peer ID. Numeric ID является внутренним адресом adapter и не попадает в domain contracts.

## 8. Compatibility

N1 не переписан. Старые:

```text
NetworkTransportBoundary v1
NetworkTransportPort v1
EnetTransportPort v1
LoopbackTransportPort v1
```

сохраняются для принятых N1/H0 paths.

`SinglePeerTransportCompatibilityAdapter` позволяет подключать старый port к v2 boundary как transport с `max_peers = 1`. Миграция существующих session services может выполняться вертикальными этапами без одновременной замены всей сети.

## 9. Проверяемый vertical slice

```text
один ENet listener
→ client A и client B подключаются одновременно
→ каждый получает отдельный transport session
→ оба отправляют CONTROL frame
→ server сохраняет LISTENING
→ server отправляет target reply каждому peer
→ A получает только A
→ B получает только B
```

Loopback tests дополнительно проверяют reconnect, route generation и fencing старой session.

## 10. Что T1 не делает

T1 не включает:

- handshake protocol v2;
- client authentication;
- World Directory;
- NATS Core или JetStream;
- durable outbox;
- authority lease service;
- cross-server handoff;
- content transfer;
- dynamic interest management.

Следующий этап `B0` вводит transport-independent message bus ports поверх уже разделённых transport families.
