# План реализации сетевой части N1–N5

## Текущая база

```text
v16.4.1-foundation-inventory-merge
main tree: 05161a3d2fb5f36520977ce1b801058aca215a43
```

Foundation, N0 и Inventory UI-I0–UI-I2 приняты. Следующая цель — доказать один реальный authoritative command path между двумя Godot-процессами.

## Критический путь

```text
N1.0 transport boundary
→ N1.1 ENet handshake + initial snapshot
→ N1.2 remote item.move_to_container
→ N1.3 reconnect + replay
→ N2 process harness
→ R3.1 authoritative persistence/recovery
→ N3 World Directory
→ N4 cross-server handoff
→ N5 ghost replicas/interest management
```

## N1.0 — transport boundary

Checkpoint: `v16.4.2-network-transport-boundary`.

Реализуется общий lifecycle, одинаковый для loopback и будущего ENet:

```text
STOPPED
→ STARTING/LISTENING или CONNECTING
→ READY
→ DRAINING
→ STOPPED
```

Аварийное состояние: `FAILED`.

Обязательные свойства:

- transport принимает только наследников канонического transport port script;
- descriptor имеет точную схему без дополнительных полей;
- send разрешён только в `READY`;
- message type ограничен allowlist;
- payload проходит canonical JSON validation;
- runtime objects отклоняются;
- размер сообщения и очередь ограничены;
- lifecycle transitions fail-closed;
- `drain()` и `stop()` идемпотентны;
- loopback реализует тот же порт, что позже реализует ENet.

N1.0 не содержит сокетов и не меняет domain API.

## N1.1 — ENet handshake и initial snapshot

Отдельные процессы:

```text
simulation-server ↔ ENet ↔ bot-client
```

Handshake согласует protocol version, capabilities, runtime role и contract versions. После него сервер отправляет строгий `EntitySnapshotEnvelope`, клиент проверяет JSON boundary и checksum.

Checkpoint: `v16.5.0-network-n1-snapshot`.

## N1.2 — удалённая authoritative item command

Первая команда: `item.move_to_container`.

Путь:

```text
bot-client
→ NetworkCommandEnvelope
→ ENet
→ command gateway
→ authority/revision validation
→ ItemTransferService
→ WorldEntityAggregate
→ operation ledger
→ snapshot/delta
→ bot-client
```

Клиент не мутирует canonical state самостоятельно. Duplicate delivery выполняет mutation не более одного раза.

Checkpoint: `v16.5.1-network-n1-item-command`.

## N1.3 — reconnect и replay

Используется модель:

```text
at-least-once delivery
+ stable operation_id
+ idempotent execution
+ replayable terminal result
```

Добавляются timeout, reconnect, bounded deduplication и graceful drain.

Checkpoint: `v16.5.2-foundation-network-n1`.

## N2 — multi-process harness

Runner автоматически выделяет порт, запускает процессы с изолированными `user://`, ждёт readiness, собирает JSONL, завершает процессы и формирует JSON/JUnit report.

Checkpoint: `v16.6.0-network-n2-process-harness`.

## R3.1 — persistence и crash recovery

Сохраняются snapshot, revision, epoch, tick, ledger и replayable command results. Проверяются падения между mutation, ledger, flush и response.

Checkpoint: `v16.7.0-repository-r3.1-authoritative-recovery`.

## N3 — World Directory

Регистрация nodes, heartbeat, authority regions, leases, renewal, route lookup, draining и expired-owner fencing.

Checkpoint: `v16.8.0-network-n3-world-directory`.

## N4 — cross-server handoff

Подключение существующей N0 handoff state machine к двум реальным simulation-server и Directory. Главный инвариант: одновременно не более одного authoritative writer.

Checkpoint: `v16.9.0-network-n4-cross-server-handoff`.

## N5 — ghosts и interest management

Read-only replicas, border overlap, subscriptions, promotion/demotion и bounded update frequency. Начинается только после принятого N4.

## Политика веток

```text
feature/n1-transport-boundary
feature/n1-enet-snapshot
feature/n1-remote-item-command
feature/n1-reconnect-replay
feature/n2-process-harness
feature/r3.1-authoritative-recovery
feature/n3-world-directory
feature/n4-authority-handoff
```

Review fixes непринятого этапа остаются в той же ветке и оформляются `fix(network): ...`.
