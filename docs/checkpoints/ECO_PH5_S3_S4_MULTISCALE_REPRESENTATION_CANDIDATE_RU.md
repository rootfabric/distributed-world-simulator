# ECO.PH5-S3/S4 — Multi-Scale Representation + Robustness — CANDIDATE

Статус: `EXACT WINDOWS AUTOMATED CORE PASS / GRAPHICAL RERUN PENDING AFTER LAB PARSE FIX / RESEARCH_ONLY`.

Текущий fix head: `62c8431a3af1fe03401c2bca97cafb99dc6fc641`.

Принятый родитель: `ECO.PH5-S2 @ ddf4d89f8127efbbea7d0571192e6297127a6ec0`.

## Реализованный surface

PH5-S3 имеет пять явных representation tiers:

`TIER_0_FULL -> TIER_1_REDUCED -> TIER_2_CANOPY -> TIER_3_IMPOSTOR -> TIER_4_POPULATION_ONLY`.

Реализованы deterministic tier selection/hysteresis, strict SHA-256 truth validation, real reduced geometry cost, canopy materialization, настоящий Godot billboard impostor, population-only без individual geometry, unified materializer с fail-closed сверкой declared/actual primitive counts, S4 churn/invalid-input robustness, canonical PH2 phenotype × tier matrix и graphical lab.

## Exact Windows automated evidence

Engine: `Godot 4.7.1.stable.double.custom_build.a13da4feb`.

Accepted parent regression:

- PH5-S1 focused: `PASS (720)`;
- PH5-S1 restart: `PASS (4)`;
- PH5-S2 focused: `PASS (387)`;
- PH5-S2 visual smoke: `PASS (12)`;
- PH5-S2 restart: `PASS (5)`;
- accepted S2 hashes preserved: `2e66860bff80fbf56274e211fcefe0ba4f895a39e76e153e835021a814305f0f` / `5b869596e4c341f1f43aa457828016ec8af657a1c0e771b22a7348f1e8ae743e`.

PH5-S3/S4:

- tier policy: `PASS (49)`;
- canopy/impostor: `PASS (16)`;
- exact Windows canopy hash: `3acb4e234f924db8ea0a8076ac3e00ce34e56b5bca5fb4fde15975d0dc1b53b2`;
- exact Windows impostor hash: `287c025c96f0a4b6ea398ee3cada6ba1fba41451c634568d7f0c5f106303ea25`;
- real multiscale materialization: `PASS (61)`;
- materialization matrix hash: `f0a2b391c2c1ded19f8d44e0fb46b66256ad98e09366eab40b094ea4903e3b20`;
- S4 robustness: `PASS (5026)`;
- churn digest: `dea866454f7655067fe739803c00663a0bb08c6f1649ce899044c5a4ea04fb51`;
- canonical PH2 phenotype × five-tier matrix: `PASS (430)`;
- canonical matrix hash: `e0522bb289060d064134a3955a3979a9b5fc0066500d5ca082f3eaf99666a68d`.

Это уже закрывает automated truth-invariance/matrix часть checkpoint.

## Найденный graphical blocker и fix

Первый exact-Windows graphical smoke на head `14e1c7aa...` остановился на parse error:

`Cannot infer the type of distance_scale variable`.

Причина: динамическое индексирование нетипизированного literal Array в lab script.

Исправлено commit:

`62c8431a3af1fe03401c2bca97cafb99dc6fc641 — fix(eco): type S4 lab distance scale for Godot 4.7`.

Шкала вынесена в:

`const DISTANCE_SCALE_BY_TIER: Array[float] = [1.0, 1.8, 3.2, 7.0, 12.0]`

и используется через explicit `distance_scale: float`.

На Linux double той же engine revision patched scene smoke прошёл `PASS (40 assertions)`. Это подтверждает parse/scene wiring fix, но не заменяет exact-Windows graphical gate и human observation.

## Оставшийся gate

На Windows после `git pull` достаточно повторить:

```powershell
$Godot = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"
.\RUN_ECO_PH5_S3_S4_TESTS.ps1 -GodotPath $Godot
.\OPEN_ECO_PH5_S4_LAB.ps1 -GodotPath $Godot
```

Для graphical acceptance проверить:

- `FULL -> REDUCED -> CANOPY -> IMPOSTOR -> POPULATION_ONLY` действительно визуально различаются;
- при переключении tiers в одном environment `growth_graph_hash` остаётся тем же;
- `POPULATION_ONLY` не показывает individual plant geometry;
- `Q/E` меняет phenotype/GrowthGraph независимо от representation tier.

## Decision boundary

Сейчас:

`AUTOMATED_CORE_PASS_GRAPHICAL_GATE_PENDING`.

`ECO.PH RESEARCH COMPLETE` пока не выставлен. После exact-Windows smoke PASS + human graphical PASS можно принять PH5-S3/S4, синхронизировать roadmap/passport и остановиться на предусмотренной развилке:

`ECO.CONV0 | ECO.CAL1`.
