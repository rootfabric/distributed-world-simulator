# Ближайшие итерации после v16.5.1-network-n1-remote-item-command

## Зафиксированная база

```text
v16.4.1-foundation-inventory-merge       принято
v16.4.2-network-transport-boundary       принято
v16.5.0-network-n1-snapshot              принято
v16.5.1-network-n1-remote-item-command   текущий candidate
```

## Текущий этап — N1.2

Ветка:

```text
feature/n1-remote-item-command
```

Проверяемый сценарий:

```text
initial snapshot
→ remote item.move_to_container
→ one server-side ItemTransferService mutation
→ one ledger record
→ aggregate revision/tick advance
→ EntityDeltaEnvelope
→ exact replay without mutation
→ stale revision rejection
→ final checksum equality
```

Review fixes остаются в той же ветке.

## Следующий этап — N1.3

Ветка после принятия N1.2:

```text
feature/n1-reconnect-replay
```

Задачи:

1. обрыв после отправки команды до получения ответа;
2. reconnect с новой session ID;
3. повторная доставка прежнего operation ID;
4. replay прежнего result/delta;
5. mutation count остаётся равным одному;
6. bounded replay cache и timeout semantics;
7. clean drain без process leaks.

Checkpoint target: `v16.5.2-foundation-network-n1`.

## Затем

```text
N2 multi-process harness
→ R3.1 persistence/crash recovery и migration старого user-state
→ N3 World Directory + leases
→ N4 cross-server handoff
→ N5 ghost replicas
```

## Не расширять до N1.3

- UI-I3 batch/multi-select;
- optimistic inventory mutation;
- второй authoritative simulation-server;
- World Directory;
- player prediction;
- ghost streaming;
- распределённую физику.

## Merge gate

```text
editor import/parse
все test_*.gd объявлены в regression runner
N0/N1 network profile
N1.2 dedicated runner
полный Godot regression
main scene CLI
simulation-server lifecycle
real ENet server/client command process
no process leaks
no stale checkpoint/build ID
git diff --check
```

Новый этап получает новую ветку. Review fixes текущего непринятого этапа выполняются в той же ветке отдельными `fix(...)` коммитами.
