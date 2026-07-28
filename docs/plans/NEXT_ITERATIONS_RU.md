# Ближайшие итерации после v16.5.0-network-n1-snapshot

## Зафиксированная база

```text
v16.4.1-foundation-inventory-merge       принято
v16.4.2-network-transport-boundary       принято
v16.5.0-network-n1-snapshot              текущий candidate
```

В mainline уже объединены Foundation Part 1–3, N0 fix1, Item Graph/aggregate и Inventory UI-I0–UI-I2. N1.0 зафиксировал общий transport lifecycle. N1.1 добавляет реальный ENet handshake и initial snapshot между отдельными Godot-процессами.

## Текущий этап — N1.1

```text
simulation-server
→ handshake validation
→ session assignment
→ initial EntitySnapshotEnvelope
→ client checksum validation
→ SnapshotAckEnvelope
→ clean process exit
```

N1.1 не мутирует Item Graph. Это отдельный gate транспорта и snapshot delivery.

## Следующий этап — N1.2

Ветка:

```text
feature/n1-remote-item-command
```

Обязательный сценарий:

1. server создаёт authoritative item/container state;
2. client получает initial snapshot;
3. client отправляет `item.move_to_container`;
4. server проверяет owner, epoch и expected revision;
5. существующий `ItemTransferService` выполняет mutation;
6. operation ledger фиксирует одну операцию;
7. server возвращает delta или snapshot;
8. client повторно валидирует результат;
9. checksum клиента и сервера совпадает;
10. duplicate command не выполняет mutation повторно.

Checkpoint: `v16.5.1-network-n1-item-command`.

## После N1.2

```text
N1.3 reconnect/replay
→ N2 process harness
→ R3.1 persistence/crash recovery и migration старого user-state
→ N3 World Directory + leases
→ N4 cross-server handoff
→ N5 ghost replicas
```

## Что не расширять до N1.2/N1.3

- UI-I3 batch/multi-select;
- optimistic inventory mutation;
- второй simulation-server;
- World Directory;
- player prediction;
- ghost streaming;
- распределённую физику.

## Обязательный merge gate

```text
editor import/parse
все test_*.gd объявлены в regression runner
N0/N1 network profile
полный Godot regression
main scene CLI
simulation-server lifecycle
реальный server/client process test
нет прямой presentation mutation
нет process leaks
нет stale checkpoint/build ID
```

## Политика веток

Новый этап получает новую короткую ветку. Review fixes текущего непринятого этапа выполняются в этой же ветке отдельными `fix(...)` коммитами. После принятия checkpoint ветка сливается в `main` и удаляется.
