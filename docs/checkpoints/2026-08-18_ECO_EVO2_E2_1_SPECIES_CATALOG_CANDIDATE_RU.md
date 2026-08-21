# ECO EVO2 / E2.1 — SpeciesCatalog Contract Candidate

Статус: `CANDIDATE / RESEARCH_ONLY / EXACT ATTACHED GODOT PASS / NOT_SELF_ACCEPTED`.

Ветка: `feature/eco-evolutionary-ecology`.

Exact code-under-test HEAD:

`bf468942718df6b84ebd4c61a294987e8e63c607`

Initial validation carrier commit:

`74af3b2a8a7cc30b38b034513836b07ad60d50a4`

Validation:

`validation/ecology/eco-evo2-e2-1-species-catalog-validation.json`

## 1. Что закрыто до E2.1

EVO1/P2.8 уже имеет canonical acceptance и `EVO1 COMPLETE`.

P3.1..P3.8 уже accepted как research route; P3.8 aggregate:

`6132820a5c6597765b4f3abeeb8cf9fc9e6aaffb90ba83a1263997b17fc6f3a0`

Lineage diagnostics parent P2.7 отдельно frozen:

`7e814c0d8bdff952f9b86579b95fe305212ec02017c2298437e2ba3e46d2babe`

P2.7 прямо декларирует research detection policy и `canonical_species_declared = false`.

P4 branch lifecycle является отдельной production-integration governance-линейкой и не считается global/main acceptance до independent review/verifier и main-owned promotion.

## 2. Новый контракт

Добавлен:

`scripts/research/ecology/plant_species_catalog_v1.gd`

Git blob SHA:

`f1c706b6d915e6e709be2fcdd7e0fa8cb89fcbc2`

Контракт вводит только research identity:

`research_species_id`

Он не является canonical biological taxonomy.

Stable identity строится по:

```text
schema
+ version
+ species concept
+ lineage_id
```

Поэтому изменение traits у той же lineage сохраняет identity, но меняет `entry_hash` и `catalog_hash`.

Catalog entry сохраняет:

- lineage identity;
- full ancestry;
- immediate parent;
- split year;
- validated genome + checksum;
- validated recruitment traits + checksum;
- canonical observed patch range prior;
- source P2.7 observation hash;
- explicit `canonical_species_declared = false`.

Catalog сохраняет:

- schema/version/species concept;
- accepted P2.7 lineage parent identity;
- bake id;
- source run provenance digest;
- canonical species-id order;
- deterministic catalog hash;
- explicit noncanonical taxonomy status.

## 3. Fail-closed hardening

Во время implementation review найден inherited compatibility gap P2.7:

- legacy P2.7 `validate_observation()` может принять extra source field, потому что observation hash его не включает;
- `split_year` в legacy validator проходит через `int(...)`, поэтому эквивалентный `float` Variant может сохранить тот же observation hash.

E2.1 не наследует эту мягкость.

Перед P2.7 semantic validation он требует exact source observation field set и exact Variant types. Acceptance test специально доказывает обе границы:

```text
P2.7 accepts legacy extra field
E2.1 rejects it

P2.7 accepts float split-year Variant with same canonical integer meaning
E2.1 rejects it
```

Это локальное усиление нового EVO2 boundary; accepted P2.7 source не изменялся.

## 4. Acceptance test

Добавлен:

`tests/research/ecology/eco_evo2_e2_1_species_catalog_acceptance.gd`

Git blob SHA:

`4df82431d3ce20fd48610e1c250aafb9f0afbaac`

Runner:

`RUN_ECO_EVO2_E2_1_TESTS.ps1`

Runner Git blob SHA:

`726f56142d82106ecb1e39d32879f83c9542a46c`

Runner fail-closed проверяет два разных parent evidence:

```text
P2.7 lineage diagnostics aggregate
7e814c0d8bdff952f9b86579b95fe305212ec02017c2298437e2ba3e46d2babe

P3.8 persistent ecosystem aggregate
6132820a5c6597765b4f3abeeb8cf9fc9e6aaffb90ba83a1263997b17fc6f3a0
```

Они не смешиваются в одну ancestry identity.

## 5. Exact attached Godot evidence

Binary:

`4.7.1.stable.double.custom_build.a13da4feb`

SHA-256:

`bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7`

Для исполнения был собран minimal `res://` project из exact GitHub blobs. Все исполняемые dependencies были сверены через Git blob SHA:

```text
PlantGenome
6d00dbb8286e9856bd5db8a8d7d4fd308a0b72bd

RecruitmentTraits
6faeff9da9f7fa5a03e1df586de9cb29795d30de

EnvironmentSample
7ae8cc2534940ceb3c69879f8850467ba32fea8c

P2.7 DivergenceDiagnostics
fdb7d4cbacc7dd575c665c66340a926f82f07483

E2.1 SpeciesCatalog
f1c706b6d915e6e709be2fcdd7e0fa8cb89fcbc2

E2.1 acceptance test
4df82431d3ce20fd48610e1c250aafb9f0afbaac
```

То есть parser/runtime запускал именно текущий GitHub-код этих файлов, а не переписанные test doubles.

Результат:

```text
parser/preload: PASS
fresh process A: PASS
fresh process B: PASS
53 / 53 assertions PASS
fresh-process logs byte-identical
```

Canonical candidate outputs:

```text
aggregate_hash = aa23bc269738ace132fb1386ec01b339cc7fd82e1238223c1075b60dac5896ad
single_catalog_hash = b17f3c8bb17d71504aa683ca6d40cf25ab346d5a70432f8b0744566fd8c90f3a
multi_catalog_hash = ceba80d9f639b8b5042fd826bad23a5e83c7c3a7c79baeaad9397e70ffb9f474
alpha_research_species_id = eco-research-species/2164d8161e30ec9df8a54c47
```

Дополнительный exact-dependency integration probe дал `18 / 18 PASS` и byte-identical two-process replay.

## 6. Что это НЕ доказывает

В execution-контейнере нет полного Git checkout ветки и нет PowerShell runtime, поэтому сам `RUN_ECO_EVO2_E2_1_TESTS.ps1` здесь не был выполнен end-to-end.

Следовательно:

```text
E2.1 = STRONG CANDIDATE
E2.1 != FORMALLY SELF-ACCEPTED
E2.2 != AUTHORIZED YET
```

Также E2.1 не доказывает:

- deterministic lineage selection из long-run evolution — это E2.2;
- transfer в unseen environment — E2.3;
- persistence/JSON codec — E2.8;
- canonical species taxonomy;
- production authority.

## 7. Формальный следующий gate

В canonical worktree:

```powershell
cd C:\Godot\lunar-world-eco-evolutionary-ecology

git pull

$Godot = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"

.\RUN_ECO_EVO2_E2_1_TESTS.ps1 -GodotPath $Godot
```

При exact PASS можно frozen-accept E2.1 и открыть:

`ECO.EVO2 / E2.2 — Deterministic Evolution Bake Export`.
