# Документация PlanetSimulator

## Изменяемые миры и динамическое вещество

- `architecture/DYNAMIC_MATTER_FABRIC_RU.md` — целевая модель: процедурный объём, sparse persistent mutations, сохранение массы и переходы field/fragment/item/construct;
- `architecture/adr/ADR-017-dynamic-matter-fabric.md` — ADR, заменяющий прежнее общее решение heightfield + voxel;
- `plans/MUTABLE_WORLDS_ROADMAP_RU.md` — MW0–MW8 изолированного астероида, MI0–MI4 интеграции Луны и MP0–MP4 production track;
- `checkpoints/2026-07-31_MUTABLE_WORLDS_ARCHITECTURE_ROADMAP_RU.md` — документационный checkpoint анализа текущего среза.
- `architecture/MW0_MATTER_CONTRACTS_RU.md` — принятая граница контрактов вещества, snapshot channels, mutations и mass ledger;
- `architecture/MW1_FIXED_SEED_ASTEROID_RU.md` — accepted fixed-seed volumetric asteroid, stable features, geology и mass integration;
- `architecture/MW2_SPARSE_BRICKS_AND_QUERY_RU.md` — octree cells, sparse materialization, ghost seams и canonical query service;
- `checkpoints/2026-07-31_V17_0_0_SIMULATION_MW0_MATTER_CONTRACTS_RU.md` — первый code checkpoint geological track.
- `checkpoints/2026-07-31_V17_0_0_SIMULATION_MW0_MATTER_CONTRACTS_FIX1_RU.md` — принятое исправление typed normalization MW0.
- `checkpoints/2026-07-31_V17_1_0_SIMULATION_MW1_FIXED_SEED_ASTEROID_RU.md` — принятый MW1.
- `checkpoints/2026-07-31_V17_2_0_SIMULATION_MW2_SPARSE_BRICKS_RU.md` — исходный MW2 candidate.
- `checkpoints/2026-07-31_V17_2_0_SIMULATION_MW2_SPARSE_BRICKS_FIX1_RU.md` — текущий MW2 fix1 candidate: `get_snapshot()` вместо конфликтующего `get()`.

Принятый runtime checkpoint: `v16.10.5-persistence-m6-dedicated-recovery` (`ACCEPTED`, delivery `fix1`).
Текущий architecture candidate: `v16.10.6-architecture-a3-single-server-multiplayer`.

M1–M6 сформировали единый production gameplay path с graphical multiplayer, canonical Item Graph, reconnect/replay и durable recovery. A3 фиксирует эту архитектуру перед B1 NATS Core adapter.

Ключевые документы:

- `architecture/A3_SINGLE_SERVER_MULTIPLAYER_ARCHITECTURE_RU.md` — freeze единственного production single-server gameplay path;
- `checkpoints/2026-07-31_V16_10_6_ARCHITECTURE_A3_SINGLE_SERVER_MULTIPLAYER_RU.md`;
- `architecture/M6_DEDICATED_PERSISTENCE_RECOVERY_RU.md`;
- `checkpoints/2026-07-31_V16_10_5_PERSISTENCE_M6_DEDICATED_RECOVERY_RU.md`;
- `MCP_GODOT.md` — контракт автономного управления double Godot через MCP:
  managed processes, runtime input, viewport screenshots, assertions, логи и
  корректное завершение процесса;
- `architecture/M5_GRAPHICAL_ACCEPTANCE_PREPARATION_RU.md` — подготовительная UI/replica boundary M5;
- `checkpoints/2026-07-31_PRE_M5_GRAPHICAL_ACCEPTANCE_PREPARATION_RU.md`;
- `architecture/M4_PRE_M5_HANDOFF_RU.md` — актуальная база `main` перед M5:
  canonical M4 gameplay, сетевой полигон, MCP, окно client и camera-relative
  movement;
- `checkpoints/2026-07-30_V16_10_2_RUNTIME_M3_DEDICATED_GRAPHICAL_MULTIPLAYER_RU.md`;
- `checkpoints/2026-07-30_V16_10_1_RUNTIME_M2_DEDICATED_GRAPHICAL_CLIENT_RU.md`;
- `architecture/M3_DEDICATED_GRAPHICAL_MULTIPLAYER_RU.md`;
- `architecture/M2_DEDICATED_GRAPHICAL_CLIENT_RU.md`;
- `architecture/adr/ADR-015-dedicated-graphical-multiplayer.md`;
- `architecture/adr/ADR-014-dedicated-graphical-client.md`;
- `../config/network/dedicated-graphical-multiplayer.v1.json`;
- `../config/network/dedicated-graphical-client.v1.json`;
- `plans/SINGLE_SERVER_MULTIPLAYER_ROADMAP_RU.md`.

## v16.3.3 — Foundation world aggregate part 3

Checkpoint: `checkpoints/2026-07-27_V16_3_3_FOUNDATION_WORLD_AGGREGATE_PART3_RU.md`.

Контракты: `contracts/WORLD_ENTITY_AGGREGATE_V1_RU.md`, `contracts/ITEM_GRAPH_V2_RU.md`.

## v16.3.3 fix2 — presentation/spatial boundary hardening

- `checkpoints/2026-07-27_V16_3_3_FOUNDATION_WORLD_AGGREGATE_PART3_FIX2_RU.md`
- Dictionary keys and Object metadata are inspected for presentation objects.
- Raw SpatialRef is validated before quaternion canonicalization.

## v16.3.2 fix2 — terminal lifecycle world-load fence

Checkpoint: `checkpoints/2026-07-27_V16_3_2_FOUNDATION_LIFECYCLE_PART2_FIX2_RU.md`.

## v16.3.2 fix1 — Foundation lifecycle fail-closed

Checkpoint: `checkpoints/2026-07-27_V16_3_2_FOUNDATION_LIFECYCLE_PART2_FIX1_RU.md`.

## v16.3.2 — Foundation lifecycle part 2

Checkpoint: `checkpoints/2026-07-27_V16_3_2_FOUNDATION_LIFECYCLE_PART2_RU.md`.

## Чекпоинты

- `checkpoints/2026-07-29_V16_6_0_NETWORK_N2_PROCESS_HARNESS_RU.md` — N2 process orchestration, fault classification и JSON/JUnit.

- `checkpoints/2026-07-27_V16_3_3_FOUNDATION_WORLD_AGGREGATE_PART3_RU.md` — canonical WORLD aggregate, Item Graph v2 и SimulationKernel boundary.

- `checkpoints/2026-07-27_V16_3_2_FOUNDATION_LIFECYCLE_PART2_FIX2_RU.md` — terminal FAILED и release fence запрещают обычную загрузку мира после failed shutdown.

- `checkpoints/2026-07-27_V16_3_2_FOUNDATION_LIFECYCLE_PART2_FIX1_RU.md` — fail-closed drain barrier и аварийное завершение после отказа begin_shutdown.

- `checkpoints/2026-07-27_V16_3_2_FOUNDATION_LIFECYCLE_PART2_RU.md` — LifecycleCoordinator, graceful shutdown, terrain drain и simulation-server process test.

- `checkpoints/2026-07-27_V16_3_1_FOUNDATION_N0_PART1_RU.md` — runtime role contracts, N0 envelopes, loopback и authority fencing.
- `checkpoints/2026-07-27_V16_3_FOUNDATION_AND_NETWORK_CHECKPOINT_RU.md` — архитектурная ревизия и решение Foundation Gate + N0.

- `checkpoints/2026-07-26_R0_STABILIZATION_CHECKPOINT_RU.md`
- `checkpoints/2026-07-27_R1_1_ITEM_IDENTITY_STATE_STORE_RU.md`
- `checkpoints/2026-07-27_R1_2_OPERATION_LEDGER_RU.md`
- `checkpoints/2026-07-27_R1_3_GRAVITY_AND_PHYSICAL_MASS_RU.md`
- `checkpoints/2026-07-27_R1_4_R2_ITEM_GRAPH_AND_PLAYER_INVENTORY_RU.md`
- `checkpoints/2026-07-27_R2_STACK_CONTROLS_RU.md`
- `checkpoints/2026-07-27_R2_PLACEMENT_DEBUG_UI_RU.md`
- `checkpoints/2026-07-27_R2_INVENTORY_UX_LIGHTING_RU.md`

## Архитектура

- `architecture/audits/2026-07-27_V16_3_ARCHITECTURE_AND_NETWORK_AUDIT_RU.md`

- `architecture/MULTI_WORLD_SIMULATOR_CORE_RU.md`
- `architecture/REFERENCE_FRAMES_AND_DISTRIBUTED_SPACE_RU.md`
- `architecture/SHARED_SPACE_AND_PARTITIONING_RU.md`

- `architecture/PROCEDURAL_EARTH_RULE_PIPELINE_RU.md`

- `architecture/TARGET_ARCHITECTURE_RU.md`
- `architecture/PROJECT_STRUCTURE_RU.md`
- `architecture/ZONES_AND_CHUNKS_RU.md`
- `architecture/ENTITY_REGISTRY_V1_RU.md`
- `architecture/PERSISTENT_WORLD_LAYER_V1_RU.md`
- `architecture/PLUGGABLE_CONTROLLER_ARCHITECTURE_RU.md`
- `architecture/ASYNC_TERRAIN_STREAMING_V1_RU.md`
- `architecture/adr/`

## Контракты

- `contracts/WORLD_RUNTIME_V1_RU.md`
- `contracts/SPATIAL_REF_V1_RU.md`
- `contracts/PARTITION_ADDRESS_V2_RU.md`
- `contracts/ENTITY_STATE_V2_RU.md`
- `contracts/GRAVITY_FIELD_V1_RU.md`
- `contracts/ITEM_GRAPH_V1_RU.md`
- `contracts/ITEM_GRAPH_V2_RU.md`
- `contracts/WORLD_ENTITY_AGGREGATE_V1_RU.md`
- `contracts/CONTAINER_STATE_V2_RU.md`

- `contracts/PARTITION_SNAPSHOT_V1_RU.md`
- `contracts/WORLD_MANIFEST_V1_RU.md`
- `contracts/CHUNK_STATE_V1_RU.md`
- `contracts/JOURNAL_V1_RU.md`
- `contracts/CONTROLLER_PROFILE_V1_RU.md`

## Диагностика

- `diagnostics/LOGGING_RU.md`
- `diagnostics/TERRAIN_PERFORMANCE_LOGGING_RU.md`

## Network N1 checkpoints

- `checkpoints/2026-07-28_V16_5_2_FOUNDATION_NETWORK_N1_RU.md`
- `checkpoints/2026-07-28_V16_5_1_NETWORK_N1_REMOTE_ITEM_COMMAND_RU.md`
- `checkpoints/2026-07-28_V16_5_0_NETWORK_N1_SNAPSHOT_RU.md`
- `network/N1_NETWORK_IMPLEMENTATION_PLAN_RU.md`

## Foundation/N0 checkpoint

- `checkpoints/2026-07-27_V16_4_0_FOUNDATION_N0_RU.md`
- `contracts/N0_NETWORK_CONTRACTS_V1_RU.md`

## Сеть

- `network/NETWORK_READINESS_CHECKPOINT_RU.md`
- `network/SEAMLESS_WORLD_ROADMAP_RU.md`
- `network/N0_NETWORK_CONTRACTS_PLAN_RU.md`
- `network/NETWORK_TEST_MATRIX_RU.md`
- `network/PARALLEL_DEVELOPMENT_RULES_RU.md`

## Планы

- `plans/V16_4_FOUNDATION_GATE_PLAN_RU.md`

- `plans/EARTH_MOON_ARCHITECTURE_TEST_RU.md`

- `plans/ROADMAP_RU.md`
- `plans/NEXT_ITERATIONS_RU.md`
- `plans/V11_ACCEPTANCE_TESTS_RU.md`
- `plans/V12_ACCEPTANCE_TESTS_RU.md`
- `plans/V13_ACCEPTANCE_TESTS_RU.md`
- `plans/V14_ACCEPTANCE_TESTS_RU.md`
- `plans/V15_ACCEPTANCE_TESTS_RU.md`
- `plans/V15_5_ACCEPTANCE_TESTS_RU.md`
- `plans/V15_5_1_COORDINATE_FOUNDATION_PLAN_RU.md`
- `plans/V15_5_1_ACCEPTANCE_TESTS_RU.md`

## Рельеф и LOD

- `terrain/LOD_ARCHITECTURE_V9_RU.md`
- `terrain/LOD_LAYERS_V8_RU.md`
- `terrain/MICRO_DETAIL_ARCHITECTURE_RU.md`
- `terrain/PHOTO_SURFACE_V9_RU.md`


## Зафиксированная проверка coordinate foundation

- `docs/diagnostics/V15_5_1_FIXED_VALIDATION_RU.md`

- [`checkpoints/2026-07-27_V16_3_1_FOUNDATION_N0_PART1_FIX1_RU.md`](checkpoints/2026-07-27_V16_3_1_FOUNDATION_N0_PART1_FIX1_RU.md) — strict schema и fail-closed handler result;

- `architecture/A1_GENERIC_AGGREGATE_FOUNDATION_RU.md` — generic aggregate contracts, adapters and replica store.
- `checkpoints/2026-07-29_V16_8_1_ARCHITECTURE_A1_GENERIC_AGGREGATE_RU.md` — A1 checkpoint.

- `architecture/M0_MULTI_AGGREGATE_TRANSACTIONS_OUTBOX_RU.md` — атомарные multi-aggregate commits и transactional outbox.

## M5 graphical multiplayer acceptance

- [`architecture/M5_GRAPHICAL_MULTIPLAYER_ACCEPTANCE_RU.md`](architecture/M5_GRAPHICAL_MULTIPLAYER_ACCEPTANCE_RU.md)
- [`checkpoints/2026-07-31_V16_10_4_TESTING_M5_GRAPHICAL_MULTIPLAYER_ACCEPTANCE_RU.md`](checkpoints/2026-07-31_V16_10_4_TESTING_M5_GRAPHICAL_MULTIPLAYER_ACCEPTANCE_RU.md)
