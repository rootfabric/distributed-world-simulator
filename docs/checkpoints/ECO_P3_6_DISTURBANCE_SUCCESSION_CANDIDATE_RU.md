# ECO P3.6 — Disturbance & Succession — ACCEPTED

Статус: `ACCEPTED_EXACT_ATTACHED_GODOT_CANONICAL`.

Дата: 2026-08-13.

## Frozen identity

```text
aggregate=a7abcc49c2b9e7d473ceefb147996cb2febf6248bafe7004e3d5da01827cc5cc
parent_p3_5=255912c4da9f1296d11f9e64bf91812ae3d32dff2726b4866c4ba761be8b8c83
kernel=ee83e97e3f4dbea23a591e745101aa3e2d235433
test=ef8e8565246fb454ed6483f95df3b33c1d253802
Godot=4.7.1.stable.double.custom_build.a13da4feb
```

Полный сохранённый exact-Godot gate: P3.5 parent regression PASS (74 assertions), P3.6 A/B/C PASS (33 assertions each), byte-identical logs.

Свежая проверка текущих live kernels P3.3..P3.8 выполнена двумя отдельными Godot process; оба лога byte-identical (`18a21dfbc585326d971d88fda568d77e1a54ba84cef538c532ae73babfb03318`). В одном run 32 проверки. P3.6 проверяет bounded damage, recovery и pre-disturbance biomass ceiling.

Это attached-Godot acceptance по прямой Human-directed execution gate. Windows PASS не заявляется. P3.7 теперь разрешён к собственному gate, но этим checkpoint не принят.
