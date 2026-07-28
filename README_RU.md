# Planetary World v16.4.2-network-transport-boundary — Foundation N0 и Inventory UI объединены

Checkpoint объединяет принятый `v16.4.0-foundation-n0-fix1` с веткой
`feature/ui-i0-inventory-shell` (`UI-I0`–`UI-I2`). В основной линии теперь
одновременно находятся server-safe foundation, строгие N0 contracts и новый
компонентный интерфейс инвентаря.

Проект рассчитан на Godot 4.7.1 с `precision=double`.

## Текущий checkpoint

```text
v16.4.2-network-transport-boundary
```

Build ID:

```text
n1-transport-lifecycle-boundary
```

Интеграция сохраняет главный инвариант:

```text
canonical simulation ≠ presentation ≠ transport
```

Что вошло:

- component inventory shell, ViewModel и CommandFacade;
- contextual external containers, drag/Shift-click/context actions;
- search, filters, view-only sort, inspector и bounded cell pool;
- сохранение UI preferences отдельно от Item Graph;
- совместимость UI drop-one/drop-stack с canonical `WorldEntityAggregate`;
- полный Foundation/N0 authority, revision, tick и kernel-port fencing;
- 55 обязательных Godot regression tests.

При пробном merge был найден реальный API-разрыв: UI-I1 вызывал старый
`drop_item_stack()`, отсутствующий после Foundation Part 3. Контроллер снова
публикует `drop_item`, `drop_item_stack` и `drop_item_quantity`, но все три пути
используют текущий `ItemTransferService`, WORLD relation и aggregate
reconciliation — прямой presentation mutation не возвращён.

Основные документы:

- `docs/checkpoints/2026-07-28_V16_4_1_FOUNDATION_INVENTORY_MERGE_RU.md`;
- `docs/checkpoints/2026-07-28_V16_4_0_FOUNDATION_N0_FIX1_RU.md`;
- `docs/plans/INVENTORY_UI_REDESIGN_PLAN_RU.md`;
- `docs/plans/NEXT_ITERATIONS_RU.md`;
- `docs/network/SEAMLESS_WORLD_ROADMAP_RU.md`.

Следующий основной этап:

```text
N1 — один authoritative simulation-server
   + отдельный bot-client
   + ENet transport adapter
   + initial snapshot
   + одна remote item command
   + checksum equality
```

`UI-I3` с batch/multi-select отложен до появления реального authoritative
command path на N1/N2.

## Установка и отладка

- Монтажное гнездо маяка является предметом. Перенесите его в hotbar, выберите клавишей `1–0`, наведитесь на поверхность и нажмите `E`.
- Установленное гнездо сохраняется как WORLD item и предоставляет attachment socket для маяка. Снимать само основание пока нельзя.
- `F10` открывает правую системную панель с переходами между мирами и выдачей каждого предмета в количестве `×1` или `×100`.
- `F` включает двухслойный круговой свет: широкий terrain fill радиусом 1000 м и отдельный ближний fill.
- В консоли `Tab` дополняет команды и аргументы, а `↑/↓` восстанавливают историю с фокусом и курсором в конце строки.

## Управление стаками

- ЛКМ-перетаскивание переносит весь стак.
- ПКМ + перетаскивание сначала выбирает целевой слот или контейнер, после отпускания кнопки появляется выбор количества.
- В `SLOTS`-контейнере перенос на занятую совместимую ячейку объединяет стаки до `max_stack`. Остаток остаётся в исходной ячейке.
- Перенос на пустую фиксированную ячейку не объединяет стак с соседними ячейками.
- В `BULK`-контейнере без фиксированных ячеек совместимые стаки объединяются автоматически; остаток становится отдельной записью только после заполнения существующих стаков.
- Рюкзак игрока и универсальный ящик работают в режиме `BULK`; hotbar и батарейный шкаф — в режиме `SLOTS`. Правая секция внешнего контейнера скрыта при обычном `Tab` и появляется только после `E` на реальном контейнере.


## Быстрый старт

Нажмите `~` и используйте команды:

```text
help
world.list
world.load moon
world.load earth
world.load earth_moon
world.load item_lab
world.load playground
world.back
test.list
test.run all
runtime.descriptor
runtime.snapshot
input.bindings
display.fullscreen.toggle
display.resolution.cycle
```

Основные проверяемые горячие клавиши текущего `SimulatorApp`:

```text
F2         вернуть игрока к позиции спектатора
F3         игрок / shared-space spectator
F4         визуализация LOD
F5         первое/третье лицо
J          humanoid / jetpack
Tab        открыть/закрыть инвентарь
1–9, 0     выбрать быстрый слот 1–10
G          выбросить один предмет выбранного stack
E          подобрать / открыть / установить гнездо или маяк
F          двухслойный круговой фонарь (широкий радиус 1000 м)
F10        системное меню: миры и выдача предметов
Q/E        крен в режиме свободного полёта
```

Лаборатория предметов не привязана к `F5` и открывается только командой
`world.load item_lab`.

Безусловно глобальными остаются `~` и `F1`. `Tab`, `E`, `G` и `1–0` маршрутизируются в предметные команды активного runtime. Клавиши `F2`–`F5`, `J`
и действие `E` маршрутизируются через команды активного runtime и выполняются
только там, где соответствующая команда зарегистрирована. Навигация между
мирами, ввод и параметры окна принадлежат `SimulatorApp`;
специализированные функции миров перенесены в команды активного runtime. Поэтому
новые карты не создают собственный несовместимый набор клавиш или меню.

Обязательная подготовка репозитория и регрессия:

```powershell
.\PREPARE_R0_REPOSITORY.ps1
.\RUN_WORLD_REGRESSION_TESTS.ps1
.\RUN_FOUNDATION_LIFECYCLE_TESTS.ps1
.\RUN_FOUNDATION_WORLD_AGGREGATE_TESTS.ps1
.\RUN_NETWORK_CONTRACT_TESTS.ps1
```

Runner сначала выполняет headless editor import/parse, затем запускает все
`test_*.gd`, проверяет полноту списка и сохраняет JSON-отчёт в
`artifacts/test-results/world-regression-summary.json`. Чекпоинт R0 описан в
`docs/checkpoints/2026-07-26_R0_STABILIZATION_CHECKPOINT_RU.md`.

Чекпоинт R1.1 описан в
`docs/checkpoints/2026-07-27_R1_1_ITEM_IDENTITY_STATE_STORE_RU.md`. Новые
предметы используют глобальные UUID, Item Registry имеет versioned JSON
snapshot, а полный SpatialRef сохраняется через ItemStateStore.

Чекпоинт R1.2 описан в
`docs/checkpoints/2026-07-27_R1_2_OPERATION_LEDGER_RU.md`. Команды предметного
aggregate используют expected revision, канонический SHA-256 payload fingerprint
и persistent bounded operation ledger. Точный replay безопасен, другой payload с
тем же operation ID отклоняется.

Чекпоинт R1.3 описан в
`docs/checkpoints/2026-07-27_R1_3_GRAVITY_AND_PHYSICAL_MASS_RU.md`. Общий
`GravityField` суммирует гравитационные колодцы Солнца, Земли и Луны, учитывает
систему отсчёта и используется физическими предметами. Масса WORLD-контейнера
включает рекурсивную массу содержимого.

Чекпоинт R1.4/R2 описан в
`docs/checkpoints/2026-07-27_R1_4_R2_ITEM_GRAPH_AND_PLAYER_INVENTORY_RU.md`.
Полный item graph сохраняется атомарно, а `world.load playground` предоставляет
рюкзак, hotbar, drag-and-drop UI, внешний ящик, battery-only rack и монтаж маяка.

Архитектура: `docs/architecture/MULTI_WORLD_SIMULATOR_CORE_RU.md`.
Приёмка: `docs/plans/V15_5_ACCEPTANCE_TESTS_RU.md`.

## Предметы и инвентарь

`world.load playground` открывает ручной R2-сценарий. В рюкзаке находятся маяки
и аккумуляторы; справа стоит ящик с дополнительными маяками, слева — контейнер
с battery-only slots, впереди — монтажная плита. `Tab` показывает предметы
иконками, перенос выполняется drag-and-drop. Предмет в контейнере не имеет
физического тела; после выброса в WORLD оно восстанавливается вместе с массой и
гравитацией.

Лаборатория `world.load item_lab` остаётся низкоуровневой диагностикой relation
переходов. Команда `world.back` возвращает в предыдущий мир.

Проверка:

```powershell
.\RUN_UNIFIED_ARCHITECTURE_TEST.ps1
.\RUN_ITEM_SYSTEM_TESTS.ps1
```

## Земля и единое пространство

В проект добавлена независимая процедурная Земля реального радиуса 6 371 км.
`world.load earth` создаёт отдельный `EarthApp`, в системе которого физически
зарегистрирована только Земля. `world.load earth_moon` использует `PlanetaryApp`
и создаёт оба тела на реальном среднем расстоянии 384 400 км в едином
double-precision simulation-space. Луна остаётся на исходной логике v15.2.

В мире `earth_moon` общий режим запускается сразу. Для управления используйте
консольные команды, а не отдельную ветку клавиш карты:

```text
space.mode.toggle
space.teleport.body earth
space.teleport.body moon
space.focus.other_body
earth.teleport.biome forest
earth.teleport.biome grassland
earth.teleport.biome desert
earth.teleport.biome tundra
earth.teleport.biome alpine_snow
earth.debug.cycle
earth.rules.reload
diagnostics.save
```

Свободный полёт использует общие actions ядра: `WASD`, `Space/Ctrl`, `Shift`,
`Q/E` для крена и `H` для выравнивания. Полный список минимальных bindings
показывает команда `input.bindings`. Земля и Луна находятся в одном иерархическом `FrameGraph`. Поверхностные
объекты хранят body-fixed координаты, орбиты и вращение вычисляются аналитически
по единым часам, а каждый генератор выполняет observer-relative floating origin
только перед рендерингом.

`GravityField` вычисляет абсолютное поле в `sol.barycentric` и локальное
body-relative поле в системах Земли и Луны. Снаружи тел ускорение уменьшается по
закону обратных квадратов. `GravityTrajectoryIntegrator` предоставляет
velocity-Verlet propagation для будущих спутников и выброшенных объектов.
Контракт: `docs/contracts/GRAVITY_FIELD_V1_RU.md`.

Автоматический архитектурный тест:

```powershell
.\RUN_EARTH_ARCHITECTURE_TEST.ps1
```

Подробности:

- `docs/architecture/PROCEDURAL_EARTH_RULE_PIPELINE_RU.md`;
- `docs/plans/EARTH_MOON_ARCHITECTURE_TEST_RU.md`;
- `docs/architecture/SHARED_SPACE_AND_PARTITIONING_RU.md`.


## Координаты и время v15.5.1

```text
time.status
time.scale 3600
time.pause
time.step 60
time.resume
space.frame.current
space.frame.set body/earth/fixed
space.frame.set body/earth/inertial
space.frame.set sol.barycentric
```

Каноническое положение хранится в `SpatialRef`, server partition — в
`PartitionAddress`, а Godot transform остаётся локальным представлением возле
наблюдателя. Поля `universe_id/instance_id` отделяют постоянную Вселенную от
тестовых и параллельных simulation instances.

Поверхностная адресация использует общий `CubeSphereGrid`, настраиваемый отдельно
для Земли и Луны. Плотность сетки и правила адресации имеют явную revision,
которая входит в chunk ID и путь persistence:

```text
.../partition/cube_sphere/revision/1/zone/...
partitions/.../cube_sphere_r1/...
```

Проверка:

```powershell
.\RUN_COORDINATE_FOUNDATION_TESTS.ps1
```

Архитектура: `docs/architecture/REFERENCE_FRAMES_AND_DISTRIBUTED_SPACE_RU.md`.

## Луна

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

## Legacy-управление автономного LunarApp

При запуске через основной `SimulatorApp` используйте `~`, `help` и команды
общего реестра. Клавиши ниже сохранены только для автономного запуска старых
runtime-сцен и не являются новым публичным контрактом ядра.

```text
C          первое/третье лицо
E          взаимодействовать с маяком в центре экрана
J          Lunar EVA/Jetpack
K          безопасный тест terrain streaming
M          включить/выключить дальние метки маяков
P          единое пространство Земля–Луна
F5         первое/третье лицо
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
