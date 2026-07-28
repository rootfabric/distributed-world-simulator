# План реализации сетевой части N1–N5

## Текущая база

```text
v16.4.2-network-transport-boundary — принят
v16.5.0-network-n1-snapshot — candidate текущего этапа
```

Foundation, N0, Inventory UI-I0–UI-I2 и общий transport lifecycle boundary приняты. N1.1 доказывает первый реальный обмен между двумя отдельными Godot-процессами.

## Критический путь

```text
N1.0 transport boundary                         ACCEPTED
→ N1.1 ENet handshake + initial snapshot       CURRENT CANDIDATE
→ N1.2 remote item.move_to_container           NEXT
→ N1.3 reconnect + replay
→ N2 process harness
→ R3.1 authoritative persistence/recovery
→ N3 World Directory
→ N4 cross-server handoff
→ N5 ghost replicas/interest management
```

## N1.0 — transport boundary

Checkpoint: `v16.4.2-network-transport-boundary`.

Общий lifecycle для loopback и реальных transport adapters:

```text
STOPPED
→ STARTING/LISTENING или CONNECTING
→ READY
→ DRAINING
→ STOPPED
```

Аварийное состояние: `FAILED`. Boundary ограничивает message types, canonical JSON payload, размер сообщения и очередь, отклоняет runtime objects и принимает только настоящий transport port.

## N1.1 — ENet handshake и initial snapshot

Checkpoint: `v16.5.0-network-n1-snapshot`.

Ветка: `feature/n1-enet-snapshot`.

Реальная топология:

```text
headless simulation-server
          ↕ ENet / reliable packets
headless bot-client
```

Реализуемый путь:

1. server открывает localhost ENet endpoint;
2. bot-client подключается отдельным Godot-процессом;
3. client отправляет строгий `NetworkHandshakeEnvelope`;
4. server проверяет protocol, role, capabilities и версии контрактов;
5. server возвращает `NetworkHandshakeResultEnvelope` с назначенным `session_id`;
6. server отправляет строгий `EntitySnapshotEnvelope`;
7. client повторно валидирует DTO, authority metadata и checksum;
8. client отправляет `SnapshotAckEnvelope`;
9. server проверяет session, snapshot identity и checksum;
10. оба процесса формируют JSON-отчёты и корректно завершаются.

Fail-closed проверки:

- malformed/non-canonical wire frame;
- неизвестный message type;
- protocol mismatch;
- неправильная runtime role;
- отсутствующая capability;
- несовместимая версия DTO;
- повреждённый handshake/snapshot/ack checksum;
- snapshot с authority owner/epoch, не совпадающими с advertised server authority;
- snapshot tick впереди advertised server tick;
- неожиданные или отсутствующие negotiated capabilities;
- ранний disconnect;
- зависший процесс и timeout;
- более одного клиента на текущем N1 adapter.

N1.1 намеренно не выполняет доменную mutation. Его результат — доказанная доставка initial snapshot через настоящий transport без изменения N0 DTO.

## N1.2 — удалённая authoritative item command

Checkpoint: `v16.5.1-network-n1-item-command`.

Ветка: `feature/n1-remote-item-command`.

Первая команда: `item.move_to_container`.

```text
bot-client
→ NetworkCommandEnvelope
→ ENet
→ command gateway
→ authority/revision validation
→ ItemTransferService
→ WorldEntityAggregate
→ operation ledger
→ EntityDeltaEnvelope или snapshot
→ bot-client
```

Клиент не мутирует canonical state самостоятельно. Сервер проверяет owner, epoch, expected revision и operation identity. Duplicate delivery не выполняет mutation второй раз.

## N1.3 — reconnect и replay

Checkpoint: `v16.5.2-foundation-network-n1`.

Модель доставки:

```text
at-least-once delivery
+ stable command_id/operation_id
+ idempotent execution
+ replayable terminal result
```

Добавляются reconnect, timeout, bounded deduplication, replay результата и graceful drain.

## N2 — multi-process harness

Checkpoint: `v16.6.0-network-n2-process-harness`.

Runner выделяет свободные порты, создаёт изолированные `user://`, запускает процессы, ждёт readiness, собирает stdout/stderr и JSON/JUnit, завершает зависшие процессы и проверяет отсутствие process leaks.

## R3.1 — persistence и crash recovery

Checkpoint: `v16.7.0-repository-r3.1-authoritative-recovery`.

Сохраняются snapshot, revision, epoch, tick, operation ledger и replayable command results. Отдельно решается versioned migration старых `user://worlds/.../world.json` с резервной копией и fail-closed загрузкой.

## N3 — World Directory

Checkpoint: `v16.8.0-network-n3-world-directory`.

Регистрация nodes, heartbeat, authority regions, leases, renewal, route lookup, draining и expired-owner fencing.

## N4 — cross-server handoff

Checkpoint: `v16.9.0-network-n4-cross-server-handoff`.

Существующая N0 handoff state machine подключается к двум реальным simulation-server и Directory. Главный инвариант: одновременно не более одного authoritative writer.

## N5 — ghosts и interest management

Read-only replicas, border overlap, subscriptions, promotion/demotion и bounded update frequency. Этап начинается только после принятого N4.

## Политика веток

```text
feature/n1-enet-snapshot
feature/n1-remote-item-command
feature/n1-reconnect-replay
feature/n2-process-harness
feature/r3.1-authoritative-recovery
feature/n3-world-directory
feature/n4-authority-handoff
```

Review fixes непринятого этапа остаются в той же ветке и оформляются коммитами `fix(network): ...`. Новая fix-ветка создаётся только для уже принятого и влитого checkpoint.
