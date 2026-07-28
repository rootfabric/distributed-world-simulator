# Ближайшие итерации после v16.4.2-network-transport-boundary

## Зафиксированный checkpoint

```text
v16.4.1-foundation-inventory-merge
```

Этот checkpoint объединяет две ранее разошедшиеся линии:

```text
main: Foundation Part 1–3 + N0 + N0 fix1
feature/ui-i0-inventory-shell: UI-I0 + UI-I1 + UI-I2 + fix1/fix2
```

Merge base веток: `35cb5da`. До объединения `main` имел 8 собственных коммитов,
inventory-ветка — 6. Прямое слияние давало 7 конфликтов: 5 документационных/
runner-конфликтов и 2 кодовых. Дополнительно тест выявил несовместимость старого
UI вызова `drop_item_stack()` с aggregate-aware контроллером Foundation Part 3;
она закрыта совместимым доменным API.

## Что завершено

| Этап | Статус | Результат |
|---|---|---|
| R0–R2 | принято | Item Graph, revisions, operation ledger, placement и contextual inventory |
| Foundation Part 1–3 | принято | runtime roles, lifecycle, kernel boundary, aggregate и persistence ports |
| N0 + fix1 | принято | строгие DTO, loopback, handoff contracts, authority fencing и kernel ports |
| UI-I0 | объединено | component shell, ViewModel, CommandFacade |
| UI-I1 | объединено | drag, quick transfer, context actions, split, tooltip и toast |
| UI-I2 + fix2 | объединено | search/filter/sort, inspector, preferences, bounded pool и cache invalidation |
| v16.4.1-foundation-inventory-merge | текущий | единая mainline без долгоживущей inventory-ветки |

## Текущий этап — N1.0 transport boundary

N1 должен быть одним небольшим сетевым вертикальным срезом, а не началом общего
MMO runtime.

N1 разделён на принимаемые по отдельности checkpoint:

```text
N1.0 общий transport boundary без сокетов
N1.1 ENet handshake + initial snapshot
N1.2 remote item.move_to_container
N1.3 reconnect + replay
```

Подробный план: `docs/network/N1_NETWORK_IMPLEMENTATION_PLAN_RU.md`.

## Следующий после текущего патча этап — N1.1

Обязательный сценарий:

1. запустить headless `simulation-server`;
2. запустить отдельный `bot-client`;
3. выполнить handshake protocol/capabilities;
4. передать initial `EntitySnapshotEnvelope`;
5. отправить одну `item.move_to_container` команду;
6. применить её существующим domain service на сервере;
7. вернуть snapshot или delta;
8. подтвердить равенство checksum клиента и сервера;
9. повторить тот же сценарий через loopback и ENet;
10. корректно завершить оба процесса.

### Границы N1

Не включать:

- второго simulation-server;
- World Directory и lease renewal;
- cross-process handoff;
- player prediction;
- ghost streaming;
- UI-I3 batch operations;
- распределённую физику.

## После N1 — N2 process lab

- Python harness и свободные порты;
- отдельный `user://` для каждого процесса;
- readiness/shutdown JSONL;
- server restart и client reconnect;
- duplicate delivery и operation replay;
- timeout/cleanup;
- JSON/JUnit report.

## После N2 — выбор gameplay или authority

Рекомендуемый порядок:

```text
N1 transport vertical slice
→ N2 reliable multi-process harness
→ R3.1 construction/placement vertical slice
→ N3 World Directory + leases
→ N4 one-entity handoff
```

R3.1 после N2 получит уже проверенный remote-command path и не создаст второй
несовместимый command API.

## UI-I3

Batch/multi-select, take-all/deposit-all и move-matching выполнять только после
N1/N2. Batch обязан иметь один operation ID, атомарный authoritative result и
безопасный replay. До этого UI-I0–UI-I2 считаются завершённым presentation scope.

## Политика веток

После фиксации checkpoint:

- удалить локальные `earth` и `feature/console-space-hotkeys`: они уже входят в `main`;
- закрыть/архивировать `feature/ui-i0-inventory-shell` после merge commit;
- удалить stash с `.godot` cache;
- удалить ранний stash UI-I0 после подтверждения merge checkpoint;
- создавать короткие ветки от текущего `main`;
- не держать gameplay-ветку через несколько foundation/network checkpoints.

Рекомендуемые новые ветки:

```text
feature/n1-transport-boundary
feature/n1-enet-snapshot
feature/n1-remote-item-command
feature/n1-reconnect-replay
feature/n2-network-process-harness
feature/r3-1-construction-slice
```

## Обязательный merge gate

```text
editor import/parse
all discovered test_*.gd declared in runner
56/56 Godot regression tests
main scene CLI tests
simulation-server process lifecycle
network contract profile
no direct presentation mutation
no stale branch-specific project version
```

## Технический долг

- stale `user://worlds/moon-experiment-001` manifest создаёт ожидаемый error log в некоторых runtime-тестах; тесты изолируют данные и проходят, но diagnostic noise стоит убрать отдельной миграцией;
- централизовать project checkpoint/build ID, чтобы не обновлять несколько runtime/fixture точек вручную;
- добавить Linux shell runner, эквивалентный PowerShell runner;
- продолжить декомпозицию крупных orchestration-файлов.
