# FABRIC B0.6-C — Transition / Hysteresis: EXACT PASS

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

Implementation: `scripts/research/fabric_bake0/adaptive_physical_fidelity_controller_v1.gd`.
Runner: `RUN_FABRIC_B0_6_C_TESTS.sh`.
Assertions на каждый replay: **679 = 679**.
Результат обоих запусков: **PASS**, exit **0**.

Немедленная safety promotion, включая causal wake; задержанная одноуровневая demotion; consecutive-safe window и cooldown на authoritative ticks; сброс streak при spike/пропуске tick; 80 шумовых ticks без thrash; устойчивое улучшение всё же понижает fidelity; повторный stimulus не создаёт второго transition; BRIDGE-2 ownership остаётся единственным.

## Fresh-process equality

Оба запуска дали одинаковые значения:

```text
B06C_TRANSITION_HASH=e93dadfc821fb8299fc6a75d140a493be790860dcd294cd687403717d237f0aa
```
