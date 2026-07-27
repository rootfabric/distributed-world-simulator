# Checkpoint v16.3.1 Foundation/N0 Part 1 fix3

Дата: 2026-07-27

```text
v16.3.1-foundation-n0-part1-fix3
```

Патч усиливает протокольную границу после независимой повторной проверки fix2.
Предыдущие исправления остаются закрытыми; fix3 добавляет два дополнительных
P2-инварианта для snapshot canonicalization и обработки malformed commands.

## 1. Канонический quaternion в EntitySnapshotEnvelope

Строгий сетевой `spatial_ref` теперь принимает только quaternion с длиной,
близкой к `1.0`. Значение `[0, 0, 0, 2]` отклоняется как неканоническое, хотя
после локальной нормализации оно могло бы описывать ту же ориентацию.

После успешной валидации snapshot normalization:

1. нормализует quaternion до точной единичной длины;
2. устраняет двойное представление `q` и `-q`;
3. выбирает положительный `W`, а для поворота на 180 градусов применяет
   детерминированный XYZ tie-breaker.

В результате физически эквивалентные единичные quaternion имеют одинаковый
`snapshot_hash`.

Локальный permissive `SpatialRef` не изменён: строгие правила относятся только
к versioned network snapshot boundary.

## 2. Безопасная корреляция malformed command

Command с пустым или неверно типизированным `message_id`/`operation_id` не
может быть отражён напрямую в строгий result envelope. Gateway теперь подставляет:

```text
message/invalid
operation/invalid
```

только для повреждённого correlation field. Корректный соседний ID сохраняется.
Result остаётся валидным `REJECTED` envelope и несёт исходную причину:

```text
EMPTY_FIELD
INVALID_FIELD_TYPE
```

Malformed command не записывается в operation replay ledger и не вызывают
handler.

## 3. Тесты

Расширены:

- `tests/network/test_network_contracts.gd`;
- `tests/network/test_loopback_command_transport.gd`.

Проверяются:

- отказ для quaternion длины `2.0`;
- одинаковый hash для `q` и `-q`;
- канонический знак после normalize;
- пустой `message_id`;
- пустой `operation_id`;
- числовые correlation IDs;
- сохранение исходного validation error;
- валидность возвращаемого result envelope.

Следующий основной этап не меняется:

```text
v16.3.2-foundation-lifecycle-part2
```
