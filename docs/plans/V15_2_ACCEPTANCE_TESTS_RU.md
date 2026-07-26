# v15.2 — приёмочные тесты

## Проверка версии

В начале `lunar_simulation.jsonl` должно быть:

```json
{"event":"startup","data":{"project_version":"15.2","build_id":"recent-surface-cache-and-landmarks"}}
```

## Тест возврата к базе

1. Запустить проект возле ранее поставленных маяков.
2. Дождаться LOCAL детализации.
3. Улететь на 2–5 км, пересечь несколько streaming cells.
4. Вернуться по дальней метке маяка.
5. Примерно в пределах 1,8 км от pinned-cell должен появиться `terrain_pinned_cache_return_triggered`.
6. LOCAL возле базы должен включиться через cache hit без 5–7 секунд повторной генерации.
7. В логе найти `terrain_surface_cache_hit`.
8. Снова полететь от маяка: pinned-cell не должна немедленно переключаться обратно.

## Тест pinned cell

1. Поставить маяк в текущей cell.
2. Улететь так, чтобы посетить более восьми cells.
3. Вернуться.
4. Cell базы должна сохраниться в cache snapshot как pinned либо восстановиться cache hit.

## Тест меток

1. Нажать `M` и убедиться, что метки отключаются.
2. Нажать `M` повторно.
3. Улететь на несколько километров.
4. Над маяком должна оставаться надпись `МАЯК` и расстояние.
5. Перезапустить проект: метка должна восстановиться из `landmarks.json`.

## Диагностика

После теста нажать `F9` и экспортировать архив. Полезные события:

```text
terrain_surface_cached
terrain_surface_cache_hit
terrain_surface_cache_miss
terrain_surface_cache_evicted
terrain_surface_cache_pins_updated
landmark_index_loaded
landmark_index_saved
landmark_markers_toggled
```
