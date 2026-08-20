# ECO EVO3 E3.4 — Repair R2: core authority bypass closure

Статус: **IMPLEMENTER REPAIR VERIFIED / AWAITING FRESH INDEPENDENT REVIEW**.

Это не acceptance E3.4 и не разрешение на E3.5, XFER1 или production ECO authority.

## 1. Scope Repair R2

Repair R2 исправляет только остаток finding `E3.4-R-001` после Repair R1:

`causal_colonization_program_compiler_v1_core.py::build_colonization_program()` оставался напрямую импортируемым callable и мог при произвольных parsed decomposition/catalog объектах формировать accepted E3.3 / persisted EVO2 provenance из contract constants.

Repair R2 base:

`8f585c09d08fe2c0c4a3c959f52c8fb9d574eadc`

Предыдущий Repair R1 executable freeze:

`99941d07ec64edd39a81aae6d2812d4968e91aed`

## 2. Исправленная authority architecture

Новый scientific core blob:

`1472f0b1b8dbd7f0311404680f8ba6e40c4aa96c`

Core сохраняет causal computation, но direct parsed-input result теперь всегда имеет только:

`UNVERIFIED_PARSED_INPUTS_NO_ACCEPTED_INPUT_ATTESTATION`

Core больше не формирует accepted E3.3, persisted EVO2 transport/catalog, E2.FINAL или historical ECO provenance. В direct-core output также отсутствует transport attestation в `source_catalog`.

Новый hardened wrapper blob:

`5ec0cd05a04c0d02677875290306ee1fc51f07b2`

Wrapper остаётся единственной authoritative accepted-attestation boundary. Он сохраняет Repair R1 guarantees:

- exact contract/binding/decomposition/catalog Git blob verification до parse;
- decomposition raw SHA-256 verification;
- catalog raw SHA-256 verification;
- genome checksum recomputation из actual content;
- recruitment checksum recomputation;
- entry hash recomputation;
- catalog hash recomputation;
- reparse сохранённых verified raw bytes перед authoritative scientific build.

## 3. Historical EVO2/E2 lineage без нового trust root

Repair R2 **не создаёт новый identity-binding/trust-root файл**.

Historical lineage устанавливается через уже существующие accepted immutable evidence:

- E2.8 validation blob `47d55332591ef59fcf324701fece19df10781d44`;
- E2.FINAL validation blob `bd7999a7bbaba4048844333f509994b2668ed227`.

Wrapper проверяет exact blobs до parse и независимо связывает:

- accepted E2.8 catalog hash `5fcd8b90135cd8af69defc4f4a5ea26ede422ff82b25a0995bf5c6b10a53f219`;
- E2.8 transport SHA-256 `b31c863f8e1943e5778d56631f8c8ad75b95f3b9d3930a699f80fd07595d45d1`;
- 2/2 catalog entries и exact fresh restore semantic identity;
- E2.FINAL parent E2.8 aggregate link;
- E2.FINAL input transport link;
- E2.FINAL catalog identity;
- E2.FINAL aggregate `6daab256af3d1e7693c66a8afaad4d04fd1564c4376b9f3cd747a268a10c2250`;
- no direct catalog reconstruction bypass;
- no rebake;
- all restored entries enter source port.

Historical ECO anchor `f0e16195f1331f238bbacab2768e5d72ec01d1a3` дополнительно проверяется через Git ancestry относительно accepted E2.8 и E2.FINAL code-under-test HEADs.

Contract historical values используются только как expected constraints после independently established evidence identities.

## 4. Direct-core regression matrix

Новый Repair R2 test blob:

`65253d0f1b2b8c2f9e4c862c06d05b8de968b4bd`

10/10 новых regressions покрывают:

1. direct core + exact parsed inputs — accepted attestation отсутствует;
2. exact reviewer decomposition mutation + copied accepted claims — accepted attestation отсутствует;
3. exact reviewer nested catalog mutation + copied claims — accepted attestation отсутствует;
4. вызов через `wrapper._core` — accepted attestation отсутствует;
5. core source не содержит forbidden accepted/historical provenance output keys;
6. plain parsed wrapper path не может исторически attest contract constants;
7. только verified wrapper path выпускает accepted provenance;
8. historical lineage выводится из pre-existing accepted E2.8/E2.FINAL evidence;
9. tampered historical evidence отклоняется exact Git-blob gate;
10. historical anchor substitution отклоняется Git-lineage gate.

Repair R1 10/10 authority regressions сохранены. Semantic matrix остаётся 48 tests; изменены только provenance tests 14-16/41 так, чтобы historical accepted provenance проверялся через authoritative verified path, а не через synthetic parsed-input path.

Итого exact closure выполняет `68/68`, из них authority regressions `20/20`.

## 5. Scientific semantics

Repair R2 меняет core blob, потому что vulnerable provenance-capable boundary находилась внутри старого core. Это ожидаемо.

Causal scientific computation сохранён без изменения:

- six-dimension opportunity minimum;
- five-component trait support;
- trait modifier;
- establishment arithmetic;
- dispersal capacity;
- edge-arrival threshold;
- deterministic patch/edge ordering;
- bounded fixed-point propagation;
- `NO_COLONIZATION` как валидный successful result.

Exact accepted replay остался byte-identical:

- program hash `6f0b1cbe134f6b77825f66b356624975cc84e88f08c9aaba789f24c7d1cba4e6`;
- provenance hash `d79a41e95c7cfb39dec2f41b11d4066f1e57ab0260ed991c69077348ce6add9a`;
- generated artifact SHA-256 `fa6ece19e76784428fb0251a99d5b88bc1ed6183000e6c99755edbe2439c8463`;
- input species `2/2`;
- colonized species `2`;
- colonized patches `11`;
- species×patch establishments `22`.

## 6. Repair R2 executable freeze

Exact executable freeze:

`9125d350213fa55f744d98b88764c60ef0f99032`

Exact closure blobs:

1. contract `de38fbc06a2a733cfac52df5b0345f900f42f117`
2. accepted E3.3 binding `84660f5c60da2e7b9dcb9ace0d287321f303a94e`
3. accepted E3.3 decomposition `9915bc13b0e81533fdc99ffe5707d0d60ba58eda`
4. FULL persisted EVO2 catalog `397ace0c6c7b204793b7663e7a89417d44ba3484`
5. Draft 2020-12 program schema `95991eb62d90690b351d7522805ada2695d82898`
6. accepted E2.8 validation `47d55332591ef59fcf324701fece19df10781d44`
7. accepted E2.FINAL validation `bd7999a7bbaba4048844333f509994b2668ed227`
8. authority wrapper `5ec0cd05a04c0d02677875290306ee1fc51f07b2`
9. scientific non-authoritative core `1472f0b1b8dbd7f0311404680f8ba6e40c4aa96c`
10. 48-test semantic matrix `946674326ac60557023b19ff75fea5d9dac4afec`
11. Repair R1 10-test matrix `0baf87ac438a742ec8d1b7ca4fd6739fd8a2642b`
12. Repair R2 10-test matrix `65253d0f1b2b8c2f9e4c862c06d05b8de968b4bd`
13. exact runner/workflow closure identities `82c1cdfae2eea6373094c313caf8fa580da618c3` / `0b2a0322db2bf4770c07e4db9fbebc3a012a791f`

## 7. Exact executable-freeze closure

Workflow:

`32334065535 / #4 — SUCCESS`

Job:

`96320066607 — exact published E3.4 Repair R2 closure — SUCCESS`

Exact checkout HEAD:

`9125d350213fa55f744d98b88764c60ef0f99032`

Observed:

```text
ECO.EVO3 E3.4 Causal Colonization Program Compiler: PASS
semantic_and_repair_tests=68/68
repair_r1_authority_regression_tests=10/10
repair_r2_direct_core_regression_tests=10/10
authority_regression_tests=20/20
direct_core_authoritative_attestation=ABSENT
wrapper_core_handle_authoritative_attestation=ABSENT
historical_lineage_evidence=2/2
historical_lineage_contract_is_constraint_only=true
negative_matrix=PASS
published_schema_validation=PASS
closure_blobs=13/13
scientific_core_authority=NON_AUTHORITATIVE
fresh_colonization_builds=2/2
fresh_colonization_bytes_identical=true
no_colonization_negative_case=PASS
```

Canonical runner stdout SHA-256:

`7e8225d118ed44a78eb671c0548b721ede48bd0ff7d25ffdf05b82b8814454fa`

Uploaded log artifact:

- ID `9393996762`;
- ZIP SHA-256 `2716775d7417741e66b391e68f88c2adc7e2c7fb61eea34c6bd63f02a1c4dc29`.

## 8. Project Control на executable freeze

`32334065615 / #1031 — SUCCESS`

Job `96320066617 — control — SUCCESS`.

Exact head `9125d350213fa55f744d98b88764c60ef0f99032`, exact base `6848eb81ea8bd137bc81d42a6348046c0837c3e1`.

## 9. Evidence aggregate

`96cb8557b0ae68a11bf42e89a08ac3f233990f9d060c5fd3be31ea112bb17e46`

Algorithm: `SHA256_NEWLINE_JOINED_FIXED_FIELDS_V1` по immutable Repair R2 identities, перечисленным в validation evidence.

## 10. Scope boundary

На этом checkpoint:

- `E3.4 = CANDIDATE / NOT ACCEPTED`;
- PR #168 = open / not merged;
- `E3.5 = BLOCKED / NOT AUTHORIZED / NOT STARTED`;
- `XFER1 = BLOCKED`;
- production ECO authority = NOT ACTIVATED;
- canonical species taxonomy = NOT ACTIVATED;
- production binding = NOT ACTIVATED;
- self-acceptance = NOT PERFORMED.

После публикации этого evidence-only commit обязательны exact-final-head closure и Project Control. Затем допустим только fresh independent READ-ONLY Repair R2 review dispatch.
