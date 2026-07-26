# Чекпоинт R1.2 — ревизии, payload fingerprint и operation ledger

Дата: 27 июля 2026 года
Версия: `v15.7.0-r1.2`
База: принятый `v15.6.2-r1.1-fix2`

## Цель

R1.2 делает команды изменения предметного aggregate безопасными для повторной
доставки, перезапуска runtime и оптимистичной конкуренции.

Главный контракт этапа:

> Одна логическая команда имеет глобальный `operation_id`, точный payload hash и
> ожидаемую ревизию aggregate. Точный повтор возвращает прежний результат без
> повторной мутации, другой payload с тем же ID отклоняется, а устаревшая
> ревизия не может перезаписать новое состояние.

## Командный envelope

Для `MOVE_ITEM` и `SPLIT_AND_MOVE` fingerprint строится из JSON-канонического
payload:

```text
schema
schema_version
command_type
aggregate_id
expected_revision
payload
```

Словари сортируются при сериализации, числовые значения записываются с полной
точностью, после чего вычисляется lowercase SHA-256. Порядок добавления ключей в
Dictionary не влияет на hash.

## Optimistic concurrency

Методы получили необязательный аргумент:

```gdscript
move_item(item_id, relation, operation_id, expected_revision = -1)
split_and_move(item_id, quantity, relation, operation_id, expected_revision = -1)
```

`expected_revision >= 0` включает строгую проверку. Несовпадение возвращает:

```text
REVISION_CONFLICT
expected_revision
actual_revision
result_revision
```

Значение `-1` оставлено как compatibility-режим без precondition для старых
вызовов. Новые сетевые, persistence и gameplay-команды должны передавать точную
известную ревизию.

## Идемпотентность

Operation ledger хранит terminal-команды со статусами:

```text
SUCCEEDED
REJECTED
```

Запись содержит:

```text
sequence
operation_id
command_type
payload_hash
aggregate_id
expected_revision
result_revision
status
result
```

Поведение:

1. отсутствующий `operation_id` отклоняется;
2. новый ID исполняет команду;
3. тот же ID и тот же hash возвращают сохранённый `result` без мутации;
4. тот же ID и другой hash возвращают `OPERATION_ID_CONFLICT`;
5. conflict не заменяет исходную запись;
6. terminal reject также повторяется детерминированно.

## Retryable ошибки

Ошибки доступности, которые могут исчезнуть без изменения команды, не
записываются как terminal:

```text
ITEM_NOT_FOUND
CONTAINER_NOT_FOUND
SPLIT_CREATE_FAILED
```

Они возвращают статус `RETRYABLE`. После появления отсутствующей зависимости та
же команда с тем же `operation_id` может быть выполнена повторно и только после
успеха попадает в ledger.

Бизнес-конфликты, включая `REVISION_CONFLICT`, являются terminal и требуют нового
`operation_id` после обновления состояния клиентом.

## Persistence

Добавлен versioned ledger:

```text
planet_simulator.item_operation_ledger.v1
```

Он поддерживает:

```gdscript
to_dict()
load_dict()
save_to_store(item_state_store, state_key)
load_from_store(item_state_store, state_key)
```

Загрузка транзакционная и fail closed. Проверяются схема, версия, уникальность
`operation_id` и sequence, SHA-256, статусы, ревизии и согласованность metadata
внутри сохранённого результата.

Ledger ограничен по размеру. Значение по умолчанию — 2048 terminal-записей;
после превышения удаляется запись с минимальным sequence. Настройка передаётся в
`ItemDomainFactory.create(maximum_entries)`.

На R1.2 ledger сохраняется через уже существующий `ItemStateStore` отдельным
versioned state. Автоматическая атомарная запись Items + Containers + Attachments
+ Ledger одним snapshot остаётся задачей R1.4.

## Split aggregate

`SPLIT_AND_MOVE` использует ревизию исходного стека как aggregate revision.
Результат дополнительно сообщает:

```text
source_result_revision
moved_item_result_revision
new_item_id
split_quantity
```

Точный replay не уменьшает исходный стек повторно и не создаёт второй предмет.

## Тестовый барьер

Добавлен:

```text
res://tests/items/test_item_operation_ledger.gd
```

Он проверяет:

1. одинаковый hash для словарей с разным порядком ключей;
2. участие command type и expected revision в fingerprint;
3. exact replay успешной команды;
4. `OPERATION_ID_CONFLICT` для другого payload;
5. `REVISION_CONFLICT` и сохранение текущей revision;
6. детерминированный replay terminal rejection;
7. split replay без повторного уменьшения и создания;
8. retryable failure без poisoning ledger;
9. успешный повтор после появления контейнера;
10. bounded history и удаление самой старой записи;
11. JSON round-trip полного ledger;
12. fail-closed загрузку будущей версии;
13. сохранение ledger через ItemStateStore;
14. replay после полного пересоздания domain runtime;
15. conflict с persisted operation ID после перезапуска.

Существующий item-domain тест обновлён: прежнее небезопасное поведение, при
котором другой payload с тем же operation ID возвращал старый успех, теперь
обязательно отклоняется.

Тест включён в:

```powershell
.\RUN_ITEM_SYSTEM_TESTS.ps1
.\RUN_WORLD_REGRESSION_TESTS.ps1
```

Общий regression manifest содержит 27 тестов.

## Не входит в R1.2

- expected revision контейнера и multi-aggregate transaction token;
- автоматический autosave ledger после каждой команды;
- единый атомарный snapshot всего item graph;
- distributed authority ownership и replication;
- world-specific gravity и рекурсивная физическая масса — R1.3;
- полная загрузка container/attachment/entity graph — R1.4.

## Критерий приёмки

R1.2 принят, когда:

```powershell
.\RUN_ITEM_SYSTEM_TESTS.ps1
.\RUN_WORLD_REGRESSION_TESTS.ps1
```

завершаются успешно на double-precision console Godot, полный runner обнаруживает
27/27 тестов, выполняет 30/30 шагов с main-scene regression и создаёт отчёт с:

```text
checkpoint = v15.7.0-r1.2
passed = true
```
