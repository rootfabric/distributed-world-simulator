# Аудит текущего покрытия тестами

**Дата исследования:** 27 июля 2026 года
**База аудита:** полный архив `lunar-world-double-godot(2).zip`
**Уточнение:** R0 и R1.1 добавляют тесты поверх этой базы; перед реализацией
каждого этапа аудит нужно пересчитывать.

## 1. Количественный снимок

Для базового полного архива:

| Метрика | Значение |
|---|---:|
| Production GDScript | 79 файлов |
| Строки production GDScript | около 23 981 |
| Файлы `test_*.gd` | 23 |
| Все GDScript в `tests` | 25 |
| Строки тестового GDScript | около 3600 |
| `tests/core` | 4 теста |
| `tests/integration` | 7 тестов |
| `tests/items` | 2 теста |
| `tests/runtime` | 1 тест |
| `tests/unit` | 9 тестов |

После R0/R1.1 ожидается 26 обязательных тестов в regression manifest, включая
hotkey contract, world switch during generation и item identity/state store.

## 2. Существующие тесты по областям

### Core

- `test_command_registry.gd` — базовая регистрация и выполнение команд.
- `test_controller_profiles.gd` — загрузка профилей контроллеров.
- `test_hotkey_contract.gd` — зафиксированные клавиши и действия.
- `test_world_catalog.gd` — основной успешный каталог миров.

### Unit

- `test_simulation_clock.gd`;
- `test_reference_frame_graph.gd`;
- `test_celestial_motion.gd`;
- `test_partition_address_v2.gd`;
- `test_cube_sphere_grid.gd`;
- `test_partition_foundation.gd`;
- `test_atmosphere_layer.gd`;
- `test_earth_generation_pipeline.gd`;
- `test_jetpack_controller.gd`.

### Integration

- `test_persistence_roundtrip.gd`;
- `test_entity_registry_migration.gd`;
- `test_first_person_interaction.gd`;
- `test_terrain_streaming_contract.gd`;
- `test_unified_planetary_runtime.gd`;
- `test_unified_runtime_boot.gd`;
- controller profile integration.

### Items

- `test_item_domain.gd`;
- `test_item_lab_integration.gd`;
- после R1.1: `test_item_identity_and_state_store.gd`.

### Runtime

- `test_world_boot_matrix.gd`;
- после R0: `test_world_switch_during_generation.gd`.

## 3. Тепловая карта покрытия

| Область | Текущее состояние | Основной пробел |
|---|---|---|
| Item Domain | хорошее | полная матрица ошибок, signals, fuzz sequences |
| Item identity/state | добавлено в R1.1 | operation ledger и полный graph persistence позже |
| Spatial/partition | хорошее основание | отдельные invalid/fuzz tests SpatialRef и providers |
| Entity Registry | хорошая миграция | lifecycle, delete/evict, queries и signals |
| Lunar persistence | основной round-trip | corruption, atomicity, journal recovery |
| World boot | хорошее | failure rollback и повторные циклы |
| Terrain streaming | слабое | worker, state machine, payload, commit, collision, cache |
| Physics | очень слабое | реальные physics frames, контакты и движение |
| Input/controllers | слабое | настоящий Input pipeline и CharacterBody movement |
| Interaction | частичное | настоящий raycast и collision masks |
| Earth rules | частичное | правила по отдельности, mesh и vegetation |
| Atmosphere | частичное | plugin lifecycle, boundaries и cleanup |
| UI/console | почти нет | command wiring, history, completion, state |
| Diagnostics/logger | почти нет | file rotation, JSON, failure paths |
| Stress/performance | нет системного набора | leaks, bounded resources, long runs |
| Visual/export | нет | renderer smoke и exported build smoke |

## 4. Критические наблюдения

### 4.1. Terrain contract пока не проверяет terrain pipeline

Текущий integration test в основном проверяет конфигурацию, cell ID, hysteresis
и наличие методов. Он не доказывает:

- что worker действительно создал payload;
- что payload геометрически валиден;
- что commit прошёл все стадии;
- что collision заменился;
- что stale revision была отброшена;
- что cache восстановил поверхность;
- что repeated swap не накапливает узлы.

Это наиболее рискованная зона текущего проекта.

### 4.2. Создание RigidBody ещё не является physics test

Если тест только создаёт `RigidBody3D`, проверяет наличие узла и удаляет его, он
не проверяет:

- gravity;
- движение;
- collision;
- contact signals;
- переход в sleeping;
- сохранение скорости;
- отсутствие проваливания.

Для этого нужны реальные physics frames.

### 4.3. Interaction test обходит raycast

Прямое назначение `current_target` проверяет interaction handler, но не проверяет
камеру, query, mask, исключение собственного RID и поиск interactable parent.

### 4.4. Runtime success-path не покрывает rollback

Boot matrix хорошо проверяет рабочие runtime. Не покрыты runtime, которые:

- не реализуют контракт;
- падают в configure;
- регистрируют конфликтующую команду;
- не очищают owner;
- не завершают worker;
- выбрасывают ошибку в `prepare_for_unload()`.

### 4.5. Async callback в RuntimeTestRegistry требует решения

Текущий registry вызывает callback синхронно и нормализует немедленный результат.
До добавления async-support нельзя считать, что `await` внутри зарегистрированного
runtime test будет корректно ожидаем. Возможные решения:

1. оставить async engine tests отдельными SceneTree scripts;
2. научить registry ожидать coroutine/signal;
3. явно отклонять async callbacks, чтобы не получить ложный PASS.

На первом этапе безопаснее использовать вариант 1.

## 5. Области без прямого поведенческого теста

Особое внимание требуется production-модулям, которые могут быть транзитивно
загружены тестами, но их поведение не вызывается напрямую:

- TerrainStreamingManager и commit pipeline;
- ProceduralMoonTerrain payload generation;
- recent surface cache;
- ProceduralEarthWorld mesh lifecycle;
- EarthPlacementSystem;
- EarthAssetLibrary;
- ControllerHost и реальное movement;
- SpectatorController;
- EarthExplorer frame switching;
- DeveloperConsole;
- Lunar HUD и PlanetaryOverlay;
- LunarLogger;
- atmosphere plugins;
- compatibility wrappers.

Транзитивный preload подтверждает синтаксис и существование пути, но не является
поведенческим покрытием.

## 6. Матрица будущих тестов

### Core и lifecycle

| Будущий тест | Что должен проверить |
|---|---|
| `test_runtime_test_registry.gd` | ошибки, signals, owner cleanup, async policy |
| `test_command_registry_errors.gd` | parser edge cases, aliases, rollback |
| `test_world_catalog_validation.gd` | malformed JSON, duplicates, invalid runtime |
| `test_simulator_world_lifecycle_failures.gd` | abort, rollback, reload after failure |
| `test_world_switch_repetition.gd` | leaks и owner isolation после циклов |

### Items

| Будущий тест | Что должен проверить |
|---|---|
| `test_item_error_matrix.gd` | каждый error code и отсутствие partial mutation |
| `test_item_attachment_service.gd` | sockets, occupied, detach, cycles |
| `test_item_signal_contract.gd` | точное число relation/item/quantity signals |
| `test_item_representation_physics.gd` | WORLD ↔ CONTAINER ↔ ATTACHMENT в реальном engine |
| `test_item_graph_property_sequences.gd` | случайные последовательности с фиксированным seed |

### Terrain

| Будущий тест | Что должен проверить |
|---|---|
| `test_moon_generation_determinism.gd` | seed, finite heights, continuity |
| `test_streaming_payload_geometry.gd` | vertices, indices, normals, collision payload |
| `test_streaming_state_machine.gd` | все state transitions и revision fencing |
| `test_surface_cache_policy.gd` | hit/miss, LRU, pinning и capacity |
| `test_streaming_commit_collision.gd` | staged commit, raycast, actor safety, cleanup |

### Persistence

| Будущий тест | Что должен проверить |
|---|---|
| `test_persistence_corruption.gd` | manifest/chunk/journal corruption |
| `test_persistence_atomic_write.gd` | temp/rename, overwrite, failure recovery |
| `test_landmark_index_rebuild.gd` | rebuild, duplicates, delete/toggle |
| `test_repository_event_contract.gd` | signals и порядок событий |

### Engine behavior

| Будущий тест | Что должен проверить |
|---|---|
| `test_world_interactor_raycast.gd` | настоящий raycast и focus lifecycle |
| `test_flat_humanoid_movement.gd` | input, move, jump, collision |
| `test_planetary_humanoid_movement.gd` | radial gravity и local up |
| `test_jetpack_movement.gd` | camera-relative flight, boost, vertical movement |
| `test_spectator_controller.gd` | mouse look, roll, level horizon |

### Earth, atmosphere, UI

| Будущий тест | Что должен проверить |
|---|---|
| отдельные Earth rule tests | hydrology, climate, biome, surface composition |
| `test_procedural_earth_world.gd` | transforms, gravity, LOD, valid mesh arrays |
| `test_earth_placement_system.gd` | deterministic vegetation и exclusion rules |
| atmosphere plugin tests | activate/deactivate/recenter/cleanup |
| console/HUD/overlay tests | input, history, commands, formatting |
| logger tests | rotation, errors, valid JSON и bounded history |

## 7. Приоритет по риску

1. Terrain state machine, payload и collision.
2. Persistence corruption и atomicity.
3. Item representation в реальном physics world.
4. Simulator failure rollback.
5. Настоящий input, movement и raycast.
6. Earth vegetation/mesh и atmosphere plugins.
7. UI, diagnostics и compatibility.
8. Stress, performance, export и visual smoke.

Этот порядок основан не на размере файла, а на потенциальном ущербе:
повреждение сохранения, зависший worker, потеря предмета или проваливание игрока
опаснее, чем ошибка формата текста в HUD.
