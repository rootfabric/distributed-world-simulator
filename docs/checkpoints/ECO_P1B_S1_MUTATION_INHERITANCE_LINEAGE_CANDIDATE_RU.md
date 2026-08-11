# ECO.P1B-S1 — Deterministic Mutation, Inheritance and Lineage — CANDIDATE

## Статус

`LOCAL_FOCUSED_PASS / EXACT_WINDOWS_PENDING`.

Это первый шаг после принятия ECO.P1A и первый код, где разрешена наследуемая genetic variation. Selection, spatial competition и species classes здесь намеренно отсутствуют.

## Главная граница

P1B начинается строго с **одного ancestor**. Controlled probes из S3 остаются только диагностическими эталонами и не используются как исходные виды.

Разделены два понятия:

- **genotype** — набор наследуемых ecological traits (`PlantGenome`);
- **individual** — конкретный потомок с `individual_id`, parent pointer и generation.

Если у offspring нет ни одной эффективной mutation, он наследует тот же genotype checksum/id, но остаётся новым individual. Это не позволяет искусственно раздувать genetic diversity простым размножением.

## Mutable traits P1B-S1

- `water_preference`;
- `root_depth_m`;
- `growth_rate`;
- `shade_tolerance`;
- `seed_dispersal_distance_m`.

Остальные P1A traits на этом шаге неизменяемы. Это соответствует EXP-V2 и сохраняет эксперимент достаточно узким для диагностики.

## Deterministic mutation

Mutation stream не использует mutable global RNG state. Для каждого offspring/trait deterministic значения выводятся из hash-контекста:

`revision + lineage + parent individual + generation + offspring index + mutation seed + policy + trait`.

Поэтому restart процесса не меняет результат.

Default policy:

- probability `0.42` на trait;
- water preference step `±0.08`;
- root depth step `±0.30 m`;
- growth rate step `±0.08`;
- shade tolerance step `±0.08`;
- seed dispersal step `±3 m`.

Mutation считается эффективной только если после clamp trait реально изменился. Все values проходят прежний `PlantGenomeV1.validate()`.

## Lineage/provenance

`PlantLineageRecordV1` хранит:

- `lineage_id`;
- `individual_id`;
- `parent_individual_id`;
- `generation`;
- `birth_index`;
- `mutation_seed`;
- parent/child genome checksums;
- mutation event hash;
- собственный checksum.

На P1B-S1 lineage split ещё не моделируется: все descendants исходного ancestor сохраняют один `lineage_id`. Это позволит позже отличать обычные mutations внутри lineage от настоящей proto-speciation в EXP-V7.

## Local evidence

Godot `4.7.1.stable.double.custom_build.a13da4feb`:

- P1A-S1: `109/109`;
- P1A-S2: `235/235`;
- P1A-S3: `208/208`;
- P1A-S4: `165/165`;
- P1B-S1 focused: `5834/5834`;
- P1B-S1 separate-process replay: `6/6`.

Fixed hashes:

- ancestor lineage: `73621a2c49d6496bb89faef63a8350f2a76b553fd718fa88d1bc6b21b83a230f`;
- 256-sibling population: `83a114cd712aacac42e0a1b4d74c0876a441fadb019f6640bfd44c921778ce84`;
- 160-generation chain: `3792cf995265b622ab8817a973f0bd38aedab8ca34721ca9468178e6e1a35874`.

В 256 siblings при default policy:

- 12 offspring сохранили ancestor genotype без mutation;
- 244 получили минимум одну эффективную mutation;
- каждый из пяти traits мутировал больше 100 раз;
- у каждого trait присутствуют и positive, и negative deltas.

Это ещё **не адаптация**. Это только доказательство, что материал для natural selection генерируется воспроизводимо и без встроенного направления к заранее выбранной стратегии.

## Gate

S1 принимается после exact-Windows runner с теми же P1A regressions и тремя P1B hashes.

После acceptance открывается:

`ECO.P1B-S2 — Spatial Selection Baseline`.

Там descendants впервые попадут в принятую P1A environment map, а reproductive success будет зависеть только от accepted resource consequences. Только после этого можно говорить о начале natural selection.
