# ECO.P1A-S4 — Determinism, Sensitivity and Failure Classification — CANDIDATE

## Статус

`LOCAL_FOCUSED_PASS / EXACT_WINDOWS_PENDING`.

S4 проверяет, что принятая в S1/S2 экологическая модель не только визуально правдоподобна, но и воспроизводима, чувствительна к параметрам в объяснимом направлении и не содержит очевидных runaway/failure режимов.

## Что сделано

Добавлен research-only `ECO.P1A-S4.1` sensitivity harness. Он не меняет accepted S1 EnvironmentSample и не переписывает S2 resource/population equations.

Проверяются явные perturbations:

- moisture amplitude ±5%;
- sunlight amplitude ±5%;
- root cost ±5%;
- maintenance cost ±5%;
- flood penalty ±5%;
- root depth sweep;
- small shade-tolerance trait change.

Cost sweeps работают как диагностическое изменение уже рассчитанных S2 cost terms. Полная biomass dynamics остаётся в accepted `SinglePlantPatchSimulatorV1`.

## Determinism

Baseline фиксирован тремя hashes:

- summary: `327d211d24f8f74251e02f0ced22323b4120c18d9b42a9cfcf99974cf9accc5a`;
- full result: `cb1641a6b49dfa2be3f64c94f2ebc3240327eaca559d025d34e72ba74c0aa11e`;
- total biomass series: `7c621f1a8c302fdd10f60fd4e576b7688a3bd1065f84c84b7c391e5031f05e0c`.

Same-process replay и отдельный fresh Godot process дают те же hashes.

## Sensitivity

Baseline `17x17` имеет average initial net около `-0.116069`.

| Perturbation | Avg net |
|---|---:|
| moisture 0.95 | -0.145365 |
| BASE | -0.116069 |
| moisture 1.05 | -0.087506 |
| sunlight 0.95 | -0.139996 |
| sunlight 1.05 | -0.098353 |
| root cost 0.95 | -0.107908 |
| root cost 1.05 | -0.124231 |
| maintenance 0.95 | -0.086019 |
| maintenance 1.05 | -0.146119 |
| flood penalty 0.95 | -0.114360 |
| flood penalty 1.05 | -0.117778 |

Малые изменения не вызывают хаотических скачков и идут в ожидаемых направлениях.

Root depth не является free trait:

- global avg net при scale 0.50: `-0.142693`;
- scale 1.50: `-0.107649`;
- scale 2.20: `-0.128666`.

То есть польза сначала растёт, затем стоимость снова ухудшает общий результат. Локально deep root помогает dry ridge и одновременно ухудшает wet floodplain.

## Failure matrix

Локальный focused acceptance классифицировал:

- global extinction — PASS;
- unbounded biomass — PASS, biomass далеко от hard cap;
- one-field domination — PASS, одновременно активны WATER/LIGHT/NUTRIENT/FLOOD, крупнейший limiter <75% patches;
- free trait escalation — PASS;
- boundary seams — PASS;
- hidden biome conditionals — PASS source scan;
- presentation-resolution dependency — PASS;
- floating-point/replay divergence — PASS exact hash.

## Автоматический результат

Godot `4.7.1.stable.double.custom_build.a13da4feb`:

- S1 regression: `109/109`;
- S2 regression: `235/235`;
- S3 regression: `208/208`;
- S4 focused: `165/165`;
- separate-process restart replay: `5/5`.

## Windows gate

```powershell
cd C:\Godot\lunar-world-eco-evolutionary-ecology
git pull
$Godot = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"
.\RUN_ECO_P1A_S4_TESTS.ps1 -GodotPath $Godot
```

Если hashes совпадают и все parent regressions зелёные, S4 можно принять и открыть `P1A-S5 — P1A Acceptance + Evolution Decision`.
