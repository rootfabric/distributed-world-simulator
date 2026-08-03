# NX5 — Remote Snapshot Interpolation

## Назначение

NX4 отвечает только за локально управляемого игрока: немедленное prediction, authoritative reconciliation и smoothing коррекций. NX5 добавляет отдельный presentation-путь для удалённых игроков. Сервер и canonical replica остаются источником истины; удалённый `Node3D` никогда не получает input authority и не записывает состояние обратно в симуляцию.

## Поток данных

```text
validated PlayerStateSnapshot
  -> запись remote player по server_tick
  -> bounded timeline конкретного logical_player_id
  -> render_tick = estimated_server_tick - 6 ticks
  -> interpolation / bounded extrapolation / hold
  -> RemotePlayerPresenter transform, yaw, flashlight
```

Outer snapshot clock читается из уже существующего `m3_multiplayer_client_runtime.get_snapshot()`. Поэтому canonical snapshot не расширяется presentation-полями, protocol hash NX4 fix1 не меняется и старые серверы/клиенты не получают новый wire DTO.

## Основные параметры

- authoritative tick: 60 Гц;
- ожидаемая публикация snapshot: 20 Гц;
- interpolation delay: 6 ticks / 100 мс;
- extrapolation horizon: максимум 6 ticks / 100 мс;
- timeline: максимум 32 snapshot на удалённого игрока;
- teleport fence: 8 м;
- implied-speed fence: 48 м/с.

## Политики timeline

1. Записи сортируются по `server_tick`; допустима ограниченная перестановка пакетов.
2. Точное повторение того же player state на том же tick подавляется. Новый outer `snapshot_revision`, вызванный, например, Item Graph-событием, сохраняется без ложного конфликта.
3. Изменённое состояние на уже занятом tick отклоняется как конфликт.
4. Пакет старше уже заполненного bounded window отклоняется и не вызывает churn.
5. Смена `transport_session_id` без роста ownership/authority epoch отклоняется.
6. Рост ownership epoch, authority epoch или корректная смена session очищает старый timeline и немедленно устанавливает новую baseline.

## Отрисовка

Между соседними snapshot позиция и velocity интерполируются линейно. `orientation_yaw` проходит кратчайшим путём через границу `-PI/PI`. Дискретные presentation-флаги переключаются на половине интервала.

Если render clock вышел за последний snapshot, позиция продолжается по последней authoritative velocity не более 100 мс. После горизонта presenter удерживает последнюю authoritative позицию и не накапливает бесконечный drift.

Teleport, чрезмерная implied speed и epoch discontinuity не интерполируются: до authoritative tick удерживается предыдущая точка, на границе применяется snap.

## Изоляция NX4

- локальный player исключён существующим `playground_runtime` до вызова remote presenter;
- `ClientPredictionReconciler` не изменён;
- movement input, ACK pruning и owner smoothing не изменены;
- canonical replica, persistence и серверная fixed-tick simulation не изменены;
- wire schema и protocol hash остаются NX4 fix1.

## Тесты

`test_nx5_remote_snapshot_interpolation.gd` проверяет конфигурацию, ordering, duplicate/conflict, yaw wrap, interpolation, extrapolation, hold, teleport, reconnect, bounded memory и детерминированные loss/jitter профили при 30/60/144 FPS.

`test_nx5_remote_snapshot_interpolation_integration.gd` проверяет реальный `RemotePlayerPresenter`, чтение outer snapshot clock из client runtime, отсутствие snap при обычном обновлении, bounded extrapolation, reconnect reset и независимость нескольких remote players.

Обязательная независимая приёмка дополнительно повторяет NX4 focused, Network N0–M4, M7/M3/N1 и полный world regression.
