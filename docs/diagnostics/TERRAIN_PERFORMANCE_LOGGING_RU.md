# Диагностика производительности рельефа v15

## Файлы

Основной специализированный лог:

```text
user://logs/terrain_performance.jsonl
```

Общий лог приложения также получает те же события:

```text
user://logs/lunar_simulation.jsonl
```

На Windows `user://` обычно соответствует:

```text
%APPDATA%\Godot\app_userdata\Real Scale Procedural Moon\
```

По `F9` создаётся диагностический JSON со snapshot очереди и последними
результатами:

```text
user://diagnostics/diagnostic_*.json
```

Скрипт:

```powershell
.\EXPORT_TERRAIN_DIAGNOSTICS.ps1
```

собирает логи, diagnostics и текущий конфиг в архив
`lunar-terrain-diagnostics-<timestamp>.zip` рядом с проектом.

Быстрая локальная сводка:

```powershell
.\ANALYZE_TERRAIN_LOG.ps1
```

Она выводит average/P95/max для background и commit stages, а также список
самых длинных кадров. Рядом с проектом создаётся текстовый отчёт.

## Главные события

### `synchronous_surface_rebuild`

Возникает на старте, spawn или телепорте. Содержит:

- `craters_and_anchor_ms`;
- `clear_old_nodes_ms`;
- `local_mesh_total_ms`;
- `medium_annulus_total_ms`;
- `medium_full_total_ms`;
- `rocks_total_ms`;
- `collision_total_ms`;
- `total_sync_rebuild_ms`.

Это исходная точка сравнения старого синхронного пути.

### `terrain_job_started`

Фоновый запрос принят. Полезные поля:

- `request_id`;
- `cell_id`;
- `reason`;
- `include_collision`;
- `include_medium`;
- скорость и prediction distance в `extra`.

### `terrain_job_cpu_ready`

Фоновый расчёт завершён. `background_timings_ms` разделён на:

```text
crater_catalogs_and_anchor_ms
local_sampling_and_indices_ms
local_normals_ms
local_colors_ms
local_tangents_ms
rock_descriptors_ms
total_background_ms
```

При REGIONAL rebuild добавляются соответствующие
`medium_annulus_*` и `medium_full_*`.

### `terrain_commit_stage`

Один атомарный main-thread этап. Возможные `stage`:

```text
local_mesh_resource
medium_annulus_resource
medium_full_resource
collision_shape
rock_layer_0 ... rock_layer_5
atomic_swap
```

Поля:

- `duration_ms`;
- `budget_ms`;
- `over_budget`.

### `terrain_surface_swapped`

Полная сводка одного перехода:

- все background timings;
- все commit stage timings;
- `request_to_swap_ms`;
- `commit_cpu_sum_ms`;
- `max_commit_stage_ms`;
- `max_observed_frame_ms`;
- количество вершин, треугольников и камней.

### `long_frame_detected`

Кадр превысил порог, по умолчанию 50 мс. Событие содержит состояние manager и
активную commit stage. Это позволяет сопоставить визуальный фриз с конкретной
операцией.

### `terrain_streaming_summary`

Периодический snapshot состояния очереди, по умолчанию каждые 10 секунд.

## Как определить причину задержки

| Что велико | Вероятная причина | Следующий шаг |
|---|---|---|
| `local_sampling_and_indices_ms` | height/crater sampling | оптимизировать sampler, spatial crater index |
| `local_normals_ms` | CPU normal accumulation | parallel groups или нормали из height derivatives |
| `local_tangents_ms` | tangent calculation | shader/triplanar material или parallel calculation |
| `rock_descriptors_ms` | перебор cell и surface normal для камней | density tiles, deferred decoration |
| `local_mesh_resource` | создание ArrayMesh | split mesh на clipmap rings |
| `collision_shape` | `create_trimesh_shape()` | tiled collision, ближайшие tiles сначала |
| `rock_layer_N` | создание большого MultiMesh | chunked MultiMesh или меньший batch |
| `atomic_swap` | SceneTree/root update | deferred retirement и меньшие группы узлов |
| background мал, кадр длинный без commit | сторонний gameplay/render stall | анализ общего profiler и лога |

## Настройки

Файл:

```text
config/terrain_streaming.json
```

Для диагностики сначала не меняйте параметры. После первого набора логов можно
экспериментировать с:

- `stream_cell_size_m`;
- `prediction_seconds`;
- `max_prediction_distance_m`;
- `long_frame_threshold_ms`;
- `main_thread_commit_budget_ms`.

## Что прислать для анализа

После теста достаточно архива, созданного:

```powershell
.\EXPORT_TERRAIN_DIAGNOSTICS.ps1
```

Перед экспортом полезно нажать `F9` сразу после заметного зависания.
