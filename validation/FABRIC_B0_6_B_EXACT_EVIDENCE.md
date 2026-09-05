# FABRIC B0.6-B — Deterministic Selection: EXACT PASS

## Exact subject и runtime

Branch: `research/fabric-bake0-6-adaptive-physical-fidelity-r1`.
Runtime HEAD: `2254b450b4d31832a6c143fc85096372679c6bc6`.
Runtime TREE: `82532abb755b6b652b84a96ff5d92a8225cd8dba`.
Godot: `4.7.1.stable.double.custom_build.a13da4feb`.
Binary SHA-256: `bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7`.

Два завершённых запуска из разных новых Git checkout: `exact-a` и `exact-b`.
В обоих fresh import: exit 0, fatal 0; runtime runner: exit 0. Это измеренные
результаты, не перенос прежних PASS и не GitHub Actions, остающийся в очереди.
Machine evidence: `validation/fabric_b0_6/exact-replay.v1.json`.
Raw archive: `DWS_B0_6_EXACT_RUNTIME_EVIDENCE.zip`, SHA-256 `f0fe97043abd8b1bc774a9e6c471b46c6f74b72d999bd836f1368b6fd3f2faaf`.

## Реализация и acceptance

Implementation: `scripts/research/fabric_bake0/adaptive_physical_fidelity_selector_v1.gd`.
Runner: `RUN_FABRIC_B0_6_B_TESTS.sh`.
Assertions на каждый replay: **44 = 44**.
Результат обоих запусков: **PASS**, exit **0**.

SAFEST, CHEAPEST_SAFE и HOLD_IF_SAFE; фиксированный tie-break; инвариант порядка ключей; rehashed/повреждённый envelope; неизвестная policy; пустой safe set; никакая малая цена не разрешает unsafe fidelity. CHEAPEST_SAFE минимизирует declared cost внутри safe prefix, а minimum_safe_fidelity остаётся границей разрешённого упрощения.

## Fresh-process equality

Оба запуска дали одинаковые значения:

```text
B06B_SELECTION_HASH=d6c9c6aa07e0bd741a0fa50bb9d7ca9a10291043c680675f06fd58beb3818939
```
