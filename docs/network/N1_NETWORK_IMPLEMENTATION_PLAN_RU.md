# План реализации сетевой части N1–N5

## Текущая база

```text
v16.4.2-network-transport-boundary       принят
v16.5.0-network-n1-snapshot              принят
v16.5.1-network-n1-remote-item-command   candidate текущего этапа
```

Foundation, N0, Inventory UI-I0–UI-I2, transport lifecycle и ENet handshake/snapshot path сохранены. N1.2 доказывает первую реальную authoritative domain-команду между двумя отдельными Godot-процессами.

## Критический путь

```text
N1.0 transport boundary                         ACCEPTED
→ N1.1 ENet handshake + initial snapshot       ACCEPTED
→ N1.2 remote item.move_to_container           CURRENT CANDIDATE
→ N1.3 reconnect + replay                      NEXT
→ N2 multi-process harness
→ R3.1 authoritative persistence/recovery
→ N3 World Directory
→ N4 cross-server handoff
→ N5 ghost replicas/interest management
```

## N1.0 — transport boundary

Checkpoint: `v16.4.2-network-transport-boundary`.

Общий lifecycle для loopback и реальных adapters, canonical JSON fence, ограничения payload/queue и строгий transport port.

## N1.1 — ENet handshake и initial snapshot

Checkpoint: `v16.5.0-network-n1-snapshot`.

Два headless Godot-процесса согласуют protocol/capabilities/contracts, получают transport session, передают initial `EntitySnapshotEnvelope` и подтверждают checksum через `SnapshotAckEnvelope`.

## N1.2 — удалённая authoritative item-команда

Checkpoint candidate: `v16.5.1-network-n1-remote-item-command`.

Ветка: `feature/n1-remote-item-command`.

Полный путь:

```text
bot-client
→ NetworkCommandEnvelope(item.move_to_container)
→ ENet wire frame
→ simulation-server
→ authority/session/revision validation
→ ItemTransferService
→ Item Registry + Container Registry + operation ledger
→ WorldEntityAggregate
→ EntityDeltaEnvelope
→ ENet
→ bot-client snapshot apply
→ final checksum equality
```

Обязательные гарантии:

- клиент не мутирует authoritative state самостоятельно;
- owner, epoch, aggregate revision и item revision проверяются до mutation;
- source/destination membership проверяется сервером;
- доменная операция фиксируется в ledger ровно один раз;
- aggregate revision и server tick увеличиваются монотонно;
- exact replay одного `operation_id` возвращает прежний результат;
- exact replay не вызывает handler и mutation второй раз;
- другой payload с тем же `operation_id` отклоняется;
- повторная доставка того же delta не применяется второй раз;
- stale revision после успешной команды отклоняется;
- при ошибке aggregate/delta commit восстанавливаются items, containers, ledger и aggregate;
- server/client final snapshot checksums совпадают.

N1.2 не включает reconnect и устойчивость deduplication cache после перезапуска процесса.

## N1.3 — reconnect и replay

Следующая ветка: `feature/n1-reconnect-replay`.

Checkpoint target: `v16.5.2-foundation-network-n1`.

Реализовать:

1. потерю ENet-соединения после отправки команды и до ответа;
2. новую transport session без изменения entity/item identity;
3. повторную отправку исходного `operation_id`;
4. replay сохранённого command result и delta/snapshot;
5. отсутствие второй domain mutation;
6. bounded deduplication/replay window;
7. handshake timeout, command timeout и graceful drain;
8. несколько последовательных reconnect в process test.

Модель доставки:

```text
at-least-once delivery
+ idempotent command processing
+ stable operation_id
+ replayable result
```

## N2 — общий multi-process harness

После N1.3 один кроссплатформенный runner должен управлять портами, isolated `user://`, readiness, timeout, process cleanup, fault scenarios, JSON и JUnit reports. Текущие Godot process tests являются вертикальными fixtures, но не заменяют общий harness.

## R3.1 — authoritative persistence и recovery

Сохранить snapshot, authority metadata, operation ledger и replay records. Проверить падение процесса до/после mutation, ledger write, flush и response. Старый несовместимый `user://world.json` должен получать backup/migration или явную безопасную очистку.

## N3 — World Directory

Регистрация simulation nodes, heartbeat, authority regions, lease issuance/renewal, route lookup, drain и expired-lease fencing. На N3 ещё не требуется перенос сущности.

## N4 — cross-process handoff

Подключить N0 handoff state machine к двум серверам и Directory. Инвариант: число active authoritative writers для сущности не превышает одного.

## N5 — ghosts и interest management

Read-only replicas около границ, bounded subscriptions, route switching и promotion только после принятого N4.

## Веточная политика

- новый этап — новая короткая ветка от актуального `main`;
- review fixes непринятого N1.2 выполняются в `feature/n1-remote-item-command`;
- fix-коммит: `fix(network): harden authoritative remote item command`;
- после принятия N1.2 ветка сливается и удаляется;
- N1.3 начинается в `feature/n1-reconnect-replay`.
