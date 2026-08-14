# V0-S1: Design Brief исправления обычного запуска

**Risk:** HIGH (`PERSISTENCE_CHANGE`)
**Branch:** `feature/v0-s1-networked-planetary-outpost-mvp`
**Project base:** `09714b6f2681e3b5cf3f2f9e28416cf9a7378304`
**Observed head:** `d235e1566ba7b36a8782b61f23b35b9405fb8df4`

## Проблема

Обычный запуск `main.tscn` повторно читает ранее записанный
`user://worlds/moon-experiment-001/world.json` и ошибочно отклоняет собственный
manifest как несовместимый. JSON parser возвращает числа как `float`, тогда как
runtime descriptor содержит дискретные identity-поля как `int`. Текущая
проверка сравнивает их строковые представления (`"1.0" != "1"`).

Дальнейшая инициализация получает неинициализированный repository snapshot,
kernel port отклоняет его с `CHECKSUM_MISMATCH`, runtime выгружается, а окно
остаётся чёрным.

После устранения manifest mismatch проявился второй независимый дефект: сохранённый
item graph содержит high-precision `float`. В используемом double-build Godot JSON
round-trip может изменить несколько последних битов такого числа. Entity snapshot
считал checksum до transport boundary, поэтому loopback client отклонял валидный
authority snapshot с `CHECKSUM_MISMATCH`. Checksum теперь использует ограниченную
13 значащими десятичными цифрами числовую identity; само payload и save format не
переписываются.

## Желаемое поведение

- JSON-эквивалентные числовые identity (`1` и `1.0`) считаются одинаковыми.
- Реально отличающиеся revision/grid значения остаются fail-closed.
- Формат manifest, ownership и persistence paths не меняются.
- Повторное открытие только что записанного manifest проходит.
- Entity snapshot сохраняет checksum после JSON transport даже для high-precision
  double-значений из ранее сохранённого item graph.

## Рассмотренные варианты

1. Удалять пользовательский world manifest при запуске — отклонено: потеря
   persistence и маскировка дефекта.
2. Переписывать JSON числа в строки — отклонено: изменение save format.
3. Нормализовать только числовое сравнение identity — выбран минимальный вариант,
   сохраняющий формат и fail-closed семантику.

## Scope

Разрешённые пути:

- `scripts/persistence/lunar_world_repository.gd`;
- `scripts/network/contracts/entity_snapshot_envelope.gd`;
- `tests/integration/test_persistence_roundtrip.gd`;
- `tests/network/test_network_contracts.gd`;
- этот Design Brief;
- локальная Codex MCP-конфигурация для выбора правильного checkout.

Non-goals: migration ownership, новый save format, очистка пользовательского
мира, изменение authority ownership или V0 gameplay.

## Проверка

1. Regression: repository повторно открывает записанный JSON manifest.
2. Existing foreign instance и incompatible grid остаются rejected.
3. High-precision entity snapshot валиден после JSON transport.
4. Обычный `main.tscn` больше не выдаёт manifest/checksum ошибки.
5. Focused V0-S1 suite и Earth graphical multiprocess остаются PASS.
