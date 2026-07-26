# v15.1 — проверка бесшовного streaming

## Автоматическая проверка

```powershell
.\RUN_TERRAIN_STREAMING_TEST.ps1
```

Ожидается:

```text
Terrain streaming contract tests: PASS
```

## Безопасный тест K

1. Встать рядом с маяком.
2. Нажать `K`.
3. Дождаться результата.
4. Проверить, что поверхность и позиция персонажа визуально не изменились.
5. В логе должно быть событие `terrain_stream_test_staged` с
   `surface_swapped=false`.

## Проверка неподвижного состояния

1. Не двигать персонажа две минуты.
2. HUD должен показывать `ACTIVE`, без постоянно меняющихся target cell.
3. В `terrain_performance.jsonl` не должны непрерывно появляться
   `terrain_job_started`.

## Проверка движения

1. Включить Jetpack через `J`.
2. Пролететь `3–5 км`, несколько раз меняя направление.
3. Допустимы небольшие просадки FPS, но не остановка около `0.3–1 с`.
4. Вернуться к маякам и остановиться.
5. Streaming должен стабилизироваться.

## Сбор диагностики

```powershell
.\ANALYZE_TERRAIN_LOG.ps1
.\EXPORT_TERRAIN_DIAGNOSTICS.ps1
```

Особенно важны:

- максимум `collision_tile`;
- длиннейшие кадры;
- количество `terrain_surface_swapped`;
- `prediction_skip_counts`;
- события `terrain_actor_surface_reconciled`.
