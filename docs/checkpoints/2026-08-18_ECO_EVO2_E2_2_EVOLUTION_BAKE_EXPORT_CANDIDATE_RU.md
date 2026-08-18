# ECO.EVO2 / E2.2 — Deterministic Evolution Bake Export Candidate

Статус: `CANDIDATE / RESEARCH_ONLY / EXACT ATTACHED GODOT PASS / NOT_SELF_ACCEPTED`.

Ветка: `feature/eco-evolutionary-ecology`.

## 1. Exact candidate

Code-under-test HEAD:

`7cf98d67a4658644a6f2dde3e93e28a184638ec3`

Frozen parents:

- E2.1 SpeciesCatalog accepted aggregate: `aa23bc269738ace132fb1386ec01b339cc7fd82e1238223c1075b60dac5896ad`;
- P2.8 deterministic Plant World save/restart accepted aggregate: `ba4e4bcef779764c86b20f1a76b452e0a2edcc88d351a1f9b4d2d41e10c420d6`.

Executable blobs:

- `scripts/research/ecology/plant_evolution_bake_export_v1.gd` — `6ed4abfa58c28a99fb1c28547d81e1a292756e10`;
- `tests/research/ecology/eco_evo2_e2_2_evolution_bake_export_acceptance.gd` — `87a980543239b71b6a7fb5d7e2ecfcd2e89df195`;
- `RUN_ECO_EVO2_E2_2_TESTS.ps1` — `b2d55213ac19714fe3f603e7266c539ac43ab104`.

## 2. Что реализовано

E2.2 вводит fail-closed boundary между long-run evolutionary/lineage evidence и принятым E2.1 `SpeciesCatalog`.

Pipeline:

```text
long-run lineage histories
        ↓
canonical typed bake source
        ↓
retention / rejection policy
        ↓
latest unambiguous representative observations
        ↓
accepted E2.1 SpeciesCatalog.build(...)
        ↓
portable deterministic bake export
```

Source содержит validated P2.7-compatible lineage observations, yearly occupancy evidence, exact `source_run_hash`, canonical lineage ordering и deterministic `source_hash`.

## 3. Retention policy

Research-only policy revision: `ECO.EVO2-E2.2.1`.

```text
WINDOW_YEARS                         = 8
MIN_OCCUPIED_YEARS_IN_WINDOW         = 6
MIN_LINEAGE_AGE_YEARS                = 8
MAX_REPRESENTATIVE_STALENESS_YEARS   = 2
```

Lineage retained только если:

1. возраст lineage не меньше 8 лет;
2. она присутствует в final year;
3. occupied минимум 6 из последних 8 лет;
4. latest representative observation не старше 2 лет.

Explicit rejection reasons:

- `RECENT_LINEAGE`;
- `EXTINCT_AT_FINAL`;
- `TRANSIENT_PERSISTENCE`;
- `STALE_REPRESENTATIVE`.

Эти thresholds — **export policy**, а не biological species definition.

## 4. Species semantics

E2.2 не вводит clustering и не объявляет каноническую taxonomy.

Одна retained lineage hypothesis передаётся в E2.1 и получает уже определённый E2.1 `research_species_id`.

Mutation event не считается новым видом автоматически. Существующий mutation kernel сохраняет lineage identity и поэтому не используется как shortcut `mutation -> species`.

## 5. Integrity hardening

Во время implementer review был найден ранний integrity defect:

`E2_2_INTEGRITY_001_RECOMPUTED_SELECTION_TAMPER`.

Проблема: validator ранней формы мог проверить внутренне пересчитанные selection hashes, не доказывая заново, что selection действительно следует из source evidence.

Repair до candidate freeze:

- export теперь embeds exact validated source;
- `validate_export()` заново валидирует source;
- заново вычисляет selected/rejected decisions из source;
- требует точного совпадения derived decisions с export claims;
- заново строит expected E2.1 SpeciesCatalog;
- требует exact equality expected catalog и supplied catalog.

Acceptance test проверяет tamper даже при recomputed `selection_hash` и `bake_hash`.

## 6. Exact attached Godot evidence

Godot:

`4.7.1.stable.double.custom_build.a13da4feb`

Binary SHA-256:

`bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7`

Результат после integrity repair:

```text
parser/preload                    PASS
fresh process A                   PASS
fresh process B                   PASS
assertions                        62 / 62 PASS
fresh-process logs                byte-identical
```

Canonical evidence:

```text
aggregate_hash = 56d4b8bfd3064ad37b720d5bff2bc98bb72b0ab7ad871877fc268d5e6df703ce
source_hash    = c165964f710036287b9e8d310085a662d004b05eecc0c915ad1d3650a18dedb9
bake_hash      = 45496eb67aac5cc0a65babfeb0c49fa99616df17c2f7e8b9e8b95d04cb2b4e5b
catalog_hash   = 5fcd8b90135cd8af69defc4f4a5ea26ede422ff82b25a0995bf5c6b10a53f219
selected       = 2
rejected       = 4
```

Fresh-process log SHA-256:

`04a11281a398bf24a7880a95a01728a9a64bbac5c79e7a8aa6019ba918f329b2`

Parser/check log SHA-256:

`39fde4591a5b4e0b04ce5153e2250cb1acf164a74c7a9335186d68f9edcccc3a`

## 7. Exact dependency identity

Minimal exact-blob execution used:

```text
environment_sample_v1.gd                    7ae8cc2534940ceb3c69879f8850467ba32fea8c
plant_genome_v1.gd                           6d00dbb8286e9856bd5db8a8d7d4fd308a0b72bd
plant_recruitment_traits_v1.gd               6faeff9da9f7fa5a03e1df586de9cb29795d30de
plant_lineage_divergence_diagnostics_v1.gd   fdb7d4cbacc7dd575c665c66340a926f82f07483
plant_species_catalog_v1.gd                  f1c706b6d915e6e709be2fcdd7e0fa8cb89fcbc2
plant_evolution_bake_export_v1.gd            6ed4abfa58c28a99fb1c28547d81e1a292756e10
eco_evo2_e2_2_*_acceptance.gd                87a980543239b71b6a7fb5d7e2ecfcd2e89df195
```

После публикации GitHub blobs implementation/test/runner были повторно сверены и совпали с exact tested files.

## 8. Fixture boundary

Acceptance source run hash:

`d44a160531d7f49cd0d0018a1fa8cb55d6be8ebf8157e5cb555232b8dd0fb337`

Это **synthetic contract fixture provenance**. Он не выдается за accepted evolution result.

Причина отдельного typed source boundary: accepted P2.8 доказывает long-run deterministic Plant World persistence, но текущий accepted upstream не публикует canonical collection multi-lineage evolved observations, пригодную напрямую для E2.2 bake.

E2.2 определяет контракт, который такой producer обязан выдавать позднее.

## 9. Scope proof

Diff от входного E2.2 base HEAD

`bdd0bac6bfd109b81e1023b0106afb719a3579df`

до code-under-test HEAD содержит только три файла:

- E2.2 implementation;
- E2.2 acceptance test;
- E2.2 runner.

Production/runtime paths не изменены. Accepted E2.1/P2.8 source files не изменены.

## 10. Почему это ещё не ACCEPTED

Implementer evidence не заменяет свежую формальную verification роль.

Execution container не содержит полноценный repository checkout и PowerShell runtime, поэтому `RUN_ECO_EVO2_E2_2_TESTS.ps1` здесь end-to-end не исполнялся. Вместо этого exact GitHub blobs были выполнены напрямую exact Godot double в fresh minimal project.

Поэтому текущий verdict:

`CANDIDATE_EXACT_ATTACHED_GODOT_PASS_FULL_BRANCH_RUNNER_PENDING`.

Нельзя объявлять independent Reviewer PASS.

Нельзя открывать E2.3 по implementer evidence.

## 11. Следующий формальный gate

Запустить на canonical branch checkout:

`RUN_ECO_EVO2_E2_2_TESTS.ps1`

или эквивалентную fresh verification с exact blob identity и exact Godot.

Если gate GREEN:

```text
freeze E2.2
        ↓
ACCEPT E2.2
        ↓
OPEN E2.3 Frozen-Catalog Transfer
```
