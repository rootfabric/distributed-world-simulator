# ADR-006: authority lease, epoch fencing и handoff

**Статус:** предложено к принятию
**Дата:** 2026-07-27

## Контекст

Сервер может упасть, быть заменён или передать объект другому серверу. Постоянное назначение `entity → process` невозможно.

## Решение

1. Entity и interaction island имеют одного authority owner.
2. Право задаётся lease, а не постоянной записью.
3. Каждая смена владельца увеличивает `authority_epoch`.
4. Любая mutation-команда содержит expected revision и authority epoch.
5. Handoff выполняется state machine с prepare/commit/abort.
6. Target не изменяет candidate до commit.
7. Source не изменяет entity после commit.
8. Старый epoch всегда fenced.
9. Ghost/projection read-only.
10. Первая версия допускает короткую паузу, но не дубли authority.

## Инвариант

```text
active_authority_count(entity_or_island, tick) <= 1
```

## Последствия

- handoff становится тестируемой транзакцией;
- split-brain определяется по epoch;
- server process можно безопасно заменить;
- требуется World Directory и durable commit record;
- тесно связанные физические объекты мигрируют островом.
