# ECO.EVO3 / E3.1 — Planet Field Snapshot Contract — ACCEPTED

Статус: `ACCEPTED / RESEARCH_ONLY / NO_PRODUCTION_BINDING`.

Ветка: `feature/eco-evolutionary-ecology`.

Exact code-under-test freeze:

`7a1f5f0dc29b0564c6d4b684826250fca6a9b711`.

Parent E3.0 durable head:

`f1820949fcb89156429e5c150e530ac7da1267b7`.

## Что доказано

E3.1 вводит детерминированный research-only входной контракт для Planetary Ecology Compiler. Snapshot связывает:

- stable planet identity;
- stable time key;
- reference frame identity;
- stable spatial keys;
- opaque semantic references на `G / ENV / MAT / WQ / SD / TF`;
- temperature, soil moisture, light, nutrients и disturbance pressure;
- per-sample provenance;
- fixture provenance;
- deterministic snapshot hash.

Snapshot не является canonical world state и не создаёт production API binding.

## Fixed-unit numeric policy

Чтобы не вносить неоднозначность float canonicalization на входе compiler-а, E3.1 использует только integer fixed units:

```text
latitude / longitude     microdegrees
temperature              milli-degrees C
moisture/light/nutrients ppm fraction
disturbance              ppm fraction
```

Все значения проверяются по bounded ranges до построения snapshot.

## Research fixture

Fixture:

`fixtures/research/ecology/evo3/e3_1_planet_field_semantic_fixture.v1.json`.

Он содержит 12 заранее заданных samples и opaque research semantic references для всех шести foundation dependencies. Ни одно поле fixture/snapshot не содержит biome label, species assignment или population truth.

Frozen identities:

```text
contract hash
b3e96b432008ea93692c5cbde9cf7c74cceca4e4c4196ef261a5fbd0ff405170

fixture hash
3e22d87666b13a4bafcdd5dd3184097b53b221103fd2f9e9f2be452c8ab79978

field provenance hash
3827c1da7d94227fb04b5fbfbd93fd5262c826cd86503af9f540a120431a82c3

snapshot hash
2ceb042d905b06ae76acc699b60ed6c115d3e0ac7943ce7cbe0c94f962447b00

canonical snapshot artifact SHA-256
5123ebd58e6eade5d3dab2325af49a43234bc8834182ddd7db7d6c463896b790

E3.1 aggregate
0a412c5c6cb12264c93c92d502321b578ebb3d166ae90d80ab450e03478e8036
```

## Exact published candidate

```text
contract
  dce1e88104d3fb1ec3dece88f96338a980d50fba

snapshot schema
  506ed3abc448e810cf1f414edc8864bee4822442

fixture
  3b9ebfdd5962f885884b8145c519c2cb84498a24

implementation
  beea22985f6ab8c47c838c39aec45994492b5ee9

acceptance tests
  096a14a5862f5d74cdf81b1822f1fee22f2764d3

canonical runner
  cc3ec0d1ad6fd07bf1a16d5a5d33b67d0de493e7
```

Все шесть published Git blobs были реконструированы byte-for-byte и сверены через `git hash-object` перед acceptance execution.

## Verification

Canonical runner:

`RUN_ECO_EVO3_E3_1_TESTS.py`.

Результат exact-published carrier:

```text
Python                         3.13.5
py_compile                     PASS
semantic tests                 32 / 32 PASS
fresh runner A/B               PASS / PASS
exit codes                     0 / 0
fresh snapshot builds          2 / 2 PASS
snapshot bytes                 byte-identical
runner logs                    byte-identical
runner log SHA-256             f0c8169b1c36edb68505e19951db493324fac637b989383d2f3234304a3763e2
```

Negative suite не ограничивается raw checksum failure: semantic mutations пересчитывают соответствующие hashes и всё равно должны быть rejected. Проверяются parent/XFER0 substitution, production binding, canonical-owner promotion, owner write permission, float encoding, missing foundation, duplicate spatial keys, invalid values, biome/species/population injection, snapshot authority escalation и sample reordering.

## Authority boundary

E3.1 НЕ означает:

- production binding `G/ENV/MAT/WQ/SD/TF`;
- владение canonical environment/time/spatial truth;
- production persistence authority;
- network/transaction/authority ownership;
- population truth;
- species placement;
- canonical taxonomy.

`XFER1` остаётся `BLOCKED_WAIT_CANONICAL_FOUNDATIONS`.

## Решение

`E3.1 ACCEPTED`.

Следующий этап разрешён как research-only:

`ECO.EVO3 / E3.2 — Ecological Opportunity Field`.

E3.2 обязан потреблять accepted E3.1 snapshot contract/artifact. Прямой обход через raw fixture запрещён.

Independent Reviewer/Verifier PASS этим checkpoint не заявляется. Project Control/GitHub CI GREEN также не выводится из локального canonical runner.
