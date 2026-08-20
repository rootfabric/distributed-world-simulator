# ECO EVO3 E3.4 — Repair R3: helper authority bypass closure

Статус: **IMPLEMENTER REPAIR VERIFIED / AWAITING FRESH INDEPENDENT REVIEW**.

Это не acceptance E3.4 и не разрешение на E3.5, XFER1 или production ECO authority.

## 1. Scope Repair R3

Repair R3 исправляет только остаток finding `E3.4-R-001` после Repair R2.

Repair R2 уже сделал scientific core неавторитетным, однако wrapper сохранял прямой top-level helper:

`causal_colonization_program_compiler_v1.py::_rehash_program(program, provenance, transport_sha256, transport_bytes)`.

Этот callable позволял взять произвольный core output, передать caller-supplied accepted provenance/transport значения и пересчитать `provenance_hash` и `colonization_program_hash`, не проходя verified raw-input authority boundary.

Repair R3 base:

`9b64fef3110690a55ad4020f13b83e67d5eae944`

Предыдущий Repair R2 executable freeze:

`9125d350213fa55f744d98b88764c60ef0f99032`

## 2. Исправленная authority architecture

`_rehash_program(...)` удалён полностью; переименование или replacement helper не вводились.

Новый authoritative wrapper blob:

`91f31dd7a291ef1f88c3af1bf8456ebd0dad4c08`

Финальная authoritative provenance/hash assembly теперь выполняется только внутри verified `build_colonization_program(...)` после `_reparse_verified_inputs(...)` и, следовательно, после:

- exact raw-byte + Git-blob verification contract/binding/decomposition/catalog;
- decomposition artifact SHA-256 и accepted identity verification;
- genome checksum recomputation из actual catalog content;
- recruitment checksum recomputation;
- entry hash recomputation;
- catalog hash recomputation;
- exact accepted E2.8 evidence blob validation;
- exact accepted E2.FINAL evidence blob validation;
- historical ECO anchor Git ancestry validation.

Accepted provenance формируется только из identities, установленных этим verified traversal. Публичный authority entrypoint не принимает caller-supplied `provenance`, transport SHA/bytes, E2.FINAL aggregate или historical anchor.

Полный wrapper-helper audit подтверждает отсутствие другого top-level callable, который принимает `program` вместе с provenance/transport/decomposition/catalog/E2.FINAL/historical/hash injection inputs и способен завершить accepted-looking attestation.

## 3. Repair R2 preserved

Scientific core blob не изменён:

`1472f0b1b8dbd7f0311404680f8ba6e40c4aa96c`

Оба direct paths:

- `core.build_colonization_program(...)`;
- `wrapper._core.build_colonization_program(...)`

остаются явно non-authoritative и возвращают только `UNVERIFIED_PARSED_INPUTS_NO_ACCEPTED_INPUT_ATTESTATION` provenance без accepted E3.3 / persisted EVO2 / E2.8 / E2.FINAL / historical authority attestation и без transport attestation.

Repair R1 raw-byte/Git-blob checks, nested EVO2 recomputation, E2.8/E2.FINAL historical evidence validation и Git ancestry validation сохранены.

## 4. Repair R3 regression matrix

Новый Repair R3 test blob:

`3ecea6de15814f72311f8d807724c14a00e28c4c`

10/10 новых regressions покрывают:

1. exact Reviewer reproducer: `_rehash_program` authority surface отсутствует;
2. mutated core output + copied accepted provenance не может быть завершён в accepted attestation;
3. exact parsed core output + copied accepted provenance не может быть завершён;
4. arbitrary transport SHA/bytes injection отсутствует в authority entrypoint;
5. arbitrary E2.FINAL aggregate injection отсутствует;
6. arbitrary historical anchor injection отсутствует;
7. AST/runtime scan всех wrapper-owned top-level helpers не обнаруживает replacement provenance injector;
8. direct core остаётся non-authoritative;
9. `wrapper._core` остаётся non-authoritative;
10. verified exact wrapper остаётся authoritative и deterministic.

Сохранены original semantic tests, Repair R1 10/10 и Repair R2 10/10.

Итого exact closure: `78/78`; authority regressions: `30/30`.

## 5. Scientific semantics и deterministic replay

Causal scientific computation не изменён:

- source-port selection;
- six-dimensional opportunity minimum;
- trait support;
- modifier arithmetic;
- establishment thresholds;
- dispersal;
- continuity scaling;
- deterministic ordering;
- bounded fixed-point propagation;
- `NO_COLONIZATION` behavior.

Exact accepted replay остался byte-identical:

- program hash `6f0b1cbe134f6b77825f66b356624975cc84e88f08c9aaba789f24c7d1cba4e6`;
- provenance hash `d79a41e95c7cfb39dec2f41b11d4066f1e57ab0260ed991c69077348ce6add9a`;
- generated artifact SHA-256 `fa6ece19e76784428fb0251a99d5b88bc1ed6183000e6c99755edbe2439c8463`;
- input species `2/2`;
- colonized species `2`;
- colonized patches `11`;
- species×patch establishments `22`;
- fresh builds `2/2`, byte-identical;
- `NO_COLONIZATION` negative case = PASS.

## 6. Repair R3 executable freeze

Exact executable freeze:

`b51e815df0939deaf99ea0dc349fc7fc80c0a3bc`

Exact closure blobs:

1. contract `de38fbc06a2a733cfac52df5b0345f900f42f117`
2. accepted E3.3 binding `84660f5c60da2e7b9dcb9ace0d287321f303a94e`
3. accepted E3.3 decomposition `9915bc13b0e81533fdc99ffe5707d0d60ba58eda`
4. FULL persisted EVO2 catalog `397ace0c6c7b204793b7663e7a89417d44ba3484`
5. Draft 2020-12 program schema `95991eb62d90690b351d7522805ada2695d82898`
6. accepted E2.8 validation `47d55332591ef59fcf324701fece19df10781d44`
7. accepted E2.FINAL validation `bd7999a7bbaba4048844333f509994b2668ed227`
8. authoritative wrapper `91f31dd7a291ef1f88c3af1bf8456ebd0dad4c08`
9. scientific non-authoritative core `1472f0b1b8dbd7f0311404680f8ba6e40c4aa96c`
10. 48-test semantic matrix `946674326ac60557023b19ff75fea5d9dac4afec`
11. Repair R1 10-test matrix `0baf87ac438a742ec8d1b7ca4fd6739fd8a2642b`
12. Repair R2 10-test matrix `65253d0f1b2b8c2f9e4c862c06d05b8de968b4bd`
13. Repair R3 10-test matrix `3ecea6de15814f72311f8d807724c14a00e28c4c`
14. exact runner/workflow closure identities `08f622680026c9c54cbe5f119d9f4c23695c90cc` / `aa8ef86ad6b39d07ff59768a63feca1db6185f80`

## 7. Exact executable-freeze closure

Workflow:

`32345733295 / #6 — SUCCESS`

Job:

`96353988943 — exact published E3.4 Repair R3 closure — SUCCESS`

Exact checkout HEAD:

`b51e815df0939deaf99ea0dc349fc7fc80c0a3bc`

Observed:

```text
ECO.EVO3 E3.4 Causal Colonization Program Compiler: PASS
semantic_and_repair_tests=78/78
repair_r1_authority_regression_tests=10/10
repair_r2_direct_core_regression_tests=10/10
repair_r3_helper_bypass_regression_tests=10/10
authority_regression_tests=30/30
rehash_program_authority_surface=ABSENT
replacement_program_provenance_injection_helpers=ABSENT
direct_core_authoritative_attestation=ABSENT
wrapper_core_handle_authoritative_attestation=ABSENT
historical_lineage_evidence=2/2
negative_matrix=PASS
published_schema_validation=PASS
closure_blobs=14/14
scientific_core_authority=NON_AUTHORITATIVE
fresh_colonization_builds=2/2
fresh_colonization_bytes_identical=true
no_colonization_negative_case=PASS
```

Canonical runner stdout SHA-256:

`035ada3c85be142b4f5b55e1354ece5f67e269e32b500bc7d30875713f195f54`

Uploaded runner-log artifact:

- ID `9397948634`;
- ZIP SHA-256 `aa869ff70fbc43a8082c7e6320178f51ceea4472651fbf867839e632f0152cb7`.

## 8. Project Control на executable freeze

`32345733296 / #1034 — SUCCESS`

Job `96353988972 — control — SUCCESS`.

Exact head `b51e815df0939deaf99ea0dc349fc7fc80c0a3bc`, exact base `6848eb81ea8bd137bc81d42a6348046c0837c3e1`.

## 9. Evidence aggregate

`4207f43f8fcbb04b1fd405fff41da94542c32153d6946362d7523ff3e4ac6a55`

Algorithm: `SHA256_NEWLINE_JOINED_FIXED_FIELDS_V1` по immutable Repair R3 identities, перечисленным в validation evidence.

## 10. Scope boundary

На этом checkpoint:

- `E3.4 = CANDIDATE / NOT ACCEPTED`;
- PR #168 = open / not merged;
- `E3.5 = BLOCKED / NOT AUTHORIZED / NOT STARTED`;
- `XFER1 = BLOCKED`;
- production ECO authority = NOT ACTIVATED;
- canonical species taxonomy = NOT ACTIVATED;
- production binding = NOT ACTIVATED;
- self-review/self-acceptance = NOT PERFORMED.

После публикации этого evidence-only commit обязательны exact-final-head Repair R3 closure и Project Control. Затем допустим только fresh independent READ-ONLY Repair R3 reviewer dispatch.
