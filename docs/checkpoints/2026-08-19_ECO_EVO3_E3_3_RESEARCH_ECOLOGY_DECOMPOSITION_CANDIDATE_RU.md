# ECO EVO3 E3.3 — Research Ecology Decomposition — Candidate

Дата: 2026-08-19  
Статус: `RESEARCH_ONLY / IMPLEMENTED / EXACT-PUBLISHED VERIFIED / AWAITING FRESH INDEPENDENT REVIEW`.

E3.3 **не принят** этим checkpoint. E3.4 остаётся `BLOCKED` до отдельного fresh independent PASS, merge/acceptance E3.3 и последующего canonical authorization roll-forward.

## 1. Родительская граница

Canonical ECO frontier, от которого начат E3.3:

`768b683f0dfb4973e0fe32934dd56183ba0a0d83`

На этой точке machine roadmap уже фиксирует:

```text
E3.2 = ACCEPTED
E3.3 = AUTHORIZED_NOT_STARTED
E3.4 = BLOCKED
```

Accepted E3.2 identities:

```text
reviewed HEAD      578981af36c2fe101925db024e6b7747c99806ab
executable freeze  f276a5b29a39a00ae15c866a310b20f3ad9fe9c8
merge commit       83f35d7abe2ebdea3e5afe175833817ad631c5e6
aggregate          ef0ed137bf8d2862f4c9cfacee0792dba8079e539daa4bfb7322d7d5da8afc9c
field provenance   9be81517eaf0c28503291c5595c0790232b8f88c7ffa9ced2e886ec1f8597aa4
opportunity field  acba61638f8128b667880f2bd391ab73f6175d0899656bba92657d578d48203c
artifact SHA-256   59a0af5e40cae5c8a91e487da158edadfd4e127a0390ebe856f78f2365a066ff
```

## 2. Exact E3.3 executable freeze

После обнаруженного до-freeze publication-format mismatch runner был перепривязан к **реальному опубликованному** schema blob и повторно выполнен против exact published closure.

Валидный executable freeze:

`527e2dbef1ae4462e5b9e682b002408057930970`

На нём ровно шесть E3.3 executable/input carrier files:

```text
contract
  config/ecology/eco-evo3-e3-3-research-ecology-decomposition-contract.v1.json
  blob 784cc3aef012a3647bf8010436ff2dac6f6446f4

accepted E3.2 field materialization
  config/ecology/accepted_inputs/e3_2_accepted_ecological_opportunity_field.v1.json
  blob 68e601958b1206235729aceb40843cd8666840aa

Draft 2020-12 schema
  config/ecology/eco-evo3-e3-3-research-ecology-decomposition.schema.v1.json
  blob 80454d5ba92553b58f598a237bf3b7815773ad33

implementation
  scripts/research/ecology/research_ecology_decomposition_v1.py
  blob 02fbc95fe94f51b09970b1d17c4a629c692f500d

tests
  tests/research/ecology/test_eco_evo3_e3_3_research_ecology_decomposition.py
  blob 9268abdbb96231f24bcbaab7d4692371e5e9dbe8
  60 tests

runner
  RUN_ECO_EVO3_E3_3_TESTS.py
  blob 2572abc247f6832238f9c42f4ac261592e53f4b8
```

## 3. Научная семантика E3.3

E3.3 потребляет **только exact accepted E3.2 opportunity field**.

Прямые входы из E3.1 snapshot, raw fixture или candidate alias запрещены.

Декомпозиция не вводит biome/species taxonomy. Она строит research-only spatial graph:

```text
12 accepted E3.2 samples
    ↓
12 research patches
    ↓
2 nearest neighbours per patch
    ↓
mutual-neighbour undirected edges
    ↓
connected components
    ↓
research ecology regions
```

Фиксированные правила:

```text
patch model       ONE_RESEARCH_PATCH_PER_ACCEPTED_E3_2_SAMPLE
patch order       lexicographic stable_spatial_key
spatial metric    wrapped latitude/longitude microdegree squared distance
neighbor count    2
neighbor order    distance, then stable_spatial_key
edge rule         edge exists only for mutual neighbour selection
continuity        1,000,000 - floor(mean absolute opportunity-vector delta)
region rule       connected components of mutual-neighbour graph
```

Species identity и biome label не участвуют в partitioning.

## 4. Exact deterministic result

Получен следующий decomposition result:

```text
patch_count                    12
edge_count                     10
region_count                    2
singleton_region_count          1
largest_region_patch_count     11
main_region_mean_continuity 914200 ppm
```

Один component содержит `cell-01..cell-11`; `cell-12` остаётся отдельным singleton research region по фиксированной mutual-neighbour topology.

Frozen hashes:

```text
contract hash
593b1889198021e2fcdae0c3746bdbe771d606427f07a7ccfc7c8a530cebec9f

decomposition provenance
76cf3fac25f7c7f52309d9c38befb3c50321e652eacb3a58731473646d680e02

decomposition hash
9736ec70f844c930f8e160a4f08ae8e0aae1cce6f73fbf106499bea15b15a51a

decomposition artifact SHA-256
cab0ec65d66f68f097c07b686e5e87ba998dfe39a9b587a3f945b10d0ac2029a

generated artifact Git blob
9915bc13b0e81533fdc99ffe5707d0d60ba58eda

evidence aggregate
148b627b094bc71574a21043627bea859e05716e6cd3d09d57f94111a51cb837
```

Generated candidate artifact:

`config/ecology/accepted_inputs/e3_3_candidate_research_ecology_decomposition.v1.json`

## 5. Verification

Exact-published direct canonical Python verification:

```text
Python                    3.13.5
jsonschema                4.26.0
py_compile                PASS
semantic tests            60/60 PASS
Draft 2020-12 schema      PASS
exact dependency blobs    5/5 PASS
published closure         6 blobs including runner
fresh runner A            PASS
fresh runner B            PASS
runner logs identical     true
fresh builds              2/2 PASS
artifact bytes identical  true
```

Runner log SHA-256:

`b09c7b690e142b6676614cc01abcccf804e750c16d6d0e6a5ce232d760d1ab6c`

Fresh decomposition artifact SHA-256:

`cab0ec65d66f68f097c07b686e5e87ba998dfe39a9b587a3f945b10d0ac2029a`

## 6. Negative gates

60-test suite подтверждает, среди прочего:

- E3.2 reviewed-head / merge / aggregate / field / artifact substitution rejected;
- E3.0 architecture substitution rejected;
- E3.1 direct input, raw fixture и candidate alias bypass запрещены;
- neighbor count нельзя target-tune после contract rehash;
- wrapped-longitude metric фиксирован;
- exact patch/edge/region topology пересчитывается;
- source semantic mutation отвергается даже после rehash;
- source/output authority и canonical-binding promotion отвергаются;
- species partition, biome label и canonical SD injection отвергаются после full rehash;
- duplicate patch, edge drop/continuity tamper и region partition tamper отвергаются после full rehash;
- published Draft 2020-12 schema принимает exact output и запрещает unexpected patch properties;
- global RNG отсутствует;
- `--snapshot` / `--fixture` CLI bypass отсутствует; вход только через explicit `--accepted-field`.

## 7. Authority boundary

Все output identities имеют research namespace:

```text
eco-evo3/e3.3/patch/...
eco-evo3/e3.3/edge/...
eco-evo3/e3.3/region/...
```

Они **не являются canonical SD domains**.

E3.3 не получает:

- canonical `G/ENV/MAT/WQ/SD/TF` ownership;
- population truth;
- species assignment или biome taxonomy;
- production persistence / transaction / network authority;
- production API binding.

`XFER1` остаётся blocked.

## 8. Post-freeze evidence boundary

Executable freeze:

`527e2dbef1ae4462e5b9e682b002408057930970`

Первый post-freeze evidence head:

`7f1d9b474794b642aad512d07d2b9af2c5bf83cc`

На нём после freeze добавлен ровно один generated artifact и **zero executable drift**.

Candidate validation затем добавлен commit:

`fa795a2994818b8ea38f2847c87d2c5672d0f818`

Validation path:

`validation/ecology/eco-evo3-e3-3-research-ecology-decomposition-validation.json`

Этот checkpoint также является только post-freeze documentation evidence и не меняет executable closure.

## 9. Следующий gate

Следующий легитимный шаг:

`FRESH INDEPENDENT CRITICAL REVIEW OF EXACT FINAL PR HEAD`.

До PASS и merge:

```text
E3.3 = CANDIDATE / NOT ACCEPTED
E3.4 = BLOCKED / NOT AUTHORIZED
```

Только последующее принятие E3.3 может открыть E3.4 `Causal Colonization Program Compiler`, который обязан потреблять accepted E3.3 decomposition + полный portable SpeciesCatalog и сохранять валидный null/no-colonization outcome.
