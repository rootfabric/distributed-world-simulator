# ECO.P1B — Local Adaptation Proof — ACCEPTED

## Решение

`ACCEPTED / 10 OF 10 GATE PASS`.

P1B доказал, что одна ancestral lineage без predefined species/biome roles воспроизводимо расходится по ecological traits под действием принятой P1A resource truth.

## Evidence chain

- S1: deterministic mutation/inheritance/lineage — Windows `5834/5834`, restart `6/6`;
- S2: spatial selection chambers — Windows `364/364`, restart `6/6`;
- S3: 49-patch regional population field — Windows `388/388`, restart `6/6`;
- S4: multi-seed/neutral/long-run robustness — Windows `86/86`, restart `5/5`.

Robustness mean correlations: water preference vs moisture `+0.900298`, root depth vs moisture `-0.538061`, shade tolerance vs sunlight `-0.421823`. Neutral control не воспроизводит эту структуру.

## Что доказано

1. Variation генерируется детерминированно и не направлена к заранее выбранной стратегии.
2. Selection использует только accepted P1A resource consequences.
3. С одинакового ancestor возникают regional trait distributions.
4. Spatial signal сильнее neutral mutation noise.
5. Феномен повторяется на нескольких seeds и не исчезает на более длинном run.
6. Traits не уходят в runaway/clamp optimum.

## Что НЕ доказано

P1B не доказывает coexistence нескольких стратегий в одном конкурентном сообществе, migration/biogeography, speciation или developmental morphology.

Следующий checkpoint: **ECO.P1C — Strategy Competition Proof**.
