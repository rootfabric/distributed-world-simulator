# ECO P3.6 — Disturbance & Succession — CANDIDATE

Статус: `IMPLEMENTATION CANDIDATE / TARGETED LINUX PASS / P3.5 ACCEPTANCE + EXACT WINDOWS CANONICAL PENDING`.

## Scope

P3.6 добавляет детерминированный слой disturbance/recovery/succession поверх immutable P3.5 seasonal result. Он не меняет P3.5 и не владеет production hazard scheduling.

Disturbance задаётся непрерывными pressure channels `heat/flood/drought` и общей severity. Lineage response определяется только явными functional traits: resistance, recovery rate, pioneer capacity. Никаких таблиц победителей по ID нет.

Recovery считается напрямую из post-disturbance loss и `recovery_years`, без накопительного timestep state. Seasonal `light/water/nutrients` ограничивают recovery pool. Итоговая biomass не может превысить pre-disturbance reference, но composition может меняться, что даёт succession.

## Targeted exact-Godot evidence

```text
Godot 4.7.1.stable.double.custom_build.a13da4feb
P3.5 parent regression: PASS (74 assertions)
P3.6 A/B/C: PASS (33 assertions each; byte-identical logs)
aggregate_hash=a7abcc49c2b9e7d473ceefb147996cb2febf6248bafe7004e3d5da01827cc5cc
heat_hash=7c6b21d85342835f8c29aad745ed3931fce7b50284509f7eaf0a4f31e0214f10
flood_hash=d7fb655873afb749433151d9262f04f9e9542ffb94e3c7cea04b8538fc534f94
drought_hash=2ac7cd6beaf26326a88e7ad16c47fe25d0022d69c19e5b7297df6aa6b8261994
log_sha256=71cb3bbfac17b2bc3667b0ffc3ab8055ff0a9c9c04e2c7d1cdb63a4cf0c0c537
```

## Gate

`RUN_ECO_P3_6_TESTS.ps1` fail-closed требует `P3.5 = ACCEPTED*`, затем прогоняет P3.5 parent regression и два fresh P3.6 процесса. Targeted PASS не является Windows canonical acceptance.
