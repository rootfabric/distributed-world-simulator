# Real Scale Procedural Moon v15

Проект для Godot 4.7.1, собранного с `precision=double`.

## Главное в v15

- CPU generation LOCAL/REGIONAL выполняется через `WorkerThreadPool`;
- старая поверхность остаётся активной до готовности новой;
- предиктивная подгрузка использует скорость персонажа;
- `ArrayMesh`, collision и шесть rock layers подключаются по стадиям;
- отдельный JSONL-лог времени каждой стадии;
- runtime streaming test по `K`;
- persistent world, Survey Beacons и pluggable controllers сохранены.

## Управление

```text
C          первое/третье лицо
J          Lunar EVA/Jetpack
K          тест фоновой генерации и staged commit
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

## Performance logs

```text
user://logs/terrain_performance.jsonl
user://logs/lunar_simulation.jsonl
user://diagnostics/diagnostic_*.json
```

На Windows: `%APPDATA%\Godot\app_userdata\Real Scale Procedural Moon\`.

Собрать диагностический архив:

```powershell
.\ANALYZE_TERRAIN_LOG.ps1
.\EXPORT_TERRAIN_DIAGNOSTICS.ps1
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
