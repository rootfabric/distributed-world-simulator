# MW0 — канонические контракты изменяемого вещества

**Checkpoint:** `v17.0.0-simulation-mw0-matter-contracts`
**Статус:** accepted, delivery `fix1`
**Base:** `v16.10.6-architecture-a3-single-server-multiplayer`
**Ветка:** `feature/mw0-matter-contracts`
**Связанная парадигма:** `DYNAMIC_MATTER_FABRIC_RU.md`

## 1. Назначение этапа

MW0 создаёт чистую доменную границу изменяемого вещества до появления генератора астероида, мешей, коллизий и инструментов бурения.

Код этапа не подключается к `SceneTree`, не меняет текущую Луну и не создаёт второй runtime-путь. Он фиксирует данные, которые должны одинаково понимать:

- процедурный генератор MW1;
- sparse storage MW2;
- meshing adapter MW3;
- добыча и Item Graph MW4;
- persistence MW5;
- сетевой authority MP0–MP2.

## 2. Замороженные решения

### 2.1. Вещество — каноническое состояние, меш — производное

`MatterSample` описывает локальное состояние поля:

```text
signed distance
+ occupancy
+ density
+ composition
+ integrity
+ temperature
+ porosity
+ semantic flags
```

Presentation material, `Mesh`, `Node`, `Resource`, collision shape и render origin в контракт не входят.

### 2.2. Геометрия и состав разделены на каналы

`MatterBrickSnapshot` хранит:

```text
GeometryChannel
    signed_distance_m
    occupancy_ratio

CompositionChannel
    canonical composition palette
    palette indices

PropertyChannel
    density
    integrity
    temperature
    porosity
    flags
```

Это позволяет в следующих этапах применять разное сжатие и разные storage LOD, не смешивая физический смысл с presentation.

### 2.3. Пространственная идентичность переиспользует S0

`MatterBrickAddress` содержит валидный `SimulationCellAddress` и локальный адрес brick:

```text
SimulationCellAddress
+ storage_level
+ brick_x / brick_y / brick_z
```

Он не объявляет authority owner. Пространственная identity и сетевое владение остаются разными понятиями.

### 2.4. Изменение мира выражается транзакцией

`MatterMutationRequest` содержит:

- стабильный `operation_id`;
- тело, actor и tool;
- тип операции;
- отсортированный набор затронутых bricks;
- expected revision каждого brick;
- пространственную форму операции;
- контейнеры-источники и получатели;
- бюджет массы и энергии;
- client tick.

Первый набор операций:

```text
EXCAVATE
DEPOSIT
FRACTURE
COMPACT
MELT
FREEZE
```

Фактический commit появится позже через существующие M0/A1 foundations. MW0 фиксирует только строгий DTO boundary.

### 2.5. Масса не может исчезнуть неявно

`MatterMassLedger` отдельно считает:

- входную и выходную массу;
- общий balance error;
- баланс по каждому material ID;
- замкнутость в заданной абсолютной tolerance.

Результат операции с незамкнутым ledger не может быть `COMMITTED`.

## 3. Контракты

| Контракт | Роль |
|---|---|
| `MatterMaterialDefinition` | физические, геологические, тепловые и технологические свойства материала |
| `MatterComposition` | нормализованная смесь stable material IDs |
| `MatterSample` | состояние вещества в точке/ячейке поля |
| `MatterBodyDefinition` | идентичность тела и версия его канонического генератора |
| `MatterBrickAddress` | адрес sparse-блока поверх S0 cell identity |
| `MatterBrickSnapshot` | checksum-protected канонический снимок каналов блока |
| `MatterMutationRequest` | намерение изменить вещество с revision fencing |
| `MatterMutationResult` | committed/rejected результат без скрытых эффектов |
| `MatterMassLedger` | проверяемый общий и покомпонентный баланс массы |
| `MatterMaterialCatalog` | детерминированный каталог материалов и его content hash |

Все payload:

- exact-field validated;
- JSON-safe;
- checksum-protected;
- канонически сортируют ID и composition;
- отклоняют `NaN`, `INF`, runtime/presentation objects;
- имеют стабильный JSON roundtrip.

## 4. Базовый каталог MW0

```text
matter/regolith-loose
matter/regolith-compacted
matter/basalt
matter/fractured-basalt
matter/water-ice
matter/iron-nickel-ore
matter/silicate-waste
```

Свойства каталога пока являются инженерными начальными параметрами, а не претензией на полный научный справочник. Их schema и единицы заморожены, численные значения разрешено уточнять отдельным versioned catalog checkpoint.

## 5. Фиксированный лабораторный астероид

MW0 резервирует fixture, который реализует MW1:

```text
body_id:             body/asteroid-mw0
body_frame_id:       body/asteroid-mw0/fixed
reference_radius_m:  1000
seed:                2026073101
generator_version:   1.0.0
```

MW0 не генерирует форму астероида. Он не позволяет случайно изменить его identity, seed или radius при начале MW1.

## 6. Тестовый gate

Focused runner:

```powershell
./RUN_MW0_MATTER_CONTRACTS_TESTS.ps1
```

```bash
./RUN_MW0_MATTER_CONTRACTS_TESTS.sh
```

Проверяются:

- положительные и отрицательные schema cases;
- exact fields и canonical IDs;
- checksum mutation;
- JSON roundtrip;
- composition normalization;
- snapshot channel consistency;
- revision monotonicity;
- rejected result without side effects;
- balanced/unbalanced material ledger;
- deterministic property scenarios с фиксированными seeds;
- запрет Godot runtime objects внутри domain DTO.

## 7. Что сознательно не входит

- SDF/noise sampler;
- реальные brick dimensions;
- materialization и cache;
- mesh/collision;
- изменение существующих Moon scripts;
- Item Graph transfer;
- persistence;
- authority service и network wire protocol.

## 8. Следующий этап

После независимой приёмки MW0 создаётся новая ветка:

```text
feature/mw1-fixed-seed-asteroid
```

MW1 реализует observer-independent sampler астероида радиусом 1000 м с seed `2026073101`, детерминированной формой, базовой неоднородной геологией и интеграцией массы без mesh/runtime.
