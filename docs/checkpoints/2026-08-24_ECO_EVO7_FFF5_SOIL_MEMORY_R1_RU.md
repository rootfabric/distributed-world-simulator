# ECO.EVO7 FFF5 — Litter / Soil Memory R1

**Статус:** `STACKED IMPLEMENTATION CANDIDATE / BLOCKED ON FFF4 ACCEPTANCE`  
**Parent candidate:** FFF4 `853a33b787b6d64be4b0f211f90781d11d8419c4`.

## Реализовано

- additive `plant_environment_effect_v3`: litter/soil-binding активируются без переписывания v1/v2;
- `soil_legacy_field_v1`: slow organic-matter proxy с 4% decay/cycle, retention/nutrient/establishment derived bonuses, canonical effect ordering;
- `evo7_soil_memory_bridge_v1`: Experiment D — source stand создаёт legacy несколько cycles, source vegetation удаляется, затем один и тот же mutation stream отбирается на modified и pristine soil;
- изменённая почва влияет на moisture/nutrients/establishment opportunity, а не пишет в genome;
- никакого microbiome entity stack и никакой production soil authority.

## Ключевой causality gate

`past vegetation -> persisted research-derived soil state -> source plants removed -> identical descendant pool -> different selected descendants`.

Acceptance также требует deterministic replay, order invariance и >=2/3 multiseed direction.

## Pre-publish executable smoke

На Godot `4.7.1.stable.double.custom_build.a13da4feb` отдельно выполнен smoke `plant_environment_effect_v3 + soil_legacy_field_v1`: PASS; перестановка effect records не меняет state hash, repeated cycles увеличивают organic matter при учёте decay.

## Граница

FFF5 не считается принятым, пока FFF4 не получит exact-repository machine PASS + fresh independent Review/Verify. FFF6 может быть реализован stacked-кандидатом, но не может быть принят/слит поверх непринятого FFF5.