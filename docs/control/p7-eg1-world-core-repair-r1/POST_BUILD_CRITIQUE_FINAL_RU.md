# Post-build critique — финальный кандидат P7 repair chain

Обязательный один bounded critique pass по итоговому кандидату
(`a52faf8c`, runtime-коммиты `0d8f0f94` ENet, `d24f38da` EG4,
`03c0318d` P7.4 runner, `40b22324` MW10 lock).

Результат: **NO_MATERIAL_REFACTOR_REQUIRED**.

## Появилась ли лишняя сложность?

Нет. Каждый из четырёх product-изменений остался минимальным:
одна строка восстановления bandwidth-контракта в существующем адаптере;
барьер точных шести receipt-ID в lifecycle EG4 test-client; специализация
ровно одного foreach-вызова P7.4 в canonical runner (три фазы, тот же
Invoke-GodotStep); перенос уже принятого в репозитории MW9 lock-паттерна
(атомарный release-rename + fail-closed staleness) в cross-region
repository без новых сущностей.

## Duplicate truth?

Нет. Ожидаемые receipt IDs EG4 порождаются только трафиком самого fixture.
Фазы P7.4 не дублируют gate-скрипты: runner использует те же
`-- --phase=` формы, что и canonical gate. Lock-паттерн не создаёт второй
primitive: репозиторий копирует уже принятую реализацию sibling-а.

## Новый implicit network/persistence owner?

Нет. ENet host initialization остаётся у адаптера; решение о withdrawal — у
EG4 test client; порядок фаз P7.4 — у canonical runner; lock lifecycle — у
самого cross-region repository. Координатор, authority gate, lease, codec,
каналы, delivery modes, retries, тайм-ауты не изменены.

## Sibling path?

Проверены и не потребовали изменений: T1 multi-peer contracts/processes,
NX2 traffic separation, все EG sibling-тесты, MW9 lock retry test
(12 assertions PASS на кандидате), неизменный полный world/core runner.
MW10 coordinator не менялся (delegation уже была корректной).

## Можно ли удалить временный диагностический код?

Диагностические артефакты репозитория не тронуты. Отрицательные контролы
(baseline probes) сохранены намеренно: timing-чувствительные дефекты
доказываются только каузальными negative/positive парами, а не одиночным
зелёным прогоном. Временных продуктовых хуков нет.

## Изменились ли authority / delivery / retry semantics?

Нет. Подтверждается побайтовыми reverse-diff guard-ами (runner blob
197490d8…, EG4 baseline, adapter patch, repository blob-pin) и
неизменностью всех EG/MW воркеров и assertions (53/46/36 assertions
оригинальных сценариев).

## Тест вместо продукта?

Исправление EG4 — test-client lifecycle (owner и был тестовым); P7.4 —
canonical runner (owner оркестрации); MW10 — продуктовый repository
(владелец дефекта); ENet — продуктовый адаптер. Ни в одном случае владелец
не подменён.

## Rank-up moves

- Approved-engine seed artifact истекает 2026-09-14; последующие запуски
  должны поставлять тот же pinned binary через доступный канал.
- Идентификатор probe-отчёта (hyphen/underscore) унифицирован; новые
  probes должны брать имя из единого места.

Required fixes: отсутствуют.
