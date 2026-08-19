# ECO.EVO3 / E3.2 — Ecological Opportunity Field — candidate accepted

Дата: 2026-08-19

Статус: **CANDIDATE ACCEPTED / MERGE TO ECO FRONTIER PENDING**.

Это исследовательский checkpoint. Он не является production acceptance, не даёт ECO владение G/ENV/MAT/WQ/SD/TF и не авторизует XFER1, runtime authority, persistence, networking или world transactions.

## 1. Почему работа велась в отдельной ветке

На момент начала E3.2 canonical ECO frontier `feature/eco-evolutionary-ecology` уже находился на E3.1 ACCEPTED / E3.2 AUTHORIZED. Чтобы не перезаписать параллельную работу, E3.2 реализован в отдельной ветке:

`feature/eco-evo3-e3-2-opportunity-field`

Exact source frontier base при freeze:

`7d8379a8b4cb1a817421b0bdbc8e81f52a35a393`

Exact executable candidate freeze:

`a7a2431c6f8e61410c91beca69abbbc7b3ae2c7d`

На freeze candidate был ровно на 6 commits впереди source frontier и не отставал от него.

## 2. Exact parent E3.1

E3.2 не читает raw fixture и не строит собственную копию owner fields. Единственный допустимый вход — materialized exact accepted E3.1 snapshot:

`config/ecology/accepted_inputs/e3_1_accepted_planet_field_snapshot.v1.json`

Locks:

- E3.1 code-under-test: `7a1f5f0dc29b0564c6d4b684826250fca6a9b711`
- E3.1 aggregate: `0a412c5c6cb12264c93c92d502321b578ebb3d166ae90d80ab450e03478e8036`
- E3.1 contract: `b3e96b432008ea93692c5cbde9cf7c74cceca4e4c4196ef261a5fbd0ff405170`
- E3.1 field provenance: `3827c1da7d94227fb04b5fbfbd93fd5262c826cd86503af9f540a120431a82c3`
- E3.1 snapshot: `2ceb042d905b06ae76acc699b60ed6c115d3e0ac7943ce7cbe0c94f962447b00`
- E3.1 snapshot artifact SHA-256: `5123ebd58e6eade5d3dab2325af49a43234bc8834182ddd7db7d6c463896b790`

Raw-fixture CLI surface отсутствует и отдельно проверяется acceptance tests.

## 3. Замороженная семантика E3.2

E3.2 строит непрерывные species-agnostic opportunity values в integer fixed-point PPM:

- `water_opportunity_ppm = soil_moisture_ppm`
- `light_opportunity_ppm = light_availability_ppm`
- `nutrient_opportunity_ppm = nutrient_availability_ppm`
- `persistence_opportunity_ppm = 1_000_000 - disturbance_pressure_ppm`
- `limiting_resource_opportunity_ppm = min(water, light, nutrient)`
- `establishment_opportunity_ppm = floor(limiting_resource * persistence / 1_000_000)`

`temperature_milli_c` переносится только как `thermal_context_milli_c`. В E3.2 нет temperature optimum, fitness target или species-specific weighting.

Интерполяция намеренно не вводится: `NONE_E3_2_SAMPLE_FIELD_ONLY`. Это не даёт E3.2 скрыто создавать spatial decomposition, которая относится к следующему E3.3.

Contract hash:

`bbb2e4f29ac88da42102ee6c08d239f8e0a72760ab8d1371fdea2cda258ed47d`

## 4. Exact executable closure

Freeze состоит из шести опубликованных Git blobs:

1. Runner `RUN_ECO_EVO3_E3_2_TESTS.py` — `f68c66a3fbba17dc445c8ec2a94f72ef1ea6112d`
2. Contract — `bb1f09c7b2c10887749c1b89693a503318368335`
3. Accepted E3.1 snapshot — `0d5f8b6b66b56195770af94ed2d847b5c84751c5`
4. Output schema — `46134f36d18a13f3811a0836b2773a66d5c6bb33`
5. Implementation — `a38ef6122426fa2e551b213c8d0ad2bc39799ec0`
6. Acceptance test — `8ad2ba1e15eadf24a74555c41de938a9cb7dedc6`

Runner fail-closed проверяет первые пять dependency blobs до behavioural execution. Runner blob отдельно зафиксирован durable evidence.

## 5. Fresh exact-published verification

Carrier: fresh reconstructed exact-published six-blob closure.

Python:

- executable: `/opt/pyvenv/bin/python3`
- version: `3.13.5`

Результат:

- Python compile: PASS
- semantic/negative acceptance tests: **42/42 PASS**
- canonical Python runner: executed
- fresh runner process A: PASS / exit 0
- fresh runner process B: PASS / exit 0
- runner logs byte-identical: true
- runner log SHA-256: `748055e6ee6f599a36415fd8a0cc789a10a95758cef9df2d19bf1e53bd225b54`
- two fresh field builds: PASS / PASS
- field bytes byte-identical: true

Никакая independent Reviewer/Verifier authority этим прогоном не заявляется.

## 6. Frozen result

- field provenance: `9be81517eaf0c28503291c5595c0790232b8f88c7ffa9ced2e886ec1f8597aa4`
- opportunity field hash: `acba61638f8128b667880f2bd391ab73f6175d0899656bba92657d578d48203c`
- field artifact SHA-256: `59a0af5e40cae5c8a91e487da158edadfd4e127a0390ebe856f78f2365a066ff`
- aggregate: `680d0168de9aafaed6e364def81e1631d0aa3d564feecb46300a261b536f488d`

Observed 12-sample summary:

- limiting resource min: 120000 ppm
- limiting resource max: 700000 ppm
- limiting resource mean: 390833 ppm
- establishment min: 52500 ppm
- establishment max: 402600 ppm
- establishment mean: 262050 ppm

Exact generated candidate artifact опубликован как:

`config/ecology/accepted_inputs/e3_2_candidate_ecological_opportunity_field.v1.json`

Git blob: `68e601958b1206235729aceb40843cd8666840aa`

Этот generated artifact появился после executable freeze и не изменяет code-under-test.

## 7. Negative gates

Acceptance suite отвергает, в том числе:

- подмену E3.1 head/aggregate/snapshot/artifact или E3.0 architecture после rehash;
- разрешение raw fixture или raw owner-field bypass;
- изменение формул после rehash contract;
- semantic mutation accepted snapshot даже после пересчёта snapshot hash;
- canonical authority promotion;
- reorder/drop samples;
- species, biome или population injection даже после пересчёта output hashes;
- semantic tamper establishment value после полного rehash output;
- неожиданные output fields;
- global RNG import;
- raw fixture CLI.

## 8. Архитектурная граница

E3.2 означает только: **из принятого snapshot детерминированно выводится нейтральное causal opportunity field**.

E3.2 НЕ означает:

- biome classification;
- species assignment;
- population truth;
- canonical SD regions;
- production environment/time ownership;
- production ecology authority;
- XFER1 readiness.

## 9. Следующий gate

После merge exact candidate в `feature/eco-evolutionary-ecology` можно materialize canonical ECO acceptance state и авторизовать:

**ECO.EVO3 / E3.3 Research Ecology Decomposition**.

E3.3 должен потреблять accepted E3.2 opportunity field, создавать только research-namespaced region/patch identities и не создавать/изменять canonical SD domains.

До merge canonical ECO frontier по-прежнему считается E3.2 AUTHORIZED, а не E3.2 ACCEPTED.
