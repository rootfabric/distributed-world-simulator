# Real Scale Procedural Moon v15.2

Проект для Godot 4.7.1, собранного с `precision=double`.

## Главное в v15.2

- готовые LOCAL-поверхности недавно посещённых Terrain Streaming Cell удерживаются в RAM;
- кэш хранит `ArrayMesh`, готовые collision `Shape3D`, `MultiMesh` камней и состояние генератора;
- обычная LRU-ёмкость — 8 cells;
- до 8 cells с постоянными маяками получают дополнительный статус `pinned`;
- при возвращении к маяку pinned-cell может быть активирована заранее, примерно за 1,8 км;
- повторная генерация при cache hit не запускается;
- маяки имеют дальние навигационные метки с расстоянием;
- клавиша `M` включает и выключает метки;
- в логах явно записываются `project_version=15.2` и `build_id`.

Процедурная поверхность по-прежнему не является частью постоянного сохранения. Кэш можно потерять без изменения мира: после перезапуска участок будет рассчитан заново.

## Асинхронный streaming

- CPU generation работает через `WorkerThreadPool`;
- старая поверхность остаётся активной до готовности новой;
- collision разделена на плитки примерно по 2048 треугольников;
- предиктивная подгрузка имеет гистерезис;
- `K` выполняет безопасный staged-тест без замены активного участка;
- тайминги пишутся в отдельный JSONL-лог.

## Управление

```text
C          первое/третье лицо
J          Lunar EVA/Jetpack
K          безопасный тест terrain streaming
M          включить/выключить дальние метки маяков
F12        тест controller/camera
B          поставить Survey Beacon
Delete     удалить ближайший маяк
Ctrl+S     сохранить постоянный слой
F10        тест persistence
F7         тест Entity Registry
F9         сохранить диагностический JSON
F1 / Esc   открыть или закрыть меню
Tab        захватить или освободить мышь
F3         персонаж / спектатор
F6 / R     случайная точка Луны
F8         сменить разрешение
F11        полный экран / окно
```

## Логи

```text
user://logs/terrain_performance.jsonl
user://logs/lunar_simulation.jsonl
user://diagnostics/diagnostic_*.json
```

На Windows:

```text
%APPDATA%\Godot\app_userdata\Real Scale Procedural Moon\
```

Сводка и диагностический архив:

```powershell
.\ANALYZE_TERRAIN_LOG.ps1
.\EXPORT_TERRAIN_DIAGNOSTICS.ps1
```

Для проверки cache hit ищите события:

```text
terrain_surface_cached
terrain_surface_cache_hit
terrain_pinned_cache_return_triggered
terrain_surface_cache_evicted
```

## Тесты

```powershell
.\RUN_ARCHITECTURE_TESTS.ps1
.\RUN_ENTITY_INTEGRATION_TEST.ps1
.\RUN_PERSISTENCE_TEST.ps1
.\RUN_CONTROLLER_TEST.ps1
.\RUN_TERRAIN_STREAMING_TEST.ps1
```

Подробная документация находится в `docs/README_RU.md`.
