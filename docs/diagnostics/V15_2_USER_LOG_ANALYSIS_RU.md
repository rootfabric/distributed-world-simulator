# Анализ лога `godot2026-07-26T02.59.23.zip`

## Важное замечание о версии

Переданный лог относится к старой сборке v15.0, а не к v15.1.

Признаки:

- в событии `startup` отсутствуют `project_version` и `build_id`;
- `streaming_manager_started` не содержит `collision_triangles_per_tile`, `minimum_predictive_speed_mps`, `recent_surface_cache_capacity`;
- тест `K` завершился событием `terrain_surface_swapped`, то есть реально заменил поверхность;
- в логе нет стадий `collision_tile_000...` и события `terrain_stream_test_staged`.

Начиная с v15.2 версия и build ID записываются в первый startup-event, чтобы нельзя было перепутать логи разных сборок.

## Повторная генерация посещённых участков

В логе было 17 terrain jobs и 16 полноценных swap. Одни и те же cell строились повторно:

```text
terrain/-3216/2481 — 6 запусков генерации
terrain/-3217/2481 — 3 запуска
terrain/-3216/2482 — 3 запуска
terrain/-3217/2483 — 3 запуска
```

Это подтверждает наблюдение: после возврата к маякам LOCAL-слой не восстанавливался из памяти, а полностью рассчитывался заново.

## Причина задержки при возврате

До v15.2 при каждом уходе старые ресурсы уничтожались:

- ArrayMesh LOCAL;
- collision shape;
- MultiMesh слоёв камней;
- локальные каталоги кратеров.

После возвращения система снова выполняла 5–7 секунд фонового CPU build и только затем подключала максимальную детализацию.

## Исправление v15.2

Добавлен LRU-кэш готовых ресурсов поверхности:

- 8 последних обычных streaming cells;
- до 8 дополнительных pinned cells с маяками;
- в кэше остаются готовые ArrayMesh, collision Shape3D, MultiMesh и generation state;
- при cache hit не запускаются sampling, normals, tangents, rocks и создание collision shape;
- готовые ресурсы повторно подключаются к сцене.

Новые события:

```text
terrain_surface_cached
terrain_surface_cache_hit
terrain_surface_cache_miss
terrain_surface_cache_evicted
terrain_surface_cache_pins_updated
terrain_job_preempted_by_cache
terrain_cached_surface_activated
```

В runtime summary отображается:

```text
cache=<размер> (<hits>/<misses>)
```

## Упреждающий возврат к маяку

Одного LRU-кэша недостаточно, если система ждёт пересечения точного центра Terrain Streaming Cell. Поэтому pinned-cell с маяком проверяется отдельно. При движении к ней и расстоянии до `1800 м` выполняется ранний cache lookup.

Защита от колебаний:

- ранний возврат срабатывает при движении в сторону маяка;
- при удалении от маяка запрос блокируется счётчиком `pinned_cache_moving_away`;
- в непосредственной близости cell восстанавливается независимо от малой скорости.

Ожидаемая последовательность нового лога:

```text
terrain_pinned_cache_return_triggered
terrain_surface_cache_hit
terrain_cached_surface_activated
```
