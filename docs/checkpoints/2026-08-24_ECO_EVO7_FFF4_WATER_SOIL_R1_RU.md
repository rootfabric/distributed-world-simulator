# ECO.EVO7 FFF4 — Water + Soil Texture Feedback R1

**Статус:** `IMPLEMENTATION CANDIDATE / SEPARATE CHECKPOINT / NOT FFF5`  
**База:** FFF3 truth-freeze carrier `47cd668db147a790305917858ccdb87007893393`; immutable scientific subject `e33c7296...`.

## Реализовано

- `plant_environment_effect_v2.gd`: additive successor; shade + water uptake + evaporation suppression активны, litter/soil-binding всё ещё fail-closed zero;
- `soil_water_field_v1.gd`: sand/loam/clay research selector, bounded retention/evaporation, canopy evaporation suppression, root depth/spread/allocation access, proportional deterministic uptake;
- структурные инварианты: `Σ uptake <= water available after evaporation`, `water_after >= 0`, no water creation, canonical-order hashes;
- `evo7_water_soil_feedback_bridge_v1.gd`: общий mutation pool, затем scenario-specific water field → realized environment → functional fitness → deterministic selection;
- dry-sand и mesic-loam отличаются только environmental/feedback surface, hardcoded TREE/BUSH/GRASS archetypes отсутствуют;
- FFF4 policy усиливает sampling (`morphology_probability=0.50`, genome mutation probability `0.50`, root depth step `0.45`) через существующую единственную lineage authority; отдельного mutator нет.

## Acceptance

`RUN_ECO_EVO7_FFF4_TESTS.ps1` проверяет FFF3 aggregate baseline (если не `-SkipBaseline`) и FFF4.

FFF4 gate требует:

- G8 water conservation/bounds;
- shade reduces bare-soil evaporation separately from transpiration;
- root-heavy phenotype получает больший доступ при дефиците;
- sand retains less than loam, clay more than loam;
- order-invariant field/effect hashes;
- common generation-one mutation pool;
- dry-sand vs mesic-loam different selected descendants;
- dry-sand lower LAI + root-heavier strategy;
- 3-seed robustness: направление проходит минимум 2/3;
- FFF3 `plant_environment_effect.v1` byte semantics не расширяются задним числом.

## Локальная pre-publish проверка ядра

На предоставленном Godot `4.7.1.stable.double.custom_build.a13da4feb` отдельно прогнан executable smoke `soil_water_field_v1 + plant_environment_effect_v2`: PASS, включая conservation, order invariance и преимущество deep/root-heavy доступа в dry-sand. Полный repository runner требует exact repository checkout/CI и не подменяется этим smoke.

## Граница

FFF5 отсутствует в этом checkpoint. Ни litter, ни organic-matter memory, ни establishment legacy не активированы. Следующий checkpoint может стартовать только после FFF4 machine evidence и независимого review/verification.