# Checkpoint v16.3.1 fix1 — усиление сетевой границы N0

## Статус

Исправляющий checkpoint:

```text
v16.3.1-foundation-n0-part1-fix1
```

Он не расширяет функциональный объём N0, а закрывает три дефекта первой версии
сетевой границы, найденные при внешней ревизии контрактов.

## Исправленные дефекты

### 1. Обязательность payload

`NetworkCommandEnvelope` больше не подставляет отсутствующий `payload` как `{}`.
Все поля схемы v1 обязательны. Отсутствующее поле возвращает `MISSING_FIELD`.

### 2. Невалидный результат handler-а

Gateway теперь проверяет внутренний handler result и итоговый
`NetworkCommandResultEnvelope` до записи terminal replay.

Если handler уже выполнил мутацию, но вернул несериализуемое или структурно
невалидное значение, gateway:

1. не сохраняет сломанный объект;
2. создаёт JSON-safe `REJECTED / INVALID_HANDLER_RESULT`;
3. устанавливает `requires_snapshot=true`;
4. сохраняет безопасный терминальный результат;
5. при повторной доставке не вызывает handler второй раз.

Это ограничивает повреждение одним исполнением и требует authoritative snapshot
для восстановления клиента. Полная транзакционность handler-а остаётся отдельным
требованием будущего Command Gateway.

### 3. Строгая schema validation

Command, result и snapshot envelopes теперь:

- требуют точный набор полей;
- отклоняют дополнительные поля;
- не преобразуют числа в строки и строки в числа;
- отклоняют дробные revision/epoch/tick;
- принимают integer-valued JSON number после реального JSON round-trip;
- ограничивают целые безопасным диапазоном IEEE-754;
- требуют `payload`, `physics_state` и `domain_components` как Dictionary.

JSON-канонизатор приводит `3` и `3.0` к одной числовой форме, поэтому command
fingerprint и snapshot hash не меняются после сериализации через транспорт.

## Дополнительная защита transport

`LoopbackCommandTransport` валидирует ResultEnvelope до сериализации и повторно
после JSON parse. Альтернативный gateway не может вернуть произвольный
Dictionary как успешный сетевой результат.

## Тесты

Профильный набор теперь содержит:

```text
Runtime launch option contracts:   19 assertions
N0 network contracts:              29 assertions
N0 loopback command transport:     26 assertions
Authority revision semantics:      15 assertions
```

Всего: `89 assertions`.

Негативные проверки включают:

- отсутствующий payload;
- numeric message ID;
- string revision;
- fractional revision/tick;
- дополнительные envelope fields;
- отсутствующий result payload;
- несериализуемый Node внутри handler payload;
- безопасный replay `INVALID_HANDLER_RESULT` без второго вызова handler-а;
- стабильность fingerprint/hash через JSON numeric normalization.

## Оставшийся риск

Gateway не может откатить мутацию, которую handler выполнил до формирования
невалидного результата. Поэтому terminal `INVALID_HANDLER_RESULT` требует
snapshot-resync, а будущий authoritative Command Gateway должен выполнять
команду и публикацию результата в транзакционной границе aggregate.

Следующий основной этап не меняется:

```text
v16.3.2-foundation-lifecycle-part2
```
