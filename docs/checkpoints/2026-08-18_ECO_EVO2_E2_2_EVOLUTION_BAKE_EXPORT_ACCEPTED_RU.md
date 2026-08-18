# ECO.EVO2 / E2.2 — Deterministic Evolution Bake Export — ACCEPTED

Статус: `ACCEPTED / RESEARCH_ONLY / EXACT ATTACHED GODOT EQUIVALENT FRESH VERIFICATION`.

Дата verification: `2026-08-18`.

Ветка: `feature/eco-evolutionary-ecology`.

## Exact identities

```text
E2.2 code-under-test
7cf98d67a4658644a6f2dde3e93e28a184638ec3

remote HEAD verified before acceptance write
4ddf7d275d10a6a84a3e414bfb0e76447cb2a890

acceptance validation carrier
92b20325845455e04cc1c02765c7d3f16fea1a84
```

Candidate-to-remote drift gate:

- 6 commits after code-under-test;
- only validation/control/docs files;
- no E2.2 implementation/test/runner changes;
- no production/runtime paths;
- no accepted E2.1/P2.8 source changes.

## Frozen executable blobs

```text
environment_sample_v1.gd
7ae8cc2534940ceb3c69879f8850467ba32fea8c

plant_genome_v1.gd
6d00dbb8286e9856bd5db8a8d7d4fd308a0b72bd

plant_recruitment_traits_v1.gd
6faeff9da9f7fa5a03e1df586de9cb29795d30de

plant_lineage_divergence_diagnostics_v1.gd
fdb7d4cbacc7dd575c665c66340a926f82f07483

plant_species_catalog_v1.gd
f1c706b6d915e6e709be2fcdd7e0fa8cb89fcbc2

plant_evolution_bake_export_v1.gd
6ed4abfa58c28a99fb1c28547d81e1a292756e10

eco_evo2_e2_2_evolution_bake_export_acceptance.gd
87a980543239b71b6a7fb5d7e2ecfcd2e89df195

RUN_ECO_EVO2_E2_2_TESTS.ps1
b2d55213ac19714fe3f603e7266c539ac43ab104
```

## Parent gates

```text
E2.1 SpeciesCatalog
status    ACCEPTED_EXACT_ATTACHED_GODOT_EQUIVALENT_FRESH_VERIFICATION
aggregate aa23bc269738ace132fb1386ec01b339cc7fd82e1238223c1075b60dac5896ad

P2.8 deterministic save/restart
status    ACCEPTED_EXACT_WINDOWS_CANONICAL
aggregate ba4e4bcef779764c86b20f1a76b452e0a2edcc88d351a1f9b4d2d41e10c420d6
```

## Fresh verification execution

PowerShell runtime в execution container отсутствует, поэтому literal `RUN_ECO_EVO2_E2_2_TESTS.ps1` не мог быть запущен как PowerShell process.

E2.2 validation contract прямо разрешал:

```text
full canonical branch runner
OR
 equivalent fresh verification
```

Был создан новый чистый carrier с exact branch name `feature/eco-evolutionary-ecology`. В него перенесены только frozen executable blobs, после чего их Git blob identities были повторно проверены.

Exact Godot:

```text
version
4.7.1.stable.double.custom_build.a13da4feb

binary SHA-256
bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7
```

Результат:

```text
branch identity                  PASS
exact executable blobs           PASS 8/8
E2.1 parent gate                 PASS
P2.8 parent gate                 PASS
parser/preload                   PASS / exit 0
Godot ERROR lines                0
fresh process A                  PASS / exit 0
fresh process B                  PASS / exit 0
assertions                       62 / 62 PASS
fresh-process logs               byte-identical
parser log SHA-256               39fde4591a5b4e0b04ce5153e2250cb1acf164a74c7a9335186d68f9edcccc3a
fresh-process log SHA-256        04a11281a398bf24a7880a95a01728a9a64bbac5c79e7a8aa6019ba918f329b2
```

Canonical outputs:

```text
aggregate_hash
56d4b8bfd3064ad37b720d5bff2bc98bb72b0ab7ad871877fc268d5e6df703ce

source_hash
c165964f710036287b9e8d310085a662d004b05eecc0c915ad1d3650a18dedb9

bake_hash
45496eb67aac5cc0a65babfeb0c49fa99616df17c2f7e8b9e8b95d04cb2b4e5b

catalog_hash
5fcd8b90135cd8af69defc4f4a5ea26ede422ff82b25a0995bf5c6b10a53f219
```

## Accepted E2.2 meaning

Frozen E2.2 contract now proves:

- typed canonical long-run lineage-history input boundary;
- deterministic persistence/retention policy;
- explicit `RECENT_LINEAGE`, `EXTINCT_AT_FINAL`, `TRANSIENT_PERSISTENCE`, `STALE_REPRESENTATIVE` rejection semantics;
- latest unambiguous representative observation selection;
- input-order independence;
- duplicate/ambiguous evidence fail-closed;
- no global RNG consumption;
- no caller source mutation;
- exact source evidence embedded into export;
- policy decisions re-derived during validation;
- expected E2.1 SpeciesCatalog rebuilt during validation;
- rehashed policy tamper rejection;
- no canonical taxonomy promotion;
- same/fresh-process determinism.

## Research boundary

Acceptance **не** означает:

- independent Reviewer PASS;
- canonical biological species taxonomy;
- production ecology authority;
- production persistence/transactions;
- что synthetic contract fixture является accepted real evolution bake result.

`independent_reviewer_claimed = false`.

Synthetic fixture остаётся только contract fixture. Следующий этап должен использовать frozen E2.2 artifact semantics для transfer proof, а не объявлять fixture полноценным результатом реального evolutionary producer.

## Decision

```text
ACCEPT_E2_2_AND_AUTHORIZE_E2_3
```

Следующий этап:

`ECO.EVO2 / E2.3 Frozen-Catalog Transfer`.
