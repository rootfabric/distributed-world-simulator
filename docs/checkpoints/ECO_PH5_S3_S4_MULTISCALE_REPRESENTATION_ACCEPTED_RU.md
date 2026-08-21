# ECO.PH5-S3/S4 — Multi-Scale Representation + Robustness — ACCEPTED

Статус: `ACCEPTED / RESEARCH_ONLY / ECO.PH RESEARCH COMPLETE`.

Принятый implementation tree эквивалентен `d40aaeb801f0915de1cf5400f778ee039b823b29`. После пользовательского graphical gate появился конкурентный commit `74aedd27a23e0ef0178757985b66cbc3561b6f6d`, повторно открывавший S3 core; он был явно отклонён commit `236d240390d2e0536bcc45875acfaeb8b9a57bcc`. Git compare `d40aaeb8 -> 236d2403` имеет `files=[]`, поэтому текущий PH5 tree побитово соответствует проверенному acceptance tree.

## Exact Windows evidence

Engine: `Godot 4.7.1.stable.double.custom_build.a13da4feb`.

Accepted parent regression:

- PH5-S1 focused: `PASS (720 assertions)`;
- PH5-S1 restart: `PASS (4 assertions)`;
- PH5-S2 focused: `PASS (387 assertions)`;
- PH5-S2 visual smoke: `PASS (12 assertions)`;
- PH5-S2 restart: `PASS (5 assertions)`;
- PH5-S2 reference branch+leaf geometry: `2e66860bff80fbf56274e211fcefe0ba4f895a39e76e153e835021a814305f0f`;
- PH5-S2 full geometry: `5b869596e4c341f1f43aa457828016ec8af657a1c0e771b22a7348f1e8ae743e`.

PH5-S3:

- tier policy: `PASS (49 assertions)`;
- canopy/impostor materialization: `PASS (16 assertions)`;
- canopy hash: `3acb4e234f924db8ea0a8076ac3e00ce34e56b5bca5fb4fde15975d0dc1b53b2`;
- impostor hash: `287c025c96f0a4b6ea398ee3cada6ba1fba41451c634568d7f0c5f106303ea25`;
- real multiscale materialization: `PASS (61 assertions)`;
- materialization matrix hash: `f0a2b391c2c1ded19f8d44e0fb46b66256ad98e09366eab40b094ea4903e3b20`.

PH5-S4:

- representation robustness: `PASS (5026 assertions)`;
- deterministic churn digest: `dea866454f7655067fe739803c00663a0bb08c6f1649ce899044c5a4ea04fb51`;
- canonical contrasting PH2 phenotype × five-tier matrix: `PASS (430 assertions)`;
- canonical matrix hash: `e0522bb289060d064134a3955a3979a9b5fc0066500d5ca082f3eaf99666a68d`;
- exact-Windows multiscale visual lab smoke after Godot 4.7 type fix: `PASS (40 assertions)`.

## Graphical evidence

User executed `OPEN_ECO_PH5_S4_LAB.ps1` on the exact Windows double build after the smoke PASS and reported the acceptance procedure completed.

Graphical decision: `PASS_BY_USER_CONFIRMATION_AFTER_ACCEPTANCE_LAB_EXECUTION`.

The accepted graphical contract is the previously declared gate:

`FULL -> REDUCED -> CANOPY -> IMPOSTOR -> POPULATION_ONLY` with stable `growth_graph_hash` while switching tier for one environment, environment-driven phenotype changes remaining independent from tier, and `POPULATION_ONLY` requiring no individual plant geometry.

## Accepted invariants

- `LOD / distance / screen size / renderer profile != ecology identity/state`;
- `GrowthGraph -> PlantRenderDescription -> representation` is one-way derived projection;
- real materialization counts must match declared tier counts;
- `TIER_0_FULL` and `TIER_1_REDUCED` use real ArrayMesh/MultiMesh paths;
- `TIER_2_CANOPY` and `TIER_3_IMPOSTOR` are derived far representations;
- `TIER_3_IMPOSTOR` uses a real Godot billboard material;
- `TIER_4_POPULATION_ONLY` requires no individual plant node/mesh/GrowthGraph materialization;
- tier churn, dematerialization and rematerialization cannot modify accepted ecology/resource/selection/lifecycle truth.

## Scope boundary

PH5 acceptance does **not** define canonical population storage, WorldAddress, World Query, Material Ontology, promotion/dormancy semantics, persistence, authority, network replication policy or global work scheduling.

The rejected overlapping S3 experiment contained useful ideas about aggregate population projection and bounded visual sampling. Those ideas belong to `ECO.CONV0` requirements/design, not to reopening accepted PH5 renderer truth.

## Decision

`ECO.PH5-S3 ACCEPTED`.

`ECO.PH5-S4 ACCEPTED`.

`ECO.PH RESEARCH COMPLETE`.

Next route is defined by `ECO_CONV0_GLOBAL_ALIGNMENT_RU.md`: execute a bounded `CONV0-A` consumer-requirements alignment first, then move the main research lane to `CAL1`; final `CONV0-B` contract freeze waits canonical R3/WQ/MAT foundations.
