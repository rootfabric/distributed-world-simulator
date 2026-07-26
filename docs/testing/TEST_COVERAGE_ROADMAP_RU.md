# Дорожная карта покрытия тестами

Документ определяет постепенное развитие тестов без большого одномоментного
переписывания проекта.

## Основные ограничения

- Существующие 26 regression tests нельзя выключать или заменять до появления
  эквивалентной проверки.
- Production-код меняется ради testability только отдельными маленькими задачами
  с объяснённым контрактом.
- Каждый этап должен оставлять regression suite зелёным.
- Новые engine tests запускаются настоящим Godot, а не имитацией `_process()`.
- Async-тесты до обновления RuntimeTestRegistry остаются отдельными SceneTree
  scripts.
- Stress/visual/performance tests не должны замедлять обычный быстрый цикл.

## Этап T0 — документация и инвентаризация

**Статус:** этот документальный пакет.

Сделано:

- зафиксирована стратегия;
- описан текущий аудит;
- выделены риски;
- определена последовательность;
- описаны правила новых тестов.

Критерий завершения:

- документы находятся в `docs/testing`;
- production-код и тесты не изменены;
- команда может выбрать следующий малый пакет без повторного исследования.

## Этап T1 — инфраструктура существующего runner

Цель — не добавить десятки тестов, а сделать дальнейшее расширение безопасным.

Планируемые файлы:

```text
tests/support/test_case.gd
tests/support/test_engine_guard.gd
tests/support/test_temp_directory.gd
tests/support/test_scene_factory.gd
tests/meta/test_coverage_manifest.gd
config/test_coverage_manifest.json
```

Планируемые возможности:

- общие assertions;
- ожидание process/physics frames;
- `await_condition` и `await_signal` с timeout;
- автоматический cleanup nodes;
- временный каталог каждого теста;
- восстановление global engine/input state;
- orphan-node baseline;
- единый failure snapshot;
- manifest production module → test/exclusion.

Отдельно решить контракт async callback в `RuntimeTestRegistry`:

- поддержать ожидание;
- или явно запретить async callbacks;
- не допускать ложного PASS.

Критерий завершения:

- существующие тесты работают без изменения семантики;
- новый helper проверен собственными meta-тестами;
- зависший тест завершается по timeout;
- временные файлы и nodes очищаются после failure.

## Этап T2 — core и runtime lifecycle

Первый функциональный пакет:

```text
tests/core/test_runtime_test_registry.gd
tests/core/test_command_registry_errors.gd
tests/core/test_world_catalog_validation.gd
tests/runtime/test_simulator_world_lifecycle_failures.gd
tests/runtime/test_world_switch_repetition.gd
```

Покрыть:

- все invalid inputs registry/catalog;
- aliases и parser edge cases;
- owner cleanup;
- runtime contract failures;
- rollback после неудачной загрузки;
- повторный успешный load после failure;
- ограничение history;
- отсутствие утечек команд и test owners;
- repeated world switching.

Критерий завершения:

- каждый публичный error code core registry имеет тест;
- любой failed runtime оставляет SimulatorApp в согласованном состоянии;
- после циклов в WorldHost находится ровно один runtime;
- число orphan nodes не растёт.

## Этап T3 — предметы и persistence safety

### T3.1. Item error matrix

```text
tests/items/test_item_error_matrix.gd
tests/items/test_item_attachment_service.gd
tests/items/test_item_signal_contract.gd
```

Проверить:

- каждый item/container/attachment error code;
- отсутствие partial mutation;
- точное число signals;
- idempotent repeated operations;
- cycle prevention;
- slot occupancy.

### T3.2. Item engine representation

```text
tests/items/test_item_representation_physics.gd
```

Проверить реальными кадрами:

- WORLD создаёт один body;
- CONTAINER удаляет body;
- WORLD восстанавливает body;
- ATTACHMENT не оставляет независимую физику;
- transform, linear/angular velocity и SpatialRef сохраняются;
- повторная synchronization не создаёт duplicate nodes.

### T3.3. Persistence corruption

```text
tests/persistence/test_persistence_corruption.gd
tests/persistence/test_persistence_atomic_write.gd
tests/persistence/test_repository_event_contract.gd
```

Покрыть повреждённые manifest/chunk/journal, unsupported versions, duplicate IDs,
atomic overwrite и failure recovery.

Критерий завершения:

- невозможно получить частично загруженный предметный граф без явной ошибки;
- failed operation не меняет aggregate;
- WORLD/CONTAINER/ATTACHMENT переживают round-trip;
- повреждённое сохранение обрабатывается по документированному fail-closed
  контракту.

## Этап T4 — terrain generation и streaming

Это наиболее объёмный и рискованный этап. Делить минимум на четыре патча.

### T4.1. Чистая генерация

```text
tests/terrain/test_moon_generation_determinism.gd
tests/terrain/test_streaming_payload_geometry.gd
```

Проверить seed, finite values, indices, normals, bounds и collision payload.

### T4.2. State machine

```text
tests/terrain/test_streaming_state_machine.gd
```

Проверить все переходы, pending request, stale result, cancellation и latest
revision wins.

### T4.3. Cache

```text
tests/terrain/test_surface_cache_policy.gd
```

Проверить LRU, capacity, pinning, hit/miss и cached activation.

### T4.4. Реальный commit/collision

```text
tests/terrain/test_streaming_commit_collision.gd
```

Проверить staged commit, raycast новой поверхности, безопасность actor и
отсутствие накопления collision bodies.

Критерий завершения:

- одинаковый seed даёт эквивалентный payload;
- невалидная геометрия никогда не доходит до commit;
- stale worker result не заменяет новую поверхность;
- unload/cancel не оставляет staging и worker ownership;
- repeated swaps не увеличивают число terrain nodes.

## Этап T5 — input, movement и interaction

Планируемые тесты:

```text
tests/actors/test_controller_host.gd
tests/actors/test_lunar_player_lifecycle.gd
tests/physics/test_flat_humanoid_movement.gd
tests/physics/test_planetary_humanoid_movement.gd
tests/physics/test_jetpack_movement.gd
tests/actors/test_spectator_controller.gd
tests/interaction/test_world_interactor_raycast.gd
```

Покрыть:

- настоящий Input action pipeline;
- press/release и очистку input state;
- CharacterBody movement и collision;
- radial gravity и local up;
- camera-relative jetpack;
- camera modes, pitch/yaw/roll;
- настоящий raycast, masks и focus lifecycle.

Критерий завершения:

- тест не вызывает controller method напрямую вместо input;
- actor реально перемещается за physics frames;
- actor не проходит через static collision;
- disabled controller/interactor не изменяет состояние;
- input не протекает между тестами.

## Этап T6 — Earth, atmosphere, UI и diagnostics

### Earth

- отдельные tests каждого rule;
- ProceduralEarthWorld transforms, gravity и mesh validity;
- deterministic vegetation;
- asset library completeness.

### Atmosphere

- exact altitude boundaries;
- activate/deactivate;
- plugin errors;
- cloud recenter и cleanup;
- восстановление baseline environment.

### UI и diagnostics

- DeveloperConsole history/completion;
- HUD command wiring;
- PlanetaryOverlay modes;
- logger JSON, rotation и failure paths;
- compatibility wrapper smoke.

Критерий завершения:

- каждый config-driven type имеет валидный ресурс;
- UI проверяется через контракт, а не pixel coordinates;
- atmosphere не остаётся активной после смены мира;
- логирование не вызывает падение при файловой ошибке.

## Этап T7 — property, stress и leak detection

Планируемые наборы:

```text
tests/property/test_item_graph_sequences.gd
tests/property/test_spatial_partition_roundtrip.gd
tests/stress/test_world_switch_stress.gd
tests/stress/test_terrain_streaming_stress.gd
tests/stress/test_persistence_repeated_roundtrip.gd
tests/stress/test_entity_registry_stress.gd
```

Каждый случайный тест обязан сохранять:

- seed;
- последовательность команд;
- последний valid snapshot;
- первый нарушенный invariant.

Критерий завершения:

- random failure воспроизводится одним seed;
- histories/caches остаются bounded;
- число nodes, workers и owners возвращается к baseline;
- многократный round-trip не изменяет каноническое состояние.

## Этап T8 — performance, visual и export

Добавить отдельные команды, не блокирующие обычный быстрый commit:

```text
RUN_FAST_TESTS.ps1
RUN_ENGINE_TESTS.ps1
RUN_WORLD_REGRESSION_TESTS.ps1
RUN_STRESS_TESTS.ps1
RUN_VISUAL_TESTS.ps1
RUN_EXPORT_SMOKE_TESTS.ps1
RUN_ALL_TESTS.ps1
```

Проверять:

- structural performance budgets;
- memory/node recovery;
- GPU renderer smoke;
- фиксированные visual snapshots с допуском;
- Windows/Linux export;
- запуск exported build и короткий сценарий.

Критерий завершения:

- быстрый набор остаётся удобным для локальной работы;
- тяжёлые тесты запускаются отдельно/nightly;
- отчёты сохраняются в JSON/JUnit;
- engine update сопровождается полным regression + visual/export smoke.

## Рекомендуемый первый пакет реализации

После этого документационного этапа не нужно сразу реализовывать всю дорожную
карту. Первый реальный патч ограничить следующими задачами:

1. `TestEngineGuard` и timeout helper.
2. Meta-test полноты manifest.
3. `test_runtime_test_registry.gd`.
4. `test_world_catalog_validation.gd`.
5. `test_simulator_world_lifecycle_failures.gd`.
6. `test_item_error_matrix.gd`.
7. `test_item_representation_physics.gd`.
8. `test_persistence_corruption.gd`.
9. `test_streaming_state_machine.gd` с fake worker result.
10. `test_world_interactor_raycast.gd`.

Этот пакет закрывает наиболее опасные пробелы и одновременно создаёт шаблон для
последующих тестов.

## Definition of Done для нового production-функционала

Новая подсистема не считается завершённой, пока не определены:

- её публичные invariants;
- error codes;
- signals;
- lifecycle start/cancel/unload;
- snapshot для диагностики;
- round-trip schema, если есть persistence;
- минимум один success test;
- минимум один boundary test;
- минимум один failure/rollback test;
- cleanup test для engine resources;
- место теста в fast/engine/system/stress suite.
