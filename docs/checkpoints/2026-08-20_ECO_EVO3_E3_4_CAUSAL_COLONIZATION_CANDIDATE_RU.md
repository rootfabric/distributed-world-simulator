# ECO EVO3 E3.4 — Causal Colonization Program Compiler — CANDIDATE

Статус: `RESEARCH_ONLY / IMPLEMENTER_VERIFIED / NOT_ACCEPTED / AWAITING_FRESH_INDEPENDENT_REVIEW`.

## Основание

E3.4 построен от принятого E3.3:

```text
canonical E3.3 merge  ac47904147edaa7dc46c63c20e91fd4f3a580c13
reviewed E3.3 HEAD    7ae4c17d0cca0d37369b620481d000fdbc8545fc
E3.3 executable       527e2dbef1ae4462e5b9e682b002408057930970
E3.3 Project Control  32247214418 / #1003 — SUCCESS
E3.3 decomposition    9736ec70f844c930f8e160a4f08ae8e0aae1cce6f73fbf106499bea15b15a51a
```

FULL persisted EVO2 SpeciesCatalog восстановлен до старта E3.4 через exact E2.8 writer/restore путь и затем сохранён без удаления записей:

```text
catalog hash          5fcd8b90135cd8af69defc4f4a5ea26ede422ff82b25a0995bf5c6b10a53f219
entries               2/2
semantic artifact     99d6dbf87d1a459e2f73f13959dcb53d9b0b8be1519bb5352622202954cf7d1e
semantic Git blob     397ace0c6c7b204793b7663e7a89417d44ba3484
E2.8 transport        b31c863f8e1943e5778d56631f8c8ad75b95f3b9d3930a699f80fd07595d45d1
E2.8 bytes            10383
E2.FINAL              6daab256af3d1e7693c66a8afaad4d04fd1564c4376b9f3cd747a268a10c2250
historical ECO        f0e16195f1331f238bbacab2768e5d72ec01d1a3
```

Каталог не реконструировался вручную. Все записи входят в input manifest и species-independent source port. Отсев допускается только как результат causal dispersal/establishment.

## Exact executable freeze

`bfa47f20d903d224cd6858ed006a17b9f9a2550b`

Exact closure:

```text
contract       de38fbc06a2a733cfac52df5b0345f900f42f117
E3.3 binding   84660f5c60da2e7b9dcb9ace0d287321f303a94e
E3.3 artifact  9915bc13b0e81533fdc99ffe5707d0d60ba58eda
EVO2 catalog   397ace0c6c7b204793b7663e7a89417d44ba3484
schema         95991eb62d90690b351d7522805ada2695d82898
implementation 46f424608a9d4e9bf9119b3700c3ba75b24197bd
tests          91499b788c4d8908fdad272c4cc69289e905d71d
runner         3c67b7a51b4c42d38dd87d372f73be1751ee87cf
```

## Deterministic result

```text
48/48 semantic + negative tests PASS
Draft 2020-12 schema PASS
exact closure blobs 7/7 PASS
fresh builds 2/2 PASS
fresh bytes identical true
runner log SHA-256  fe692c9ff75ff9e97a28def40d4866dbe5fb7df70a1de22d6e827058cc2b23be
program hash           6f0b1cbe134f6b77825f66b356624975cc84e88f08c9aaba789f24c7d1cba4e6
provenance hash        d79a41e95c7cfb39dec2f41b11d4066f1e57ab0260ed991c69077348ce6add9a
artifact SHA-256       fa6ece19e76784428fb0251a99d5b88bc1ed6183000e6c99755edbe2439c8463
artifact Git blob      db725ef37912547527dff5fffe39ca63e5f8c22e
evidence aggregate     0848ae61b363bbffb0a45f9eff17e5f34df48cec01f5384d6d6c5f416dc28127
```

На принятой E3.3 topology текущий catalog даёт:

- input species: `2/2`;
- colonized species: `2`;
- causal filtered species: `0` в этом конкретном replay;
- colonized patches: `11`;
- species×patch establishments: `22`;
- isolated `cell-12`: `UNREACHABLE` для обоих species.

Это не является гарантией колонизации. Negative matrix отдельно доказывает, что `NO_COLONIZATION` проходит как корректный deterministic результат и не превращается в ошибку или post-hoc species injection.

## Запрещённые shortcuts

- biome→species mapping;
- target-aware species injection;
- catalog prefilter до causal evaluation;
- catalog rebake или target tuning;
- snapshot/raw-fixture bypass accepted E3.3;
- global RNG;
- canonical species promotion;
- canonical SD creation;
- production persistence/network/transaction/authority binding.

## Review boundary

E3.4 **не принят** этой записью. Implementer не имеет права объявлять acceptance.

До fresh independent critical review:

```text
E3.4 = CANDIDATE / NOT ACCEPTED
E3.5 = BLOCKED / NOT AUTHORIZED / NOT STARTED
XFER1 = BLOCKED
production binding = FORBIDDEN
```

Следующий разрешённый шаг — только fresh independent READ-ONLY review exact PR HEAD.
