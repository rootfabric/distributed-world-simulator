# Checkpoint v16.4.0 Foundation N0 fix1

**Версия:** `v16.4.0-foundation-n0-fix1`
**Build ID:** `foundation-n0-authority-monotonicity-kernel-port-type-fix1`
**Базовый коммит:** `115183c`
**Дата проверки:** 28 июля 2026 года
**Godot:** `4.7.1.stable.double.custom_build.a13da4feb`, Linux x86_64

## Причина исправления

Независимая проверка принятого N0 обнаружила шесть обходов заявленных
инвариантов:

1. snapshot и delta допускали смену `authority_owner_id` без повышения
   `authority_epoch`;
2. snapshot допускал откат `state_revision` при повышенном epoch;
3. путь `physics_state..sleeping` нормализовался в валидный из-за удаления
   пустых сегментов при `split()`;
4. delta допускал откат `server_tick`;
5. объект произвольного класса мог имитировать kernel port подходящим
   descriptor;
6. дополнительная проверка выявила, что повышение epoch с равным revision могло
   скрыть изменение physics/domain state;
7. штатный N0-профиль не содержал негативных тестов на эти обходы.

## Исправления контрактов

### EntityDeltaEnvelope

- authority owner обязан совпадать с owner базового snapshot;
- `server_tick` не может уменьшаться;
- путь разбирается с сохранением пустых сегментов;
- ведущая, завершающая, двойная или тройная точка отклоняется;
- setters и erasers повторно проверяют каждый сегмент и работают fail-closed;
- отказ не изменяет исходный snapshot.

### LoopbackReplicationTransport

Для уже известной сущности действуют единые монотонные fences:

- `entity_type` неизменяем;
- прежний epoch требует прежнего authority owner;
- `state_revision` не может уменьшаться даже при повышении epoch;
- `server_tick` не может уменьшаться даже при повышении epoch;
- при равном revision повышение epoch допускает только смену authority metadata,
  но не изменение spatial/partition/physics/domain state;
- duplicate/replay не выполняет повторную мутацию.

Повышение epoch с прежним owner и равным revision разрешено: revision является
монотонным неубывающим счётчиком и не обязан изменяться только из-за обновления
lease/epoch.

### Kernel ports

`SimulationKernel` теперь проверяет не только внешне похожий descriptor:

- точный script `EntityRegistryKernelPort` или `WorldRepositoryKernelPort`;
- точный набор полей descriptor без дополнительных ключей;
- типы и значения каждого поля;
- configured-state порта;
- внутренний registry/repository snapshot;
- неизменность уже подключённого порта после неуспешной регистрации.

Объект другого класса с правильными `schema` и `configured=true` отклоняется.
Повреждённый экземпляр настоящего port script также отклоняется.

## Контрольные probes

После исправления:

```text
noncanonical_path_accepted:          false
delta_owner_change_accepted:         false
delta_tick_rollback_accepted:        false
snapshot_owner_change_accepted:      false
snapshot_revision_rollback_accepted: false
forged_kernel_port_accepted:         false
```

## Новые тесты

Добавлен `tests/network/test_n0_review_regressions.gd`:

- canonical и invalid path matrix;
- owner/epoch fencing для snapshot и delta;
- revision/tick rollback matrix;
- entity type immutability;
- отсутствие мутации store при отказе;
- допустимые monotonic/replay сценарии.

Расширен `tests/runtime/test_kernel_ports.gd`:

- forged entity/repository ports;
- дополнительные и ошибочно типизированные descriptor fields;
- неверные capabilities;
- повреждённое внутреннее состояние настоящих ports;
- сохранение ранее подключённого валидного порта после отказа.

## Результаты проверки

### N0 profile

```text
Test suites:  12/12 PASS
Assertions:   1200/1200 PASS
```

В том числе:

```text
N0 review regressions: 73/73
Kernel ports:          52/52
Loopback replication: 29/29
Mutation matrix:      372/372
Handoff matrix:       262/262
Golden fixtures:      159/159
```

### Полный Godot regression

```text
Обнаружено test scripts: 52
Заявлено в runner:       52
PASS:                    52
FAIL:                     0
Editor import/parse:   PASS
Main scene CLI:        PASS
```

Тяжёлые runtime-наборы также выполнены отдельно в чистых процессах:

```text
test_unified_runtime_boot:           PASS, 29.284 s
test_world_switch_during_generation: PASS, 17.001 s
test_world_boot_matrix:              PASS, 42.400 s
```

### Simulation-server process

```text
node_ready -> node_draining -> node_stopped
exit code:                    0
active presentation nodes:    0
local input:                  false
EntityRegistry kernel port:   connected
Repository kernel port:       connected
terrain drain:                2464 ms
```

## Граница этапа

Fix1 не расширяет N0 до сетевого runtime. По-прежнему намеренно отсутствуют:

- реальные ENet/WebSocket sockets;
- отдельный удалённый bot client;
- исполняемый World Directory и lease renewal service;
- cross-process authority handoff;
- ghost streaming между серверами.

Следующий этап остаётся N1: authoritative simulation-server, отдельный
bot-client, реальный transport adapter, initial snapshot, одна удалённая item
command и checksum equality.
