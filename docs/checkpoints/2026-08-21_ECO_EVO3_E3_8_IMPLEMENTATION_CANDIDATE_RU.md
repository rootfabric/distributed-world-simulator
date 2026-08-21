# ECO EVO3 E3.8 — IMPLEMENTATION CANDIDATE

Статус: `IMPLEMENTATION CANDIDATE / AWAITING FRESH INDEPENDENT REVIEW`.

E3.8 `Cross-Planet Generalization Matrix` реализован на базе точной принятой цепочки E3.1–E3.7 и persisted EVO2 SpeciesCatalog.

## Predeclared matrix (до результатов)

Контракт `config/ecology/eco-evo3-e3-8-cross-planet-matrix-contract.v1.json` фиксирует 6 семейств планет ДО компиляции:

| family | variation | spec |
|---|---|---|
| dry | SOIL_MOISTURE_MULTIPLIER | ×250000/1000000 |
| wet | SOIL_MOISTURE_MULTIPLIER | ×1500000/1000000 (clamp 1e6) |
| cold | TEMPERATURE_OFFSET_MILLI_C | −15000 |
| hot | TEMPERATURE_OFFSET_MILLI_C | +20000 |
| seasonal | DISTURBANCE_PRESSURE_MULTIPLIER | ×2000000/1000000 (clamp 1e6) |
| isolated | EDGE_CONTINUITY_MULTIPLIER | ×100000/1000000 |

## No-retuning proof

Матрица НЕ модифицирует принятые компиляторы: opportunity fields считаются неимпортированно-неизменённым билдером принятого E3.2 модуля, декомпозиции — принятым E3.3 билдером, решения колонизации — принятыми примитивами E3.4 core (`_trait_support_ppm`, `_dispersal_capacity_ppm`, `_establishment_score_ppm`, `_best_route`) с порогами принятого E3.4 контракта (`minimum_establishment_ppm=60000`, `minimum_edge_arrival_ppm=150000`). Каталог использован дословно (hash pin). SHA-256 переиспользованных модулей записаны в артефакт.

## Результаты матрицы

```text
dry      colonized=0/2  established_patches=0   -> LOST_REVERSAL x2, NO_COLONIZATION сохранён
wet      colonized=2/2  established_patches=22  -> PRESERVED_COLONIZED
cold     colonized=2/2  established_patches=22  -> PRESERVED (thermal context не fitness)
hot      colonized=2/2  established_patches=22  -> PRESERVED (thermal context не fitness)
seasonal colonized=1/2  established_patches=7   -> LOST_REVERSAL + PRESERVED
isolated colonized=2/2  established_patches=2   -> PRESERVED species-level, dispersal сжат
```

Инварианты: `six_families_exact`, `thermal_shortcut_absent` (cold/hot == baseline), `outcome_diversity_present` (LOST_REVERSAL в dry/seasonal), `null_outcome_valid`, `catalog_untouched`, `compiler_modules_reused_unmodified`.

## Authority

`RESEARCH_DERIVED_NON_AUTHORITATIVE`; `canonical_binding_resolved=false`; `production_binding_authorized=false`. Индивидуальные сущности запрещены; canonical species/time/environment ownership, history writes, forecast, network/persistence/transaction authority, asset scatter truth, XFER1 — все запрещены рекурсивной проверкой.

Capability boundary как в E3.7 после Repair R1: `_VerifiedMatrixInputs` / `_VerifiedGeneralizationMatrix`, финализация только через `serialize_planet_generalization_matrix` / `write_planet_generalization_matrix` с независимым rebuild из retained raw inputs; generic final-byte helper отсутствует; поверхность финализаторов проверяется регрессией.

## Точная идентичность сгенерированного артефакта

```text
path                validation/ecology/eco-evo3-e3-8-cross-planet-generalization-matrix.generated.json
bytes               9348
SHA-256             44de8474647483a6b18b6e5d88202358857f3b2b09171ae302b1c8497ea5b79c
Git blob            28edbe05d89daa219105fcddff20d5edaf6dd57f
provenance hash     3ede4a18fb0fa8b8895813452fe6ae4f62e633f6d7ea9188ab49ec18f6fd76be
matrix hash         707ee5bc4235ef2fcef917b8fcc825455440f7d1fa6511f5802a9a480479404e
tests               26/26
closure predicates  18/18
```

## Gate

Это implementer-side candidate evidence, а не Reviewer PASS. Требуются: fresh exact-head Closure на PR HEAD, fresh independent Reviewer, fresh independent Verifier, formal acceptance. E3.FINAL, XFER1 и production ECO остаются blocked/inactive.
