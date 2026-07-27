# Checkpoint v16.3.2 fix1 — Foundation Lifecycle Fail-Closed

**Дата:** 27 июля 2026 года
**Версия:** `v16.3.2-foundation-lifecycle-part2-fix1`
**Основа:** `v16.3.2-foundation-lifecycle-part2`

## Цель исправления

Закрыть два отказных сценария, которые не покрывались успешными lifecycle-тестами:

1. `begin_shutdown()` может завершиться ошибкой, когда coordinator уже находится в `FAILED`;
2. runtime drain может вернуть `success=false` или `drained=false`.

В обоих случаях система должна действовать fail-closed и не сообщать об успешной остановке.

## Инвариант освобождения runtime

Runtime можно отсоединить и вызвать `free()` только при одновременном выполнении:

```text
result.success == true
result.drained == true
```

При любом другом результате сохраняются:

- текущий runtime;
- его parent;
- `current_world_id`;
- definition мира;
- detached presentation nodes;
- диагностический drain result.

Устанавливается fence `_runtime_release_blocked`.

## Отказ переключения мира

`load_world()` теперь проверяет результат выгрузки предыдущего мира. При неподтверждённом barrier:

- новый runtime освобождается до добавления в дерево;
- старый runtime остаётся активным;
- world ID не меняется;
- второй runtime не появляется;
- возвращается `RUNTIME_DRAIN_FAILED`.

## Отказ graceful shutdown

Флаг `_shutdown_in_progress` выставляется только после успешного `begin_shutdown()`.

Если begin отклонён, планируется emergency cleanup. Когда активного runtime нет либо он безопасно drained, процесс завершается с ненулевым кодом. Это закрывает зависание окна после startup failure при `auto_accept_quit=false`.

Если runtime drain не подтверждён:

- runtime не освобождается;
- `STOPPING` и `STOPPED` не публикуются;
- `node_stopped` не выводится;
- lifecycle переходит в `FAILED`;
- выводится `node_shutdown_failed`;
- процесс не выполняет небезопасный quit, который разрушил бы дерево с работающим worker.

## Тесты

Добавлен `tests/runtime/test_simulator_shutdown_failures.gd`.

Покрыты:

- ошибка `request_runtime_stop`;
- `success=true, drained=false`;
- блокировка world switch;
- сохранение старого runtime;
- отсутствие перехода в `STOPPED`;
- отсутствие process quit после failed drain;
- ошибка `begin_shutdown()` в состоянии `FAILED`;
- emergency cleanup и ненулевой exit code при отсутствии runtime.

Профильный runner и полный regression включают новый тест.
