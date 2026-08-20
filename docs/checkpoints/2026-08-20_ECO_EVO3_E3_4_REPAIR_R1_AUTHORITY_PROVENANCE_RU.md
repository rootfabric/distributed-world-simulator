# ECO EVO3 E3.4 — Repair R1: exact-input authority/provenance

Статус: **IMPLEMENTER REPAIR VERIFIED / AWAITING FRESH INDEPENDENT REVIEW**.

Это не acceptance E3.4 и не разрешение на E3.5, XFER1 или production ECO authority.

## 1. Исправляемый finding

Единственный scope Repair R1:

`E3.4-R-001 — exact-input authority can be bypassed inside build_colonization_program(), allowing false provenance attestation.`

Reviewer-failed repair base:

`79158dfe0d3dc31720da8915b74321ed2c48ee8a`

Никакие научные causal equations, dispersal semantics, establishment semantics, topology semantics или SpeciesCatalog semantics в Repair R1 не перепроектировались.

## 2. Что изменено

Authoritative boundary теперь fail-closed относительно accepted-input attestation:

- exact contract, accepted E3.3 binding, accepted E3.3 decomposition и FULL persisted EVO2 SpeciesCatalog проверяются по exact Git blob bytes **до JSON parse**;
- decomposition/catalog дополнительно проверяются по принятым SHA-256 identities;
- authoritative `build_colonization_program()` не доверяет mutable parsed state: он повторно проверяет и парсит сохранённые verified raw bytes;
- plain parsed dictionaries могут использовать frozen scientific core, но получают только явный `UNVERIFIED_PARSED_INPUTS_NO_ACCEPTED_INPUT_ATTESTATION` и не могут выдать accepted E3.3/catalog provenance;
- genome checksum, recruitment checksum, catalog entry hash и catalog hash пересчитываются из фактического содержимого теми же EVO2 algorithms, которыми создан accepted SpeciesCatalog;
- authoritative provenance берётся из заново verified/recomputed input identities, а не из копируемых заявленных hash fields.

## 3. Научное ядро не переписано

Reviewer-failed implementation blob:

`46f424608a9d4e9bf9119b3700c3ba75b24197bd`

В Repair R1 этот exact blob сохранён byte-for-byte как:

`scripts/research/ecology/causal_colonization_program_compiler_v1_core.py`

Новый authority wrapper:

`e3af356a2e30eb29af27caef7c0ac6a6f067cc6d`

Следовательно causal computation отделено от authority/provenance boundary без изменения frozen scientific body.

## 4. Regression coverage

Исходный 48-test semantic/negative matrix не ослаблен и не удалён:

`91499b788c4d8908fdad272c4cc69289e905d71d`

Добавлен отдельный Repair R1 matrix, 10/10:

`0baf87ac438a742ec8d1b7ca4fd6739fd8a2642b`

Он покрывает минимум:

1. plain parsed inputs не могут аттестовать accepted provenance;
2. reviewer-demonstrated decomposition dict bypass не может false-attest;
3. reviewer-demonstrated catalog genome/trait dict bypass не может false-attest;
4. mutation verified wrapper после load игнорируется, потому что authoritative build reparses raw bytes;
5. tampered decomposition bytes отклоняются до parse;
6. tampered catalog bytes отклоняются до parse;
7. genome checksum пересчитывается из actual genome content;
8. recruitment checksum пересчитывается из actual trait content;
9. entry hash пересчитывается из actual entry content;
10. catalog hash/provenance строятся из verified/recomputed identities.

## 5. Новый executable freeze

Exact executable freeze Repair R1:

`99941d07ec64edd39a81aae6d2812d4968e91aed`

Freeze closure включает:

- contract blob `de38fbc06a2a733cfac52df5b0345f900f42f117`;
- accepted E3.3 binding `84660f5c60da2e7b9dcb9ace0d287321f303a94e`;
- accepted E3.3 decomposition `9915bc13b0e81533fdc99ffe5707d0d60ba58eda`;
- FULL persisted EVO2 catalog `397ace0c6c7b204793b7663e7a89417d44ba3484`;
- Draft 2020-12 schema `95991eb62d90690b351d7522805ada2695d82898`;
- authority wrapper `e3af356a2e30eb29af27caef7c0ac6a6f067cc6d`;
- unchanged scientific core `46f424608a9d4e9bf9119b3700c3ba75b24197bd`;
- original tests `91499b788c4d8908fdad272c4cc69289e905d71d`;
- Repair R1 tests `0baf87ac438a742ec8d1b7ca4fd6739fd8a2642b`;
- canonical runner `e779d4667a9ac5216f4b8ff436b808037c3979c0`;
- exact-head closure workflow `f7a7e56c59ef9554da854eef074899bdcd689330`.

## 6. Exact-head full closure

Authoritative closure run:

`32325422099 / #2 — SUCCESS`

Job:

`96295571982 — exact published E3.4 Repair R1 closure — SUCCESS`

Workflow явно checkout-ит и assert-ит immutable PR HEAD:

`99941d07ec64edd39a81aae6d2812d4968e91aed`

Результат:

```text
ECO.EVO3 E3.4 Causal Colonization Program Compiler: PASS
semantic_and_repair_tests=58/58
authority_regression_tests=10/10
negative_matrix=PASS
published_schema_validation=PASS
closure_blobs=9/9
scientific_core_blob_unchanged=46f424608a9d4e9bf9119b3700c3ba75b24197bd
fresh_colonization_builds=2/2
fresh_colonization_bytes_identical=true
jsonschema_version=4.26.0
```

Runner log:

- bytes `1143`;
- SHA-256 `1827b1127fdf538183fb81a4b5dcc6ae26b669e85acc42eb4b4251c57e72f5fa`;
- artifact `9391172531`;
- artifact ZIP SHA-256 `5a1de800f6dda8934d48573b3f74bcd7e7bce3f3fa4c00ea61f34e4d9129b60d`.

Первый CI run `32325379763` не используется как exact-head evidence: стандартный pull_request checkout взял synthetic merge ref. Harness был исправлен, после чего closure повторён против immutable HEAD и только повторный run считается evidence.

## 7. Scientific identity stability

После repair остались неизменны:

- contract hash `531172bc2ebdd4d13977d50afe25616a34bb0879fb8efa34d745ea3048b9d3d3`;
- catalog hash `5fcd8b90135cd8af69defc4f4a5ea26ede422ff82b25a0995bf5c6b10a53f219`;
- decomposition artifact SHA-256 `cab0ec65d66f68f097c07b686e5e87ba998dfe39a9b587a3f945b10d0ac2029a`;
- catalog artifact SHA-256 `99d6dbf87d1a459e2f73f13959dcb53d9b0b8be1519bb5352622202954cf7d1e`;
- program hash `6f0b1cbe134f6b77825f66b356624975cc84e88f08c9aaba789f24c7d1cba4e6`;
- provenance hash `d79a41e95c7cfb39dec2f41b11d4066f1e57ab0260ed991c69077348ce6add9a`;
- generated artifact SHA-256 `fa6ece19e76784428fb0251a99d5b88bc1ed6183000e6c99755edbe2439c8463`.

То есть repair изменяет trust boundary, но exact accepted scientific replay остаётся идентичным.

## 8. Project Control на freeze

`32325422108 / #1020 — SUCCESS`

Head:

`99941d07ec64edd39a81aae6d2812d4968e91aed`

После публикации этого evidence/checkpoint требуется отдельный exact-final-head Project Control; его identity должна быть указана в reviewer dispatch.

## 9. Evidence aggregate

`ce18620d9699e4b8b69724ad6e7bd8c27647a919cd4126a75e0753715576a013`

Алгоритм: `SHA256_NEWLINE_JOINED_FIXED_FIELDS_V1` по frozen Repair R1 identities, перечисленным в validation evidence.

## 10. Scope boundary

На этом checkpoint:

- `E3.4 = CANDIDATE / NOT ACCEPTED`;
- `E3.5 = BLOCKED / NOT AUTHORIZED / NOT STARTED`;
- `XFER1 = BLOCKED`;
- `production ECO authority = NOT ACTIVATED`;
- PR #168 не merged;
- self-acceptance не выполнялся.

Следующий допустимый шаг: **fresh independent READ-ONLY critical review Repair R1**.
