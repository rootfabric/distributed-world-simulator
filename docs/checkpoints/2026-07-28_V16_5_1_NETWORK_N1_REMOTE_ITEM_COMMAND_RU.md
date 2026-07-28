# Checkpoint v16.5.1 — N1.2 remote authoritative item command

**Дата:** 28 июля 2026 года
**База:** `v16.5.0-network-n1-snapshot`
**Ветка:** `feature/n1-remote-item-command`
**Build ID:** `n1-enet-authoritative-item-command`

## Цель

Доказать первый полный authoritative domain-command path между отдельными Godot-процессами:

```text
bot-client
→ ENet
→ NetworkCommandEnvelope(item.move_to_container)
→ simulation-server
→ ItemTransferService
→ Item/Container registries + operation ledger
→ WorldEntityAggregate
→ EntityDeltaEnvelope
→ ENet
→ bot-client
→ equal final checksum
```

## Реализовано

- строгий `planet_simulator.item_move_to_container_payload.v1`;
- строгий `planet_simulator.item_move_to_container_result.v1`;
- server-owned item/container/WORLD aggregate fixture;
- handshake capabilities и contract versions для команды и delta;
- owner, epoch, session, entity, aggregate revision, item revision и membership fencing;
- реальная mutation существующим `ItemTransferService.move_item()`;
- ровно одна terminal запись operation ledger;
- монотонное обновление aggregate revision и `server_tick`;
- создание и повторная проверка `EntityDeltaEnvelope` против authoritative snapshot;
- client-side delta apply и итоговое равенство checksum;
- exact command replay без повторного handler/mutation;
- duplicate delta replay fence;
- конфликт одного operation ID с другим payload;
- stale revision rejection после успешной команды;
- transactional rollback registries, ledger и aggregate при ошибке commit;
- исправление ENet peer-disconnect race без обращения к уже удалённому peer ID.

## Инварианты

```text
authoritative mutations = 1
operation ledger records = 1
aggregate revision: 12 → 13
item revision: 0 → 1
server tick: 500 → 501
source membership: true → false
destination membership: false → true
client final checksum = server final checksum
```

Exact replay возвращает прежний terminal result и тот же delta, но не вызывает domain handler второй раз. Клиент распознаёт повторный delta ID/checksum и не применяет его повторно.

## Тесты этапа

- `tests/network/test_n1_remote_item_command_contracts.gd`;
- `tests/network/test_n1_remote_item_command_processes.gd`;
- `RUN_N1_REMOTE_ITEM_COMMAND_TESTS.ps1`;
- оба теста включены в `RUN_NETWORK_CONTRACT_TESTS.ps1` и полный regression manifest.

Отдельно проверяются malformed DTO, неизвестные поля, runtime objects, noncanonical identifiers, owner/session/source/destination/item/revision fences, exact replay, replay conflict, stale epoch/revision и rollback.

## Результаты проверки

Использован Godot `4.7.1.stable.double.custom_build.a13da4feb`, Linux x86_64, double precision.

```text
N1.2 contracts:                 129/129 PASS
N1.2 ENet process:               51/51 PASS
Network profile:                 17/17 suites PASS
Network assertions:             1579/1579 PASS
Godot regression manifest:       60/60 PASS markers
Runner steps с import/main:      63/63
Main scene:                       6 PASS, 0 FAIL
Simulation-server process:       PASS
git diff --check:                PASS
```

Тяжёлые runtime-наборы подтверждены отдельно:

```text
test_unified_runtime_boot:            PASS
test_world_switch_during_generation: PASS
test_world_boot_matrix:              PASS
```

На Linux после PASS-маркера тяжёлого boot-теста возможна задержка завершения процесса из-за runtime worker cleanup. На Windows штатный runner должен подтверждать exit code каждого шага. Старый несовместимый `user://worlds/moon-experiment-001/world.json` остаётся известным fail-closed техническим долгом R3.1 и не относится к N1.2.

## Что не входит

- reconnect с новой transport session;
- replay cache после перезапуска simulation-server;
- несколько клиентов;
- World Directory;
- lease renewal service;
- cross-server handoff;
- batch inventory commands.

## Следующий этап

```text
N1.3 — reconnect + replay
```

Ветка после принятия checkpoint:

```text
feature/n1-reconnect-replay
```

N1.3 должен разорвать соединение после отправки команды, создать новую session, повторить прежний `operation_id`, вернуть сохранённый result/state и подтвердить, что mutation count остаётся равным одному.
