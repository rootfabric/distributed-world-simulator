# ECO.EVO3 / E3.2 — Repair R1 — candidate for fresh re-review

Дата: 2026-08-19

Статус: **REPAIRED CANDIDATE / FRESH INDEPENDENT RE-REVIEW REQUIRED**.

Этот checkpoint НЕ принимает E3.2, НЕ разрешает merge и НЕ авторизует E3.3. Он фиксирует Implementer-side Repair R1 после независимого `FIX_REQUIRED` по PR #155.

## 1. Superseded reviewed candidate

Независимый review проверял:

- PR #155
- base `7d8379a8b4cb1a817421b0bdbc8e81f52a35a393`
- executable freeze `a7a2431c6f8e61410c91beca69abbbc7b3ae2c7d`
- exact reviewed HEAD `0c3d96396b37d21d68b63ce00051e03b1b668569`
- Project Control `32203684025 / #989 — SUCCESS`

Verdict: **FIX_REQUIRED**.

Blocking findings:

1. published Draft 2020-12 schema имел `samples.items.additionalProperties=false`, но не объявлял `samples.items.properties`; поэтому собственный generated field был invalid instance;
2. runner и test #42 не применяли schema к generated field;
3. explicit negative matrix не исполняла duplicate sample, `canonical_binding_resolved` promotion и фактическую raw-fixture artifact attempt.

Старый executable freeze и его aggregate `680d0168de9aafaed6e364def81e1631d0aa3d564feecb46300a261b536f488d` являются superseded и НЕ могут использоваться как PASS evidence.

## 2. Repair R1 executable freeze

Новый exact code-under-test freeze:

`f276a5b29a39a00ae15c866a310b20f3ad9fe9c8`

От exact reviewed HEAD `0c3d963...` до нового freeze изменены ровно три executable-файла:

- `config/ecology/eco-evo3-e3-2-ecological-opportunity-field.schema.v1.json`
- `tests/research/ecology/test_eco_evo3_e3_2_ecological_opportunity_field.py`
- `RUN_ECO_EVO3_E3_2_TESTS.py`

Implementation, contract и accepted E3.1 snapshot не менялись.

## 3. Exact Repair R1 closure

1. Contract: `bb1f09c7b2c10887749c1b89693a503318368335`
2. Accepted E3.1 snapshot: `0d5f8b6b66b56195770af94ed2d847b5c84751c5`
3. Repaired output schema: `7492b8ebc7dfd88edb0e3ffd833ccb1d33e07160`
4. Implementation: `a38ef6122426fa2e551b213c8d0ad2bc39799ec0`
5. Repaired acceptance tests: `675448ff1d83d3e9ad2f4ed059535c97783f806a`
6. Repaired runner: `81d37d86390df98a0c0cbe2e481c2cf60a1649dc`

Contract hash остаётся:

`bbb2e4f29ac88da42102ee6c08d239f8e0a72760ab8d1371fdea2cda258ed47d`

Научная формула E3.2 не менялась.

## 4. Finding 1 repair — schema

` samples.items ` теперь имеет explicit `properties` для всех 14 published sample fields при сохранённом `additionalProperties=false`.

Дополнительно schema фиксирует:

- ID patterns;
- integer coordinate/thermal bounds;
- 0..1,000,000 PPM bounds;
- 64-hex source/provenance/sample hashes;
- exact fail-closed summary shape.

Schema SHA-256:

`d1ad48e6f758c22ade5f612b4dfeeecee30fb2831aee59bdaf175ebe6fb46316`

## 5. Finding 2 repair — real schema validation

Canonical runner теперь:

- требует `jsonschema`;
- выполняет `Draft202012Validator.check_schema()`;
- валидирует in-memory generated field;
- после двух fresh builds повторно валидирует fresh serialized artifact;
- fail-closed возвращает отдельные error codes при schema rejection.

Acceptance test #42 теперь выполняет настоящую Draft 2020-12 validation generated field, а test #43 доказывает, что `additionalProperties=false` действительно закрывает sample shape.

## 6. Finding 3 repair — negative boundaries

Suite увеличен с 42 до **47 tests**.

Добавлены explicit tests:

- schema rejects unexpected sample property;
- duplicate output sample rejected after full rehash;
- snapshot `canonical_binding_resolved=true` rejected;
- output `canonical_binding_resolved=true` rejected;
- raw fixture-shaped JSON artifact фактически передаётся в accepted-snapshot loader и отклоняется exact artifact boundary.

Старый CLI-surface guard `--fixture` также сохранён.

## 7. Fresh exact-published verification

Fresh carrier:

`/mnt/data/e32_repair_r1`

Он реконструирован из exact published Git blob contents. Independently от working copies проверено **6/6 exact blobs**.

Environment:

- Python: `/opt/pyvenv/bin/python3`
- Python version: `3.13.5`
- jsonschema: `4.26.0`

Результат двух отдельных запусков canonical runner:

- process A: exit 0 / PASS
- process B: exit 0 / PASS
- semantic tests: **47/47 PASS**
- published Draft 2020-12 schema validation: **PASS**
- fresh field builds: 2/2 PASS
- fresh field bytes identical: true
- runner logs byte-identical: true
- runner log SHA-256: `b75830bb535830aac62825a54ceefc6e8b94fdbb64f9966c824fa74bb9681195`

Никакая independent Reviewer/Verifier authority этим прогоном не заявляется.

## 8. Scientific-output regression invariant

Repair исправляет interface/evidence boundary, а не ecology formula. Поэтому regenerated field обязан остаться прежним.

Это подтверждено:

- field provenance: `9be81517eaf0c28503291c5595c0790232b8f88c7ffa9ced2e886ec1f8597aa4`
- opportunity field: `acba61638f8128b667880f2bd391ab73f6175d0899656bba92657d578d48203c`
- field artifact SHA-256: `59a0af5e40cae5c8a91e487da158edadfd4e127a0390ebe856f78f2365a066ff`
- regenerated field byte-identical to superseded candidate: true

Observed summary также не изменился: limiting mean `390833`, establishment mean `262050`.

## 9. Repair evidence aggregate

Repair R1 aggregate:

`ef0ed137bf8d2862f4c9cfacee0792dba8079e539daa4bfb7322d7d5da8afc9c`

Он связывает repair checkpoint id, exact executable freeze, E3.1 parent aggregate, contract, шесть exact closure blobs, scientific output hashes/artifact и fresh runner log hash.

Machine-readable evidence:

`validation/ecology/eco-evo3-e3-2-repair-r1-validation.json`

## 10. Authority boundary

Repair R1 НЕ меняет:

- `RESEARCH_DERIVED_NON_AUTHORITATIVE`;
- exact accepted E3.1 snapshot-only input;
- отсутствие species/biome/population truth;
- отсутствие canonical SD creation;
- отсутствие G/ENV/MAT/WQ/SD/TF ownership;
- отсутствие production persistence/network/transaction authority;
- XFER1 remains blocked.

## 11. Next gate

Следующий разрешённый шаг — только:

**fresh independent critical re-review of E3.2 Repair R1**.

До независимого PASS:

- PR #155 не должен merge;
- E3.2 не считается accepted на canonical ECO frontier;
- E3.3 остаётся blocked/not authorized.
