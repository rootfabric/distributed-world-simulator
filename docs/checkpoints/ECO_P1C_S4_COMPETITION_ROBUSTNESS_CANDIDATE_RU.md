# ECO.P1C-S4 — Competition Robustness + Aggregate Acceptance — CANDIDATE

## Статус

`LOCAL_FOCUSED_PASS / EXACT_WINDOWS_PENDING`.

S4 — финальный falsification gate для `ECO.P1C`. Он не добавляет новую biology-механику, а пытается сломать уже полученное доказательство coexistence на большем числе seeds и более длинном горизонте.

## Матрица

- `5×5`, 20 unlabeled founders;
- шесть heterogeneous seeds `1138701..1138706`;
- `18` abundance cycles × 3 сезона;
- uniform negative control на том же seed `1138701`;
- deep-horizon run: `24` cycles;
- accepted S2 abundance dynamics + accepted S3 post-hoc niche diagnostics;
- mutation/migration/species/biome rules отсутствуют.

## Явные failure classes

- `GLOBAL_TAKEOVER`;
- `DIVERSITY_COLLAPSE`;
- `CLUSTER_COLLAPSE`;
- `FALSE_NICHE_UNIFORM`;
- `RUNAWAY_TRAIT`;
- `REPLAY_DIVERGENCE`.

Uniform world намеренно не обязан сохранять heterogeneous diversity: его роль — negative control для false niche. Поэтому снижение diversity в uniform не считается ошибкой; ошибкой было бы появление region-dependent enrichment при одинаковой среде.

## Local evidence

По шести heterogeneous seeds после 18 cycles:

- minimum effective founders `>=1%`: **15/20**;
- maximum top-founder global biomass share: **0.278322**;
- minimum Shannon: **2.296101**;
- minimum substantial clusters: **3**;
- minimum niche-enriched clusters: **2**.

Uniform control:

- niche-enriched clusters: `0`;
- maximum regional enrichment span: `0.0`.

Deep horizon, 24 cycles:

- effective founders `>=1%`: `15/20`;
- top share: `0.278431`;
- Shannon: `2.335302`;
- substantial clusters: `3`;
- niche-enriched clusters: `3`.

## Determinism

- aggregate `0ca70eab1e5db569a45e244a6cd2f378469197472de2a7d35f8a4a15db870112`;
- default case `431c4b6c0683b692c9fe88fbc912f49c3659db122c8fdf2715f525ea712dc43b`;
- uniform case `8f27fb89d87d7b92911efcb80ae461d2d0f32ff169ed8f3efbdf73a296d67d47`;
- deep horizon `ca49a238f82303ac6ad7e36d10f849baff07442873ab3b20c22d2d32f9f34411`.

Local tests:

- heterogeneous: `6 × 30`, 0 failures;
- uniform: `27`, 0 failures;
- deep horizon: `30`, 0 failures;
- aggregate: `15/15`;
- fresh-process restart: `6/6`.

## После Windows PASS

Можно принять `P1C-S4`, собрать aggregate acceptance всего `ECO.P1C Strategy Competition Proof` и закрыть `ECO.P1` plant strategy proof. Следующая research-развилка: `ECO.P2` history/disturbance/succession или параллельный уже открытый `ECO.PH` developmental phenotype track.
