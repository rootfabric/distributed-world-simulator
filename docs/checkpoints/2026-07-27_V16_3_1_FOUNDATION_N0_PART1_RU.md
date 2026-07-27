# Checkpoint v16.3.1 — Foundation/N0 Part 1

## Статус

Частично выполнен путь к `v16.4.0-foundation-n0`.

Текущий checkpoint:

```text
v16.3.1-foundation-n0-part1
```

Эта часть намеренно не объявляет Foundation Gate или N0 завершёнными. Она
закрывает контракты запуска, первую часть versioned network DTO, локальный
JSON-loopback и монотонность revision при смене authority.

## Реализовано

### Runtime role contract

Добавлены роли:

```text
offline
client
simulation-server
bot-client
```

Добавлен pure-domain parser параметров:

```text
--role
--world
--run-tests
--node-id
--instance-id
--space-id
--authority-region
--user-data-dir
--print-runtime-descriptor
```

Неизвестные параметры и роли отклоняются. Текущий offline-запуск сохраняет
прежнее поведение.

### Runtime descriptor

Добавлен versioned DTO:

```text
planet_simulator.runtime_descriptor.v1
```

Он содержит role, node ID, world, instance, space, process ID, protocol version,
checkpoint и признаки presentation/input/authority.

`SimulatorApp` передаёт launch options и descriptor в context загружаемого мира.
Доступна команда:

```text
runtime.descriptor
```

### N0 command boundary

Добавлены схемы:

```text
planet_simulator.network_command.v1
planet_simulator.network_command_result.v1
planet_simulator.entity_snapshot_envelope.v1
```

Command envelope содержит operation ID, entity ID, command type, payload,
expected revision, authority epoch, client tick и transport metadata.

### Canonical JSON contract

Добавлен общий JSON-safe canonicalizer. Он:

- принимает только JSON-совместимые Variant-типы;
- отклоняет `Node`, `Object`, `RID`, `Resource`, `Callable`, `NodePath` и другие
  runtime-типы;
- отклоняет NaN и Infinity;
- использует full-precision JSON и сортировку ключей;
- создаёт стабильный SHA-256 fingerprint.

### Loopback command gateway

Добавлен локальный transport, который обязательно проходит через:

```text
Dictionary
→ canonical JSON
→ JSON parse
→ command gateway
→ result envelope
→ canonical JSON
→ JSON parse
```

Поддерживаются:

- регистрация command handler;
- exact replay без повторного вызова handler;
- `OPERATION_ID_CONFLICT` для другого payload;
- `STALE_AUTHORITY_EPOCH`;
- `UNKNOWN_COMMAND_TYPE`;
- transport message correlation при replay.

Сокеты не используются.

### Authority revision semantics

Исправлен `EntityRecord.transfer_authority()`.

Раньше authority transfer сбрасывал:

```text
state_revision = 0
revision = 0
```

Теперь owner и epoch меняются, а state revision увеличивается ровно один раз и
никогда не уменьшается.

## Тесты

Добавлены:

```text
tests/runtime/test_launch_options.gd
tests/network/test_network_contracts.gd
tests/network/test_loopback_command_transport.gd
tests/entities/test_authority_revision_semantics.gd
```

Профильный runner:

```text
RUN_NETWORK_CONTRACT_TESTS.ps1
```

Regression manifest расширен с 34 до 38 тестов.

## Фактическая проверка Linux double Godot

Использован:

```text
Godot 4.7.1.stable.double.custom_build.a13da4feb
```

Результаты новой части:

```text
Runtime launch option contracts:   PASS — 19 assertions
N0 network contracts:              PASS — 15 assertions
N0 loopback command transport:     PASS — 16 assertions
Authority revision semantics:      PASS — 15 assertions
Main scene playground:             PASS — 6/6
World switch during generation:    PASS
```

Старые unit/domain/item-тесты также прошли до тяжёлого runtime-блока.

## Незафиксированные как PASS lifecycle-тесты

Два старых тяжёлых теста остаются блокерами следующей части:

1. `test_unified_runtime_boot` может удерживать процесс во время активной terrain
   generation и не завершать Godot в пределах process timeout.
2. `test_world_boot_matrix` повторно сталкивается с несовместимым
   `moon-experiment-001/world.json` при последовательной загрузке разных grid
   configurations.

Это не скрывается как зелёный результат. Исправление относится к следующей
части Foundation Gate: isolated user data + lifecycle/shutdown barrier.

## Что ещё не реализовано

Foundation:

- реальный `SimulationKernel`;
- отключаемый `PresentationHost`;
- server boot без UI/камер;
- lifecycle coordinator;
- terrain shutdown barrier;
- isolated user data enforcement;
- `WorldEntityAggregate`.

N0:

- EntityDeltaEnvelope;
- AuthorityLease и AuthorityRoute;
- node/space/region descriptors;
- handoff ticket/result и state machine;
- golden fixtures;
- snapshot checksum field;
- полный network JSON report с N0 acceptance matrix.

## Исправление boundary validation

Строгая проверка обязательных полей, JSON-типов и handler result была усилена в
`2026-07-27_V16_3_1_FOUNDATION_N0_PART1_FIX1_RU.md`. Этот документ сохраняет
исходный checkpoint Part 1, а fix1 является его исправляющим дополнением.

## Следующая часть

Рекомендуемый следующий checkpoint:

```text
v16.3.2-foundation-lifecycle-part2
```

Объём:

1. `LifecycleCoordinator`;
2. process states STARTING/READY/STOPPING/STOPPED/FAILED;
3. isolated user data per process/test;
4. terrain `request_stop/is_drained/await_drained`;
5. process test, который завершает Godot при активном worker;
6. минимальный presentation-disabled server boot contract.
