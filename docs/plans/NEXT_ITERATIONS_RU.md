# Ближайшие итерации после v16.3

## Зафиксированный checkpoint

Текущий проверенный код:

```text
v16.3.3-foundation-world-aggregate-part3-fix1
```

Основание решения:

- `docs/checkpoints/2026-07-27_V16_3_FOUNDATION_AND_NETWORK_CHECKPOINT_RU.md`;
- `docs/architecture/audits/2026-07-27_V16_3_ARCHITECTURE_AND_NETWORK_AUDIT_RU.md`.

## Динамика версий

| Версия/этап | Состояние | Роль |
|---|---|---|
| `v15.5.2-r0` | принято | repository и regression stabilization |
| `v15.6.2-r1.1-fix2` | принято | UUID, ItemStateStore, полный SpatialRef |
| `v15.7.0-r1.2` | принято | revisions, fingerprints, operation ledger |
| `v15.8.1-r1.3-fix1` | принято | gravity wells и recursive physical mass |
| `v16.0.1-r2-fix1` | принято | полный Item Graph и player inventory |
| `v16.1.0-r2-stack-controls` | принято | stack merge/split и BULK auto-stack |
| `v16.2.0-r2-placement-debug-ui` | принято | placeable mount, admin UI, console, flashlight |
| `v16.3.0-r2-inventory-ux` | принято | contextual containers, post-drop split, operation namespace, dual-fill light |
| `v16.3.1-foundation-n0-part1-fix3` | принято | строгая N0 command/snapshot boundary и loopback |
| `v16.3.2-foundation-lifecycle-part2-fix2` | принято | fail-closed shutdown, terrain drain и terminal world-load fence |
| `v16.3.3-foundation-world-aggregate-part3-fix1` | текущий checkpoint | canonical WORLD aggregate, Item Graph v2, kernel/presentation boundary и entity/chunk lifecycle |
| `v16.4 Foundation Gate` | в работе | завершить общие kernel/repository ports и закрыть acceptance gate |
| `N0` | следующий network-этап | versioned contracts без сокетов |
| `R3.1` | параллельный gameplay | foundation и construction aggregate |
| `N1` | после N0/Foundation | один server + bot client |
| `N2` | после N1 | local multi-process lab |
| `N3` | после N2 | World Directory и leases |
| `N4` | после N3 | handoff одного объекта |

## Итерация A — v16.4 Foundation Gate

Полный план: `docs/plans/V16_4_FOUNDATION_GATE_PLAN_RU.md`.

Минимальный scope:

1. `RuntimeRole` и launch options;
2. `SimulationKernel` без presentation — boundary реализована в v16.3.3;
3. подключаемый `PresentationHost` — реализован для глобального UI в v16.3.3;
4. shutdown barrier — выполнено в v16.3.2;
5. entity/chunk lifecycle — выполнено в v16.3.3;
6. `WorldEntityAggregate` — выполнено для WORLD-items в v16.3.3;
7. revision monotonicity;
8. isolated user data.

Критерий:

> Headless simulation role запускается без UI, завершает active terrain workers и
> выходит code 0, сохраняя старую offline regression зелёной.

## Итерация B — N0 Network Contracts

Полный план: `docs/network/N0_NETWORK_CONTRACTS_PLAN_RU.md`.

Минимальный scope:

- versioned command/snapshot DTO;
- authority lease/route DTO;
- handoff state machine;
- canonical fixtures;
- runtime-type lint;
- local loopback transport interface;
- отдельный runner и JSON report.

Критерий:

> Все network contracts проходят round-trip и fencing tests без открытия сокетов.

## Параллельная работа A+B

Допускается параллельная разработка, если каталоги ответственности разделены:

```text
Core Foundation:
  scripts/simulation/kernel/
  scripts/simulation/lifecycle/
  scripts/app/runtime_roles/

Network N0:
  scripts/network/contracts/
  scripts/network/handoff/
  tests/network/
  config/network/fixtures/
```

Общая точка интеграции — `CommandGateway` и `WorldEntityAggregate`.

## Итерация C — N1 + R3.1

### N1

- simulation-server role;
- bot-client role;
- ENet adapter;
- initial snapshot;
- удалённая команда перемещения маяка;
- checksum equality.

### R3.1

- foundation item/aggregate;
- placement preview;
- validation поверхности;
- socket graph;
- save/restart;
- remote-command-ready handler.

Оба потока используют один command envelope и один aggregate serializer.

## Итерация D — N2

- Python process harness;
- readiness через JSONL;
- свободные порты;
- отдельный user data dir;
- restart/reconnect;
- duplicate command;
- timeout и cleanup;
- JSON/JUnit result.

## Итерация E — N3

- in-memory World Directory;
- node descriptors;
- authority routes;
- lease acquire/renew/release;
- два статических region owner;
- stale epoch rejection.

## Итерация F — N4

- freeze source aggregate;
- snapshot transfer;
- prepare target;
- atomic authority commit;
- source demotion;
- no duplicate authority;
- conservation checks для item quantity, UUID, mass и velocity.

## Обязательные merge gates

Каждый core/gameplay patch:

```text
existing offline regression
snapshot round-trip
no direct presentation mutation
process cleanup where applicable
```

Каждый network patch:

```text
existing offline regression unchanged
network contract tests
isolated user data
JSON report
no Godot runtime types in DTO
```

## Отдельный технический долг

Параллельно, но без подмены основного этапа:

- legacy manifest migration/изоляция;
- terrain worker shutdown;
- декомпозиция больших orchestration-файлов;
- Linux/Windows runner parity;
- обновление acceptance docs после каждого checkpoint.
