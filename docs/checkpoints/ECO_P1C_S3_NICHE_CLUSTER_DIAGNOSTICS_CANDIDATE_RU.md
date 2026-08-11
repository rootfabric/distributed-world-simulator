# ECO.P1C-S3 — Niche/Cluster Diagnostics + Multi-seed Coexistence — CANDIDATE

## Статус

`LOCAL_FOCUSED_PASS / EXACT_WINDOWS_PENDING`.

S2 доказал динамическое coexistence множества founders. S3 отвечает на следующий вопрос: являются ли survivors несколькими различимыми ecological strategies или лишь множеством близких вариантов одного generalist.

## Диагностика

- используется exact P1C-S2 abundance dynamics: `5×5`, 20 founders, 12 cycles × 3 сезона;
- три heterogeneous founder seeds: `1138701`, `1138702`, `1138703`;
- один exact uniform-control для seed `1138701`;
- effective founder: global biomass share `>=1%`;
- восемь traits: height, growth, root depth, water preference/tolerance, shade tolerance, seed count, lifespan;
- deterministic 3-way k-means только как **анонимное post-hoc diagnostic partition**;
- cluster index не является species, biome role или canonical identity;
- separation измеряется silhouette;
- niche signal измеряется как `regional cluster biomass share / global cluster biomass share` по post-hoc DRY/WET/SHADED/SUNLIT quartiles.

## Local evidence

Heterogeneous seeds:

| Seed | effective >=1% | top biomass share | Shannon | silhouette | substantial clusters | niche-enriched clusters |
|---|---:|---:|---:|---:|---:|---:|
| 1138701 | 19 | 0.2413 | 2.5755 | 0.1668 | 3 | 3 |
| 1138702 | 18 | 0.1905 | 2.6126 | 0.1540 | 3 | 2 |
| 1138703 | 18 | 0.2153 | 2.4939 | 0.1327 | 3 | 3 |

Uniform control:

- trait-space clustering всё ещё существует (`silhouette ~0.2073`);
- но `niche_enriched_cluster_count = 0`;
- у всех трёх clusters `regional enrichment span = 0.0`.

Это важный negative control: само наличие геометрических кластеров в случайном founder pool не считается доказательством ecological niche. Нишей считается только environment-dependent abundance enrichment.

## Hashes

- aggregate `75512459aa4a7d97b7e9549842c41a5ebf4b5574575bac9fec3ee51fd92d44a9`;
- default `33de1af8e20e45eea88d9ddc20ee0664b6c53f20282995c593c1738e9105db2d`;
- alternate `960ddf64b554e096e966796e6d614b75dfe2455259502310d75f700995d946a6`;
- third `cfe5778cf188ce06b512ce77e35ec6675cdc65703b1c8f437dcaa70db93b1c92`;
- uniform `b7a93ccdf4af05d92d2324a89331200a6957ce1433688dbe9ce70ded5e9c96f9`.

Local tests:

- seed matrix: `64 + 63 + 63 + 64` assertions, `0 failures`;
- aggregate contract: `5/5`;
- fresh-process restart: `5/5`.

## Truth boundary

S3 не меняет P1A/P1B/P1C-S1/S2 truth, не создаёт species classes, biome rules, новый fitness score, mutation, migration, authority/network/persistence или presentation truth. Clustering не участвует в simulation feedback.

## После Windows PASS

Принять S3 и открыть `ECO.P1C-S4 — Competition Robustness and Aggregate Acceptance`: больше seeds/длиннее горизонт, fail classification и решение о принятии всего P1C.
