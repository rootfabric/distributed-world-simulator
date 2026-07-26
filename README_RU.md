# Real Scale Procedural Moon v15.2 + Earth Architecture Test

Проект для Godot 4.7.1, собранного с `precision=double`.

## Экспериментальная Земля

В проект добавлена независимая процедурная Земля реального радиуса 6 371 км. Луна остаётся на исходной логике v15.2. Центры тел находятся на реальном среднем расстоянии 384 400 км в едином double-precision simulation-space.

Нажмите `P`, чтобы включить общий спектатор пространства. Земля и Луна одновременно остаются в одной абсолютной системе координат. Каждый генератор выполняет собственный body-local floating origin только перед рендерингом. Земля создаётся лениво при первом включении режима.

Реализованы отдельные правила:

- материки, океаническое дно, равнины и горные хребты;
- русла рек, озёрные чаши, моря и береговые зоны без симуляции жидкости;
- температура, влажность, полярность и засушливость;
- лес, травяные равнины, каменная пустыня, тундра, снег и скалы;
- четыре формы деревьев, три типа травы и три варианта камней через `MultiMesh`;
- запреты посадки на воде, снегу, резких и слишком каменистых склонах;
- LOD с объёмными деревьями, billboard-деревьями и полным удалением травы вдали;
- проверка конфликтов `requires/writes` между procedural rules.

Управление в едином пространстве:

```text
P          включить/выключить общий спектатор Земля–Луна
1          лес Земли
2          равнины Земли
3          пустыня Земли
4          тундра Земли
5          снежные горы Земли
6          перейти к поверхности Луны
7          перейти к поверхности Земли
G          направить камеру на другое небесное тело
F4         final / biome / elevation / ecology
F9         сохранить planetary diagnostic JSON
Y          перечитать правила из JSON
WASD/QE    свободный полёт в абсолютном пространстве
Shift      ускорение
колесо     изменить скорость вплоть до межпланетной
H          выровнять горизонт относительно ближайшего тела
```

Автоматический архитектурный тест:

```powershell
.\RUN_EARTH_ARCHITECTURE_TEST.ps1
```

Подробности:

- `docs/architecture/PROCEDURAL_EARTH_RULE_PIPELINE_RU.md`;
- `docs/plans/EARTH_MOON_ARCHITECTURE_TEST_RU.md`;
- `docs/architecture/SHARED_SPACE_AND_PARTITIONING_RU.md`.

## Исходная Луна v15.2

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
.\ANALYZE_EARTH_TERRAIN_LOG.ps1
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


## Атмосферный слой Земли

В проект добавлен отдельный модуль атмосферы, не связанный с terrain/biome pipeline:

- голубое процедурное небо меняет насыщенность по высоте;
- эффект плавно затухает от поверхности до границы 100 км;
- на глобальном LOD яркая атмосферная оболочка не рисуется;
- облака находятся на высоте около 4 км и подключаются как atmosphere plugin;
- облака создаются одним MultiMesh и выключаются выше 32 км;
- Луна не получает атмосферу, потому что у неё отсутствует `atmosphere_config`;
- новые явления добавляются плагинами без изменения генератора поверхности.

Конфигурации:

```text
config/atmospheres/earth.json
config/atmosphere_plugins/earth_low_clouds.json
```

Архитектура: `docs/architecture/ATMOSPHERE_LAYER_V1_RU.md`.

Проверка:

```powershell
.\RUN_ATMOSPHERE_ARCHITECTURE_TEST.ps1
```
