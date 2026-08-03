# NX5 — Remote Snapshot Interpolation fix1

## Назначение

NX4 обслуживает локального владельца через prediction и reconciliation.
NX5 обслуживает только удалённых игроков: server snapshots попадают в
ограниченный timeline, а `RemotePlayerPresenter` визуализирует состояние с
задержкой 100 мс. Server authority, canonical replica и protocol hash NX4 fix1
не меняются.

## Исправленная модель clock

Accepted M3 может выпустить несколько snapshot revisions внутри одного
`server_tick`: например, movement snapshot и следующий presentation delta.
Поэтому уникальный clock удалённого sample определяется парой:

```text
(server_tick, outer snapshot_revision)
```

Для уже существующего `server_tick` применяются правила:

1. `incoming revision > stored revision` и состояние изменилось — sample
   заменяется authoritative revision того же тика.
2. `incoming revision > stored revision` и состояние идентично — обновляется
   только outer revision, запись считается подавленным дублем.
3. `incoming revision == stored revision` и состояние идентично — точный дубль.
4. `incoming revision == stored revision` и состояние изменилось — конфликт
   `CONFLICTING_REMOTE_SNAPSHOT_TICK`.
5. `incoming revision < stored revision` — stale packet отбрасывается
   нефатально и не меняет presentation target.

Timeline по-прежнему содержит максимум один итоговый sample на server tick,
поэтому interpolation не получает нулевые интервалы и остаётся детерминированной.

## Поток данных

```text
validated PlayerStateSnapshot
  -> remote player + (server_tick, snapshot_revision)
  -> per-player bounded timeline
  -> same-tick authoritative replacement/coalescing
  -> render_tick = estimated_server_tick - 6 ticks
  -> interpolation / <=100ms extrapolation / authoritative hold
  -> position, yaw, flashlight
```

## Основные параметры

- authoritative tick: 60 Гц;
- target snapshot rate: 20 Гц;
- interpolation delay: 6 ticks / 100 мс;
- extrapolation horizon: 6 ticks / 100 мс;
- timeline: максимум 32 samples на игрока;
- teleport fence: 8 м;
- implied-speed fence: 48 м/с.

## Наблюдаемость

Interpolator публикует:

- `same_tick_replacements`;
- `same_tick_stale_dropped`;
- `duplicates_suppressed`;
- `conflicts_rejected`;
- остальные NX5 buffer/interpolation counters.

Presenter публикует `last_apply_error_code` и `interpolation_failures`.
Необработанная ошибка также выводится через `push_warning`, поэтому результат
не исчезает даже в старом caller loop, который не использует return value.

## Сохранённые гарантии

- remote presenter не имеет input authority;
- локальный owner остаётся на NX4 prediction path;
- смена ownership/authority epoch или transport session очищает timeline;
- смена session без роста epoch отклоняется;
- out-of-order insertion и bounded pruning сохранены;
- yaw интерполируется кратчайшим путём через `-PI/PI`;
- teleport и excessive implied speed не интерполируются;
- после 100 мс extrapolation удерживается последняя authoritative позиция.

## Regression fixes

- восстановлены 13 assertions `transport-bound operation identity`;
- M3 test ожидает фактический статус `accepted`;
- M4 использует checksum-valid canonical Item Graph fixture;
- runners не изменяют `HOME`/`USERPROFILE` и восстанавливают временное окружение.

## Проверка

Авторская изолированная проверка ядра:

```text
NX5 contracts:     6104 assertions, PASS
NX5 integration:     49 assertions, PASS
```

Полная приёмка выполняется на текущем рабочем дереве ветки:

```powershell
.\RUN_NX5_REMOTE_SNAPSHOT_INTERPOLATION_TESTS.ps1 `
  -GodotPath "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe" `
  -IncludeGraphicalProcess `
  -IncludeAcceptedRegression
```
