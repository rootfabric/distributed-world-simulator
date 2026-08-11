# ECO.P1B-S1 — Deterministic Mutation, Inheritance and Lineage — ACCEPTED

## Решение

`ACCEPTED`.

Exact-Windows Godot `4.7.1.stable.double.custom_build.a13da4feb` подтвердил весь parent regression и новый inheritance kernel:

- P1A-S1 `109/109`;
- P1A-S2 `235/235`;
- P1A-S3 `208/208`;
- P1A-S4 `165/165`;
- P1B-S1 focused `5834/5834`;
- fresh-process replay `6/6`.

Fixed hashes:

- ancestor lineage `73621a2c49d6496bb89faef63a8350f2a76b553fd718fa88d1bc6b21b83a230f`;
- 256-sibling population `83a114cd712aacac42e0a1b4d74c0876a441fadb019f6640bfd44c921778ce84`;
- 160-generation chain `3792cf995265b622ab8817a973f0bd38aedab8ca34721ca9468178e6e1a35874`.

## Что доказано

- P1B стартует от одного ancestor.
- Genotype identity отделён от individual identity.
- Zero-mutation offspring наследует тот же genotype, но получает новый deterministic individual identity и parent pointer.
- Mutation stream детерминирован и restart-safe.
- Пять EXP-V2 traits исследуют как positive, так и negative directions.
- Все effective mutations остаются в biological ranges `PlantGenomeV1`.
- 160 поколений сохраняют корректную provenance chain и один ancestral lineage id.
- Никакие predefined species/biome roles, presentation, authority или network inputs в kernel не добавлены.

## Граница принятия

S1 доказывает только наследуемую variation и provenance. Он не доказывает local adaptation сам по себе.

Следующий шаг — `ECO.P1B-S2 Spatial Selection Baseline`: один и тот же mutation candidate pool должен быть предъявлен разным accepted P1A environments. Только environment/resource consequences имеют право решать, какие descendants переходят в следующее поколение.
