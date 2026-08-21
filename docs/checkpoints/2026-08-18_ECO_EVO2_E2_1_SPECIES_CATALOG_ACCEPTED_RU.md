# ECO EVO2 / E2.1 — SpeciesCatalog Contract ACCEPTED

Статус: `ACCEPTED / RESEARCH_ONLY / EXACT ATTACHED GODOT / EQUIVALENT FRESH VERIFICATION`.

Ветка: `feature/eco-evolutionary-ecology`.

## Exact identities

```text
code-under-test
bf468942718df6b84ebd4c61a294987e8e63c607

acceptance source HEAD
c79e2d61e665689fe39621442f72171de5d2790f

acceptance validation carrier
3b392973fca60360016c4a303eed5b2229ef92b7
```

Validation:

`validation/ecology/eco-evo2-e2-1-species-catalog-validation.json`

## Parent evidence

```text
P2.7 lineage diagnostics
7e814c0d8bdff952f9b86579b95fe305212ec02017c2298437e2ba3e46d2babe

P3.8 deterministic ecosystem persistence
6132820a5c6597765b4f3abeeb8cf9fc9e6aaffb90ba83a1263997b17fc6f3a0
```

P2.7 остаётся research diagnostics; canonical taxonomy не объявляется.

## Verification result

Exact Godot:

```text
4.7.1.stable.double.custom_build.a13da4feb
SHA-256 bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7
```

Проверено:

```text
remote HEAD identity                    PASS
candidate->remote code/test immutability PASS
local branch identity                   PASS
exact executable Git blobs 6/6          PASS
Godot identity                          PASS
parser/preload                          PASS
acceptance test                         53/53 PASS
fresh process A                         PASS
fresh process B                         PASS
fresh-process logs byte-identical       PASS
```

Canonical outputs:

```text
aggregate_hash
aa23bc269738ace132fb1386ec01b339cc7fd82e1238223c1075b60dac5896ad

single_catalog_hash
b17f3c8bb17d71504aa683ca6d40cf25ab346d5a70432f8b0744566fd8c90f3a

multi_catalog_hash
ceba80d9f639b8b5042fd826bad23a5e83c7c3a7c79baeaad9397e70ffb9f474

alpha_research_species_id
eco-research-species/2164d8161e30ec9df8a54c47

fresh process log SHA-256
12c2d8819509e54dad6725e48cdb2cd881cf5d674632db1db268b3f7e4b5f13a
```

## Why equivalent verification is accepted

Предыдущий E2.1 validation gate прямо разрешал:

```text
full canonical branch runner
OR
equivalent fresh verification
```

Execution container не имеет сетевого доступа к GitHub и PowerShell runtime, поэтому `.ps1` буквально не выполнялся.

Вместо ослабления gate было выполнено эквивалентное доказательство:

1. remote HEAD отдельно подтверждён через GitHub;
2. diff `bf468... -> c79e2...` доказал отсутствие изменений E2.1 production/research code и acceptance test после code-under-test;
3. все исполняемые dependencies и test сверены по Git blob SHA с текущей GitHub-веткой;
4. собран fresh branch carrier `feature/eco-evolutionary-ecology`;
5. canonical acceptance GDScript выполнен на exact attached Godot double;
6. parser и два fresh-process запуска зелёные;
7. canonical hashes совпали с candidate evidence.

Это human-directed execution acceptance gate. Independent Reviewer PASS этим **не заявляется** и для E2.1 не подменяется.

## Frozen E2.1 contract

После acceptance замораживаются:

- `research_species_id` как research lineage identity;
- явный species concept `ECO_RESEARCH_LINEAGE_HYPOTHESIS_V1`;
- `canonical_species_declared = false`;
- stable identity по lineage, а не по текущему trait snapshot;
- strict source observation shape/type boundary;
- deterministic canonical entry ordering;
- deterministic entry/catalog hashes;
- explicit provenance;
- no global RNG consumption;
- no source state mutation.

E2.1 не разрешает canonical biological taxonomy и не предоставляет production authority.

## Decision

```text
E2.1 = ACCEPTED
E2.2 = AUTHORIZED
```

Следующий этап:

`ECO.EVO2 / E2.2 — Deterministic Evolution Bake Export`.
