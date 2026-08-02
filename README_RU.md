# PlanetSimulator — MW9 durable handoff candidate

Текущий checkpoint: `v17.11.0-simulation-mw9-durable-handoff-recovery` поверх принятого RL1.

MW9 сохраняет authority lease и append-only handoff journal атомарно, вводит exact fencing token, lease expiry/claim и детерминированное crash recovery. `COMMIT_DECIDED` необратим; transfer без durable decision после restart abort-ится. RL1 summary manifest переносится только как восстанавливаемый cache hint.

Focused runner: `RUN_MW9_DURABLE_HANDOFF_RECOVERY_TESTS.ps1` или `.sh`.

Архитектура: `docs/architecture/MW9_DURABLE_DISTRIBUTED_HANDOFF_RECOVERY_RU.md`.

# PlanetSimulator

Текущий Matter/Representation checkpoint:

```text
v17.10.0-simulation-rl1-matter-summary-pyramid
build_id: rl1-matter-summary-pyramid-dirty-propagation
base: accepted RL0 fix1
branch: feature/rl1-matter-summary-pyramid
status: candidate for independent review
next: MW9 durable distributed handoff and crash recovery
```

RL1 добавляет региональную summary pyramid, descendant dependency hashes, selective dirty propagation и bounded rebuild queue без изменения canonical Matter state, MW8 authority protocol или production worlds.

Текущая принятая архитектурная база: `v16.9.4-architecture-a2-networked-gameplay` (`FROZEN_WITH_GATES`).

Принятый стратегический checkpoint: `v16.9.5-roadmap-single-server-multiplayer-first`.

Принятый runtime checkpoint: `v16.10.5-persistence-m6-dedicated-recovery` (`ACCEPTED`, delivery `fix1`).

Текущий architecture candidate:

```text
v16.10.6-architecture-a3-single-server-multiplayer
build_id: a3-single-server-multiplayer-architecture-freeze
runtime base: v16.10.5-persistence-m6-dedicated-recovery
branch: feature/a3-single-server-multiplayer-architecture
status: candidate
next after acceptance: B1 NATS Core adapter
```

A3 фиксирует единственный production gameplay path: один `NetworkedGameplayService`, общие versioned wire contracts, LOOPBACK/ENet adapters, replica-only graphical clients, canonical M4 Item Graph и M6 durable recovery/replay. B1 после A3 может добавлять только server-to-server transport и не вправе создавать второй gameplay authority.

```text
FULL SINGLE-SERVER MULTIPLAYER FIRST
A2 → M1 → M2 → M3 → M4 → M5 → M6 → A3 → B1 → B2 → N3 → N4 → N5 → N6
```

До принятия A3 B1/B2 production integration отложена; N3–N6 заблокированы до A3 и B2. ENet остаётся realtime transport graphical clients.

Основные документы:

- `docs/architecture/DYNAMIC_MATTER_FABRIC_RU.md` — целевая парадигма изменяемого вещества, астероидов, пещер и добычи;
- `docs/architecture/MW0_MATTER_CONTRACTS_RU.md` — принятая граница canonical matter contracts;
- `docs/architecture/MW1_FIXED_SEED_ASTEROID_RU.md` — принятое детерминированное объёмное тело астероида, stable features и mass integration;
- `docs/architecture/MW2_SPARSE_BRICKS_AND_QUERY_RU.md` — принятые иерархические matter cells, sparse bricks, ghost samples и canonical query service;
- `docs/architecture/MW3_LOCAL_MESHING_RU.md` — принятый local Freudenthal meshing, ghost-gradient normals, collision и camera-local laboratory;
- `docs/architecture/MW4_MATTER_MUTATIONS_RU.md` — транзакционное swept-бурение, session-local persistent snapshots, mass ledger и Material Batch; MW4 fix2 дополнительно ограничивает integer-valued energy/capacity значения каноническим JSON-пределом `2^53−1`;
- `docs/architecture/MW5_MATTER_PERSISTENCE_RU.md` — durable checkpoint, атомарный repository, exact binary64 transport и process-level restart recovery;
- `docs/architecture/MW6_MATTER_NETWORK_AUTHORITY_RU.md` — принятый single-server authority и persistent-only matter replication;
- `docs/architecture/MW7_MATTER_INTEREST_REPLICATION_RU.md` — региональные interest projections, enter/leave, replay и snapshot fallback;
- `docs/architecture/MW8_REGIONAL_AUTHORITY_HANDOFF_RU.md` — принятый межсерверный regional authority handoff;
- `docs/architecture/REPRESENTATION_LOD_FABRIC_RU.md` — общий Matter/Construction lifecycle detail, proxy и impostor artifacts;
- `docs/architecture/RL1_MATTER_SUMMARY_PYRAMID_RU.md` — региональные Matter summaries, dirty ancestor propagation и bounded rebuild queue;
- `docs/architecture/adr/ADR-018-representation-lod-fabric.md` — ADR общего lifecycle и раздельных Matter/Construction builders;
- `docs/plans/REPRESENTATION_LOD_ROADMAP_RU.md` — RL0–RL6 и оптимальная интеграция с MW9–MW14;
- `docs/checkpoints/2026-08-01_V17_5_0_SIMULATION_MW5_MATTER_PERSISTENCE_FIX2_RU.md` — MW5 fix2: единый canonical persistence encoder и checksum-preserving snapshot rehydration;
- `docs/checkpoints/2026-08-01_V17_5_0_SIMULATION_MW5_MATTER_PERSISTENCE_FIX3_RU.md` — MW5 fix3: точное равенство опубликованных raw bytes и canonical persistence bytes;
- `docs/checkpoints/2026-08-01_V17_5_0_SIMULATION_MW5_MATTER_PERSISTENCE_FIX5_RU.md` — MW5 fix5: exact binary64 transport envelope вместо decimal JSON float roundtrip;
- `docs/checkpoints/2026-08-01_V17_5_0_SIMULATION_MW5_MATTER_PERSISTENCE_FIX6_RU.md` — MW5 fix6: corrected Godot binary64 probe and process-context center transport;
- `docs/checkpoints/2026-08-01_V17_5_0_SIMULATION_MW5_MATTER_PERSISTENCE_FIX7_RU.md` — MW5 fix7: детерминированный положительный tunnel witness и exact SDF comparison после restart;
- `docs/checkpoints/2026-07-31_V17_0_0_SIMULATION_MW0_MATTER_CONTRACTS_RU.md`;
- `docs/checkpoints/2026-07-31_V17_0_0_SIMULATION_MW0_MATTER_CONTRACTS_FIX1_RU.md` — принятый typed normalization fix1;
- `docs/checkpoints/2026-07-31_V17_1_0_SIMULATION_MW1_FIXED_SEED_ASTEROID_RU.md` — принятый MW1;
- `docs/checkpoints/2026-07-31_V17_2_0_SIMULATION_MW2_SPARSE_BRICKS_RU.md` — исходный MW2 candidate;
- `docs/checkpoints/2026-07-31_V17_2_0_SIMULATION_MW2_SPARSE_BRICKS_FIX1_RU.md` — принятый MW2 fix1;
- `docs/checkpoints/2026-07-31_V17_3_0_SIMULATION_MW3_LOCAL_MESHING_RU.md` — исходный MW3 candidate;
- `docs/checkpoints/2026-07-31_V17_3_0_SIMULATION_MW3_LOCAL_MESHING_FIX1_RU.md` — MW3 fix1: lifecycle-safe streamer и non-empty seam validation;
- `docs/checkpoints/2026-07-31_V17_3_0_SIMULATION_MW3_LOCAL_MESHING_FIX2_RU.md` — принятый MW3 fix2;
- `docs/checkpoints/2026-07-31_V17_4_0_SIMULATION_MW4_MATTER_MUTATIONS_RU.md` — исходный MW4 candidate;
- `docs/checkpoints/2026-08-01_V17_4_0_SIMULATION_MW4_MATTER_MUTATIONS_FIX1_RU.md` — текущий MW4 fix1 candidate: bounded focused runner и устранение квадратичной snapshot-валидации;
- `docs/checkpoints/2026-08-01_V17_4_0_SIMULATION_MW4_MATTER_MUTATIONS_FIX2_RU.md` — функционально прошедший MW4 fix2: JSON-safe energy budgets и отрицательный boundary-тест; фактическая topology — `187 assertions`;
- `docs/checkpoints/2026-08-01_V17_4_0_SIMULATION_MW4_MATTER_MUTATIONS_FIX3_RU.md` — текущий metadata-only fix3: исправление зафиксированной topology `103 → 187 assertions`;
- `config/matter/mw1-fixed-seed-asteroid.v1.json`;
- `config/matter/mw2-sparse-bricks-and-query.v1.json`;
- `config/matter/mw3-local-meshing.v1.json`;
- `config/matter/mw4-matter-mutations.v1.json`;
- `scenes/labs/matter_asteroid_meshing_lab.tscn` — принятая MW3 laboratory;
- `scenes/labs/matter_asteroid_excavation_lab.tscn` — MW4 laboratory с canonical raycast и транзакционным буром;
- `docs/plans/MUTABLE_WORLDS_ROADMAP_RU.md` — отдельный asteroid lab track и последующая интеграция в Луну;
- `docs/architecture/adr/ADR-017-dynamic-matter-fabric.md` — решение procedural volume + sparse persistent mutations;
- `docs/architecture/A3_SINGLE_SERVER_MULTIPLAYER_ARCHITECTURE_RU.md`;
- `config/network/single-server-multiplayer-architecture.v1.json`;
- `docs/checkpoints/2026-07-31_V16_10_6_ARCHITECTURE_A3_SINGLE_SERVER_MULTIPLAYER_RU.md`;
- `docs/architecture/M6_DEDICATED_PERSISTENCE_RECOVERY_RU.md`;
- `docs/checkpoints/2026-07-31_V16_10_5_PERSISTENCE_M6_DEDICATED_RECOVERY_RU.md`;
- `config/network/dedicated-persistence-recovery.v1.json`;
- `docs/architecture/M5_GRAPHICAL_MULTIPLAYER_ACCEPTANCE_RU.md`;
- `docs/architecture/M5_GRAPHICAL_ACCEPTANCE_PREPARATION_RU.md`;
- `docs/checkpoints/2026-07-31_V16_10_4_TESTING_M5_GRAPHICAL_MULTIPLAYER_ACCEPTANCE_RU.md`;
- `docs/checkpoints/2026-07-31_PRE_M5_GRAPHICAL_ACCEPTANCE_PREPARATION_RU.md`;
- `docs/architecture/M4_PRE_M5_HANDOFF_RU.md`;
- `docs/architecture/M4_CANONICAL_SHARED_GAMEPLAY_RU.md`;
- `docs/checkpoints/2026-07-30_V16_10_3_DOMAIN_M4_CANONICAL_SHARED_GAMEPLAY_RU.md`;
- `docs/architecture/M3_DEDICATED_GRAPHICAL_MULTIPLAYER_RU.md`;
- `docs/architecture/M2_DEDICATED_GRAPHICAL_CLIENT_RU.md`;
- `docs/architecture/M1_UNIFIED_NETWORKED_GAMEPLAY_CORE_RU.md`;
- `config/network/m5-graphical-acceptance-preparation.v1.json`;
- `config/network/canonical-shared-gameplay.v1.json`;
- `config/network/network-roadmap.v1.json`;
- `docs/plans/SINGLE_SERVER_MULTIPLAYER_ROADMAP_RU.md`;
- `NETWORK_ROADMAP_RU.md`.


## MW5 matter persistence fix7 — ACCEPTED

```text
checkpoint: v17.5.0-simulation-mw5-matter-persistence
delivery: fix7
base: v17.4.0-simulation-mw4-matter-mutations / fix3 (ACCEPTED)
branch: feature/mw5-matter-persistence
scope: isolated asteroid matter track; production Moon/world catalog unchanged
```

MW5 сохраняет изменённые sparse-brick snapshots и revisions, mutation journal и committed Material Batch в атомарный generation-chained checkpoint. Fix5 устраняет drift durable DTO, fix6 закрывает exact binary64 process transport, а fix7 устраняет недоказанную предпосылку о том, что геометрический центр drill capsule обязательно находится в vacuum. После commit focused-профиль сканирует interior lattice изменённых snapshots, детерминированно выбирает положительный SDF witness, подтверждает его через canonical continuous query и только затем сохраняет позицию и SDF через binary64 transport. После restart восстановленный SDF обязан быть побитово равен pre-save значению и оставаться положительным. Durable checkpoint/repository protocol при этом не изменяется.

## MW6 matter network authority fix2 — ACCEPTED

```text
checkpoint: v17.6.0-simulation-mw6-matter-network-replication
base: v17.5.0-simulation-mw5-matter-persistence / fix7 (ACCEPTED)
branch: feature/mw6-matter-network-replication
scope: isolated asteroid matter track; production Moon/world catalog unchanged
```

MW6 подключает транзакции MW4 и durable state MW5 к уже принятому single-server network path. После MW5 recovery authoritative stream начинается с размера восстановленного journal, а клиент получает full snapshot без выдуманного replay-log. Клиент отправляет exact-transport mutation command через `NetworkCommandGateway`, сервер единолично вызывает `MatterExcavationService`, а persistent brick revisions и journal outcomes реплицируются через `ReplicationEnvelope`. Reconnect использует delta replay по sequence/base hash и переходит на full persistent snapshot при gap или вытеснении replay log. Procedural revision-0 bricks по сети не передаются.


## MW6 fix2 — ACCEPTED

Принятая матрица: MW6 `130/130 PASS`, M6 standalone `10/10 PASS`, M6 process recovery `128/128 PASS`, A3 — три последовательных PASS. Fix2 является parse-only коррекцией M6 regression-теста поверх функционального fix1.

## MW7 regional matter interest — ACCEPTED

```text
checkpoint: v17.7.0-simulation-mw7-matter-interest-replication
base: v17.6.0-simulation-mw6-matter-network-replication / fix2 (ACCEPTED)
branch: feature/mw7-matter-interest-replication
decision: ACCEPTED
scope: isolated asteroid matter track; production Moon/world catalog unchanged
```

MW7 сохраняет глобальную авторитетную последовательность MW6, но реплицирует клиенту только persistent bricks его checksum-protected cell region. Каждая subscription имеет собственные `interest_revision`, `region_sequence` и `projection_hash`. Нерелевантные мутации не создают кадр. Смена области выполняется replacement snapshot с атомарным enter/leave, а reconnect выбирает regional delta replay или filtered snapshot fallback.


## MW8 regional authority handoff — ACCEPTED

```text
checkpoint: v17.8.0-simulation-mw8-regional-authority-handoff
base: v17.7.0-simulation-mw7-matter-interest-replication (ACCEPTED)
branch: feature/mw8-regional-authority-handoff
scope: isolated asteroid matter track; production Moon/world catalog unchanged
```

MW8 добавляет первый ограниченный межсерверный authority handoff. Directory хранит единственный lease каждой непересекающейся cell-region. Source сначала замораживает запись, target импортирует persistent snapshots, релевантный journal и связанные material batches под компенсационным backup, после чего directory атомарно меняет owner и authority epoch. Старый сервер немедленно теряет право записи, новый обслуживает exact replay и продолжает MW6 stream из импортированного journal frontier. Клиент получает checksum-protected handoff ticket и повторно подключает MW7 regional replica к target. Mutation через несколько authority-regions пока отклоняется.


## RL0 unified representation contracts — CANDIDATE

```text
checkpoint: v17.9.0-simulation-rl0-representation-contracts
base: v17.8.0-simulation-mw8-regional-authority-handoff (ACCEPTED)
branch: feature/rl0-representation-contracts
production Moon/world catalog changed: false
```

RL0 вводит единый cross-domain lifecycle производных представлений для Matter и Construction: exact source revision, representation key, content-addressed artifact manifest, screen/geometric error interest, deterministic coarsest-acceptable selector, dependency set, invalidation и cache states. Реальный coarse SDF meshing и Construction HLOD относятся к RL2/RL4.
