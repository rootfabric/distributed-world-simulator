# Checkpoint v16.3.1 fix2 — пограничная строгость N0

## Статус

Исправляющий checkpoint:

```text
v16.3.1-foundation-n0-part1-fix2
```

Он закрывает вторую волну пограничных дефектов сетевой границы, найденных при
повторной независимой ревизии. Функциональный объём N0 не расширен.

## Исправления

### 1. Непротиворечивый handler result

Сочетание `success=true` и `retryable=true` запрещено как
`INVALID_HANDLER_RESULT`. Безопасный терминальный отказ сохраняется, поэтому
повторная доставка не вызывает handler и не повторяет уже выполненную мутацию.

Решение о записи operation replay теперь принимается по итоговому статусу:
`SUCCEEDED` и `REJECTED` терминальны, `RETRYABLE` не сохраняется.

### 2. Safe JSON integer на любой глубине

Канонизатор отклоняет целые значения за пределами
`[-9007199254740991, 9007199254740991]` не только в полях envelope, но и внутри:

- command/result payload;
- physics_state;
- domain_components;
- spatial_ref arrays и sample_time.

Это предотвращает потерю точности и изменение fingerprint/hash после JSON
round-trip.

### 3. Строгий вложенный SpatialRef

`EntitySnapshotEnvelope` больше не использует permissive legacy `is_valid()` как
сетевую schema boundary. Вложенный `spatial_ref` требует точный набор полей,
точные JSON-типы, обязательный `sample_time_s`, массивы ровно 3/4 компонентов и
запрещает дополнительные поля.

Legacy `SpatialRef.normalize/is_valid` сохранены для локальной миграции и
persistence; сеть применяет более строгий контракт.

## Тесты

Добавлены негативные сценарии:

- `success=true + retryable=true`;
- replay такого результата без второго вызова handler-а;
- настоящий RETRYABLE повторно вызывает handler;
- unsafe integer внутри command/result payload;
- unsafe integer внутри physics_state/domain_components;
- numeric frame_id;
- отсутствующий sample_time_s;
- дополнительное поле spatial_ref;
- массив position_m неверной длины.

Следующий основной этап остаётся:

```text
v16.3.2-foundation-lifecycle-part2
```
