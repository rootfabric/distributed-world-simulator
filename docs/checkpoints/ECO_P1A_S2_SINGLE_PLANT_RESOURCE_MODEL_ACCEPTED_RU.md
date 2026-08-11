# ECO.P1A-S2 — Single-Plant Resource Model — ACCEPTED

## Решение

`ECO.P1A-S2` принят как research-only fixed-genome resource baseline.

Он доказывает, что один и тот же plant genome на принятой S1 environment truth получает разные outcomes из явного resource/cost balance, а не из biome-specific placement или скрытой magic fitness-функции.

## Реализовано

- `PlantGenomeV1` с фиксированными traits;
- `PlantResourceModelV1` с явными light/water/nutrient/temperature responses;
- costs: maintenance, roots, structure, growth, reproduction;
- water-stress, flood и density penalties;
- dominant limiting factor;
- viability class;
- `SinglePlantPatchSimulatorV1` с bounded 120-season biomass simulation.

В S2 нет mutation, natural selection, нескольких species или presentation-owned truth.

## Accepted evidence

Exact Windows worktree:

`C:\Godot\lunar-world-eco-evolutionary-ecology`

Engine:

`Godot 4.7.1.stable.double.custom_build.a13da4feb`

Результат:

- parent S1: `109 assertions, 0 failures`;
- S2: `235 assertions, 0 failures`;
- accepted environment hash: `b862c4fc529b5fd8229355c4c38b96a429e4ef1d902d6dd86b27860d8ce51af7`;
- accepted simulation hash: `618ec5c188fcb8b7c27a1e95147fcb9c9646eb6448c68a57a90cd525d5a9492c`.

Windows результат совпал с предварительным Linux focused evidence и опубликованными blob hashes.

## Наблюдаемый ecological result

Один genome создаёт одновременно:

- favourable зоны;
- marginal зону;
- unsustainable зоны;
- разные dominant limiting factors.

В частности, wet lowland может быть непригоден несмотря на высокую moisture из-за excess-water/flood stress.

## Root-depth trade-off

Глубокие корни:

- улучшают dry-ridge response относительно shallow roots;
- имеют super-linear cost;
- становятся менее выгодными на уже влажном floodplain;
- при экстремальной глубине могут ухудшить итоговый net balance.

Тем самым S2 показывает первый реальный trait trade-off, пригодный для будущей selection/evolution.

## Handoff

`ECO.P1A-S2 ACCEPTED -> ECO.P1A-S3 Diagnostic Visual Lab + Controlled Trait Probes`.

S3 должен только визуализировать и диагностировать принятую S1/S2 truth-модель; он не имеет права переносить ecological equations в presentation-код.
