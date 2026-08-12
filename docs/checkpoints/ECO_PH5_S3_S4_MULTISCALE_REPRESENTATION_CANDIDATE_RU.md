# ECO.PH5-S3/S4 — Multi-Scale Representation + Robustness — CANDIDATE

Статус: `IMPLEMENTED / LOCAL GODOT PASS / EXACT WINDOWS + CANONICAL PH2 MATRIX + GRAPHICAL USER OBSERVATION PENDING / RESEARCH_ONLY`.

Текущий candidate head до контрольного evidence commit: `ec24f3c912b65376042e050d3c14df7e1c446efd`.

Принятый родитель: `ECO.PH5-S2 @ ddf4d89f8127efbbea7d0571192e6297127a6ec0`.

## Что реализовано

PH5-S3 теперь имеет пять явных representation tiers:

`TIER_0_FULL -> TIER_1_REDUCED -> TIER_2_CANOPY -> TIER_3_IMPOSTOR -> TIER_4_POPULATION_ONLY`.

Добавлены:

- deterministic tier selection + hysteresis;
- strict SHA-256 truth validation;
- canopy materialization;
- настоящий Godot billboard impostor (`BaseMaterial3D.BILLBOARD_ENABLED`);
- `POPULATION_ONLY` без individual mesh/node requirement;
- unified multiscale materializer, связывающий declared tier policy с фактическими ArrayMesh/MultiMesh/far primitive counts;
- fail-closed divergence checks между policy count и реальной materialization;
- PH5-S4 deterministic churn/invalid-input/rematerialization robustness;
- contrasting phenotype × five-tier canonical matrix harness;
- интерактивный multiscale graphical lab;
- единый exact-Windows runner, который сначала повторяет accepted PH5-S2 regression.

## Исправленный архитектурный разрыв

До unified materializer `TIER_1_REDUCED` декларировал `35%` branches и `20%` foliage, но legacy `BRANCH_LEAF_INSTANCED` profile materialize-ил `100%` branches и `70%` foliage. Это создавало ложный разрыв между representation cost policy и фактической Godot geometry.

Теперь S3 создаёт derived reduced profile variant с теми же `35%/20%`, пересчитывает profile hash и требует exact equality между declared и actual primitive counts. Старый accepted PH5-S2 profile не изменён.

## Локальное Godot evidence

Engine: `Godot 4.7.1.stable.double.custom_build.a13da4feb`.

- PH5-S3 tier policy: `PASS (49 assertions)`;
- PH5-S3 canopy/impostor: `PASS (16 assertions)`;
- canopy hash: `ba3b64b604f14e1ba2935c82e694605953480f0de77a0599faa2a495125fdac9`;
- impostor hash: `d292449bbcba5e61c60ac0fe7775ecdec274c45b9bc03c97c0b75bd03286c136`;
- PH5-S3 real multiscale materialization: `PASS (61 assertions)`;
- materialization matrix hash: `f0a2b391c2c1ded19f8d44e0fb46b66256ad98e09366eab40b094ea4903e3b20`;
- PH5-S4 robustness: `PASS (5026 assertions)`;
- deterministic churn digest: `dea86645cc86bb4996106047ad3d229eede83f74bf82f139d2480275942dfb51`.

Дополнительно новый S4 matrix/lab surface был локально прогнан с API-compatible synthetic probe fixture для проверки wiring/behavior:

- matrix harness: `PASS (430 assertions)`, interface-probe hash `6ebaa8e6a16a6083b517731ab004c43d5f384431561c3aa1e0cc33bc3d40f8b6`;
- visual lab smoke: `PASS (40 assertions)`.

Эти два synthetic результата **не являются canonical PH2 acceptance evidence** и не заменяют exact Windows run по настоящим `plant_render_description_probes_v1.gd`.

## PH5-S2 compatibility

Git compare `ddf4d89f... -> ec24f3c9...`:

- status `ahead`;
- ahead `12`;
- behind `0`;
- все изменённые paths относятся только к новым PH5-S3/S4 surfaces;
- ни один принятый PH5-S2 source/test/lab/runner path не изменён.

Следовательно accepted S2 implementation остаётся побитово тем же. Дополнительно новый runner всё равно запускает `RUN_ECO_PH5_S2_TESTS.ps1` первым parent gate.

## Exact Windows gate

Из корня `feature/eco-evolutionary-ecology`:

```powershell
cd C:\Godot\lunar-world-eco-evolutionary-ecology
git pull
$Godot = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"
.\RUN_ECO_PH5_S3_S4_TESTS.ps1 -GodotPath $Godot
```

Runner обязан получить PASS для:

1. accepted PH5-S2 parent regression;
2. S3 tier policy;
3. S3 canopy/impostor materialization;
4. S3 real multiscale materialization;
5. S4 5026+ robustness;
6. canonical contrasting PH2 phenotype × five-tier matrix;
7. S4 graphical lab smoke.

## Graphical gate

После automated PASS:

```powershell
.\OPEN_ECO_PH5_S4_LAB.ps1 -GodotPath $Godot
```

Controls:

- `Q/E` — contrasting PH2 environment;
- `A/D` или arrows — `FULL / REDUCED / CANOPY / IMPOSTOR / POPULATION_ONLY`.

Проверить:

- при смене tier в одном environment `growth_graph_hash` не меняется;
- FULL действительно detailed;
- REDUCED визуально и по primitive count дешевле FULL;
- CANOPY заменяет индивидуальную branch/leaf geometry объёмом canopy;
- IMPOSTOR является camera-facing billboard;
- POPULATION_ONLY не имеет individual plant geometry;
- смена environment меняет phenotype/GrowthGraph независимо от текущего tier.

## Decision boundary

До exact Windows + canonical PH2 matrix + graphical observation:

`PH5-S3/S4 = CANDIDATE_NOT_YET_ACCEPTED`.

После PASS можно заменить этот candidate на accepted checkpoints, синхронизировать roadmap/passport и поставить:

`ECO.PH RESEARCH COMPLETE`.

Только после этого достигается предусмотренная центральным маршрутом развилка `ECO.CONV0 | ECO.CAL1`. Ни одна из этих линий данным candidate не авторизована и не начата.
