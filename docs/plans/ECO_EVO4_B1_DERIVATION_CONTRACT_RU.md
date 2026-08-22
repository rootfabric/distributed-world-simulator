# ECO.EVO4/E4.B1 — Контракт деривации DevelopmentTraits v0 и расширения каталога

Статус: `RESEARCH_ONLY / BRIDGE_CONTRACT / NO_ACCEPTANCE_AUTHORITY`.
Правило деривации: `evo4-b0-derivation-v0` (заморожено настоящим документом).

## 1. Честность правила

DevelopmentTraits v0 являются **детерминированной деривацией** metabolic-полей генома принятого каталога. Правило не создаёт новой поверхности отбора, не меняет ecological truth и существует только на presentation-стороне моста. Независимые developmental гены (ступень v1) вынесены за пределы моста и требуют отдельной авторизации со связью к causal model.

Принятый каталог `config/ecology/accepted_inputs/evo2_full_persisted_species_catalog.e3_4.v1.json` остаётся каноническим входом и никогда не модифицируется; расширенный артефакт — research-слой (`validation/ecology/`).

## 2. Формулы (метabolic → developmental)

| Trait | Формула | Bounds (PH0) |
|---|---|---|
| `max_height_m` | `height_m * 4.0` | [0.10, 40.0] |
| `internode_length_m` | `clamp(height_m * 0.40, 0.02, 4.0)` | [0.02, 4.0] |
| `apical_dominance` | `clamp(1.0 − seed_dispersal_distance_m / 40.0, 0, 1)` | [0.0, 1.0] |
| `branch_probability` | `clamp(seed_count / 700.0, 0, 1)` | [0.0, 1.0] |
| `branch_angle_deg` | `clamp(25.0 + shade_tolerance * 40.0, 0, 89)` | [0.0, 89.0] |
| `branch_length_ratio` | `clamp(0.60 + water_preference * 0.35, 0.05, 2.0)` | [0.05, 2.0] |
| `branching_depth` | `clamp(int(2 + round(shade_tolerance * 2)), 1, 8)` (TYPE_INT) | [1, 8] |
| `crown_spread_m` | `clamp(seed_dispersal_distance_m * 0.08, 0.05, 30.0)` | [0.05, 30.0] |

Единственный источник формул — `scripts/research/ecology/evo4_bridge_derivation_v0.py::derive_traits`; генератор обязан импортировать её, а не дублировать.

## 3. Алгоритм checksum (бит-в-бит совместимость с GDScript)

`traits_id` = `"plant-development/evo4-b0-derivation-v0/" + genome_id.replace("genome/", "genome-")`.

Payload = `"|".join` токенов строго в порядке:
`[SCHEMA, VERSION, traits_id, %.9f(max_height_m), %.9f(internode_length_m), %.9f(apical_dominance), %.9f(branch_probability), %.9f(branch_angle_deg), %.9f(branch_length_ratio), str(branching_depth:int), %.9f(crown_spread_m)]`,
где `SCHEMA = distributed_world_simulator.ecology.plant_development_traits.v1`, `VERSION = 1.0.0`, формат float — `%.9f`. Checksum = lowercase hex SHA-256 от UTF-8 payload. Эквивалент `plant_development_traits_v1.compute_checksum` (Godot `sha256_text`).

## 4. IndividualSeed (демо-идентичность)

`individual_seed_demo = int(sha256(f"{genome_checksum}|{bake_id}|{lineage_id}|EVO4_B0_DEMO|{cohort_index}")[:15], 16)` — < 2^60, безопасно для int64 Godot. Это демо-идентичность материализации, НЕ наследственное событие PH0/PH4.

## 5. Артефакт-расширение

Генератор `scripts/research/ecology/evo4_bridge_catalog_extender_v1.py` выпускает `validation/ecology/evo4_b1_dev_traits_extended_catalog.v1.json`:

- верхний уровень: `{schema, version, derived_representation: true, entries, extension_provenance}`;
- каждая запись — копия записи источника + аддитивные блоки:
  - `development_traits` — ровно 12 полей PH0 (schema, version, traits_id, 8 traits, checksum), пригодно для прямой валидации `Traits.validate`;
  - `evo4_bridge` — `{derivation_rule_id, individual_seed_demo, source_genome_checksum}` (связка с геномом);
- `extension_provenance`: `{schema: …evo4_b1_catalog_extension.v1, version, source_catalog_schema, source_catalog_hash, source_catalog_sha256, source_catalog_path, derivation_rule_id, generator, generator_version}`.

Детерминизм: без меток времени, случайности и environment-зависимых значений; повторный прогон fresh-process даёт байт-идентичный файл.
