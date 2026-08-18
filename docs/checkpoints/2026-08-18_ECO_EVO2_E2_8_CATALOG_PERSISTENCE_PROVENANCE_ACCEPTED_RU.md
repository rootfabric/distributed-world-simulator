# ECO.EVO2 / E2.8 — Catalog Persistence & Provenance — ACCEPTED

Дата: 2026-08-18  
Ветка: `feature/eco-evolutionary-ecology`  
Статус: `ACCEPTED_EXPLICIT_EQUIVALENT_FRESH_BEHAVIORAL_VERIFICATION`  
Decision: `ACCEPT_E2_8_AND_AUTHORIZE_EVO2_FINAL`

## 1. Exact freeze

Accepted code-under-test:

`5790de059aaafbfc10434bb2d40124e3c1ceb361`

Предыдущий runner freeze `5c15c079fb6c8b5300e4da4137ef76987018ae11` superseded и не является accepted HEAD: в нём runner называл 10-file set transitive closure, хотя `environment_sample_v1.gd` уже не был transitive preload после compact full-catalog refactor. Исправление было runner-only; behavioral artifact не изменился.

От предыдущего durable E2.7 branch state `12504f7af82752a23f46f68735bc3f68948e61df` до accepted E2.8 freeze — 7 commits и ровно 8 E2.8 files; production/runtime paths не затронуты.

## 2. Что доказано

E2.8 переносит через durable research boundary **полный accepted E2.2 SpeciesCatalog**, а не облегченную species/genome projection.

Persisted identity включает:

- catalog schema/version/hash;
- deterministic bake id;
- canonical ordered entries;
- exact `research_species_id`;
- exact source lineage IDs и ancestry;
- frozen genome payload/checksum;
- recruitment traits/checksum;
- source observation hashes;
- entry hashes;
- accepted EVO2 provenance E2.1..E2.7;
- явный provenance fact, что E2.2 source — synthetic contract fixture и не выдаётся за real evolved result.

Full accepted catalog hash после независимой реконструкции и после fresh-process restore:

`5fcd8b90135cd8af69defc4f4a5ea26ede422ff82b25a0995bf5c6b10a53f219`

Bake id:

`eco-evo2-bake/ff406486cc83bb8217d66213`

## 3. Persistence format

Schema:

`distributed_world_simulator.ecology.evo2_catalog_persistence.v1`

Version: `1.0.0`  
Encoding: `GODOT_VARIANT_BINARY_CANONICAL_V1`  
Transport magic: `DWS-ECO-EVO2-E2.8-CATALOG-PERSISTENCE-V1`

Обычный JSON dump сознательно не использован: persistence contract должен сохранять typed Variant identity, включая различие `int/float/bool`. Canonical dictionaries сортируют keys до `var_to_bytes`; transport хранит SHA-256 binary payload и canonical Base64. Restore сначала проверяет UTF-8 envelope, schema/version/encoding, Base64 canonicality и binary SHA, затем decode, semantic validation и byte-exact reserialization.

Known compatible versions: пустой список. Поэтому никакая совместимость не выдумывается:

```text
CURRENT_VERSION      ACCEPT
KNOWN_COMPATIBLE     только если явно объявлен
UNKNOWN_NEWER        REJECT
UNDECLARED_OLDER     REJECT
MALFORMED            REJECT
WRONG_SCHEMA         REJECT
```

## 4. Exact executable artifacts

```text
accepted E2.2 catalog carrier
b77c3421325fa1264f590b0bd75c1c59621f667f

EVO2 provenance carrier
5602607fa3b63e79da28d8da52cb3ba5f61960c1

persistence codec
83f80afe9fd467f7718f487b70f6bf1a88521339

tamper support
227c57ff4f25c80dc3fa35e99f0e4fe791620eb7

acceptance test
8e0f0d2ba6eea03337f6559276da87cf5f689d4b

fresh writer
32f85fc1809af8c094227ecc702dbbc8e7e94608

fresh restore
5d7c698a8e30a6be9622ddd9c5c08f02feac351e

canonical runner
4e75eff15351ca3ba2c9229f8b7b39937c77834e
```

Exact transitive executable GDScript closure: **9/9 PASS**. В closure входят два accepted primitives (`plant_genome_v1.gd`, `plant_recruitment_traits_v1.gd`) и семь E2.8 GDScript artifacts. Runner не считается GDScript transitive preload.

## 5. Fresh verification

Exact engine:

```text
Godot 4.7.1.stable.double.custom_build.a13da4feb
SHA-256 bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7
```

Post-repair-freeze evidence:

```text
parser/preload                     PASS
parser ERROR lines                 0
parser log SHA-256                 39fde4591a5b4e0b04ce5153e2250cb1acf164a74c7a9335186d68f9edcccc3a

acceptance A                       PASS
acceptance B                       PASS
assertions                         74 / 74 PASS
ERROR lines                        0 / 0
acceptance logs                    byte-identical
acceptance log SHA-256             9c4e541105d1b6738231a6253ea522ebccc0846f552a30733744f0c34cd32505

writer A                           PASS
writer B                           PASS
writer ERROR lines                 0 / 0
writer logs                        byte-identical
writer log SHA-256                 6ab0f1aef6a05d9e3e51fc8595d512df39b7d3aeb436d547b595ea1c6c2c912a
persisted artifacts                byte-identical
artifact bytes                     10383
artifact SHA-256                   b31c863f8e1943e5778d56631f8c8ad75b95f3b9d3930a699f80fd07595d45d1

restore A                          PASS
restore B                          PASS
restore ERROR lines                0 / 0
restore logs                       byte-identical
restore log SHA-256                fe46af6ff410cc335cdb6801cfad59fe6715857aeae7f97b7039204558e78d03
restored semantic identity         exact
```

Frozen result hashes:

```text
aggregate    4182176c1cc8b6d609fefc7057b5ff5307c92f839682e76f6168841d60275061
content      3d7ca34560483e2a4d1eb1955c008eb1f05ab3603e3d358abbf4823b33554e2e
provenance   a3a2f53107cefc5c96d835bd93327864d45f31e55b123fcd2fe4053fd5495a15
transport    b31c863f8e1943e5778d56631f8c8ad75b95f3b9d3930a699f80fd07595d45d1
catalog      5fcd8b90135cd8af69defc4f4a5ea26ede422ff82b25a0995bf5c6b10a53f219
parent E2.7  eb3b30919114cb9971b7413f416a3ae07eb50aebe81801454aaa310d6e879c7d
```

## 6. Tamper resistance

Acceptance fail-closed отвергает:

- raw byte corruption до semantic decode;
- outer transport SHA corruption;
- content hash corruption;
- genome mutation даже после пересчёта genome checksum, entry hash, catalog hash, content hash и transport hash;
- species/lineage substitution после полного nested + outer rehash;
- EVO2 provenance parent substitution после provenance/content/transport rehash;
- лишнее/отсутствующее artifact field;
- лишнее SpeciesCatalog entry field;
- wrong internal schema;
- unknown future internal version;
- reordered canonical entries после rehash;
- accepted catalog identity substitution.

Serializer/build также не потребляет global RNG.

## 7. Governance boundary

Accepted claim:

`RESEARCH_ARTIFACT_PERSISTENCE_WITH_EXACT_FULL_SPECIES_CATALOG_AND_EVO2_PROVENANCE_IDENTITY`

Не заявляется:

```text
production save authority
production persistence ownership
distributed durability
canonical species taxonomy
world transaction semantics
independent Reviewer PASS
independent Verifier PASS
```

Canonical PowerShell runner создан, но в Linux carrier отсутствуют `pwsh/powershell`. Поэтому execution authority честно классифицирована как `EXPLICIT_EQUIVALENT_FRESH_BEHAVIORAL_EXECUTION`; canonical runner execution не заявляется.

## 8. Решение

**E2.8 ACCEPTED.**

Следующий formal checkpoint:

`ECO.EVO2/E2.FINAL — Unseen World Challenge`

Он **AUTHORIZED_NOT_STARTED**. EVO2 ещё не объявлен complete: финальное end-to-end доказательство должно использовать восстановленный persisted frozen SpeciesCatalog/provenance на hidden unseen world без rebake и без biome species table shortcut.
