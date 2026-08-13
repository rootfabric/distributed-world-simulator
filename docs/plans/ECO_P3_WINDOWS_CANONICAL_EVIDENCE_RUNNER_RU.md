# ECO P3 — Windows Canonical Evidence Runner

Статус: `IMPLEMENTED / EVIDENCE-ONLY / P3.1→P3.3 / NO ACCEPTANCE MUTATION`.

Ветка: `feature/eco-evolutionary-ecology`.

## Цель

`RUN_ECO_P3_WINDOWS_CANONICAL_EVIDENCE.ps1` собирает exact Windows canonical evidence для следующего незакрытого P3 gate.

Collector не изменяет validation JSON, не переводит checkpoint в `ACCEPTED` и не открывает следующий P3 checkpoint. Acceptance всегда остаётся отдельным lifecycle commit после проверки evidence.

Последовательность:

```text
P3.1 Windows canonical evidence
-> separate P3.1 ACCEPTED lifecycle commit
-> P3.2 Windows canonical evidence
-> separate P3.2 ACCEPTED lifecycle commit
-> P3.3 Windows canonical evidence
-> separate P3.3 ACCEPTED lifecycle commit
-> P3.4 may open
```

## Fail-closed preflight

Перед canonical runner collector требует:

- exact branch `feature/eco-evolutionary-ecology`;
- отсутствие staged/unstaged изменений tracked files;
- exact Godot `4.7.1.stable.double.custom_build.a13da4feb`;
- byte-identical pinned P2.8/P3.1/P3.2/P3.3 runner, kernel и acceptance-test surfaces;
- для P3.2 — factual P3.1 validation status `ACCEPTED*`;
- для P3.3 — factual P3.2 validation status `ACCEPTED*`.

Pinned Git blob identities:

```text
RUN_ECO_EVO1_P2_8_TESTS.ps1
2f263f562bbdde60e2cf2868c1bb30dd49ed4835

RUN_ECO_P3_1_TESTS.ps1
3a4f1cf35f530da08485638cd907283cd9d6cc30

scripts/research/ecology/plant_resource_competition_v1.gd
c667569b40775a1a1898d7b911a610ca5795f380

tests/research/ecology/eco_p3_1_resource_competition_acceptance.gd
421bf16651da64f92690ba2d676ecee7b3f97cf0

RUN_ECO_P3_2_TESTS.ps1
9056e180bf806547b6ecd8ae9a75f8cc83fccdfc

scripts/research/ecology/plant_density_carrying_capacity_v1.gd
8e635f8915ad53cac9a37917df32036cf92907b2

tests/research/ecology/eco_p3_2_density_carrying_capacity_acceptance.gd
c07e2c211ac9a5bf8ce58f323b3684b1e1e04028

RUN_ECO_P3_3_TESTS.ps1
f6ebb17bc26b916711406c1808779f22dd20c496

scripts/research/ecology/plant_spatial_dispersal_v1.gd
43a25eb0e6677749162de99c251231c94d243dc1

tests/research/ecology/eco_p3_3_spatial_dispersal_acceptance.gd
9911c9197663098e1efa8875332b9d7c88ca34c6
```

Collector также пишет в evidence JSON собственный current blob, validation-file blobs/status для P3.1/P3.2/P3.3, HEAD/tree, PowerShell version, OS/architecture и exact Godot identity.

## Expected immutable aggregates

```text
ECO.EVO1/P2.8
ba4e4bcef779764c86b20f1a76b452e0a2edcc88d351a1f9b4d2d41e10c420d6

ECO.P3.1
f3e5ff9efbdee004cde58bc7de4a971cc9a17b51a13060cfc98df548c7cc425a

ECO.P3.2
172ff809b1442fc43c2534c46f1fe59363efda7d04a3f128832d61e39e144639

ECO.P3.3
37342327500b79f71ff2f5adbab51b659015311039ae5105eb00bb1705ac6c41
```

Canonical run fail-closed останавливается, если observed aggregate или parent identity отличается от ожидаемого immutable value.

## Usage

Normal mode выбирает следующий legal stage по factual validation status:

```powershell
$Godot = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"
.\RUN_ECO_P3_WINDOWS_CANONICAL_EVIDENCE.ps1 -GodotPath $Godot
```

Explicit stages:

```powershell
.\RUN_ECO_P3_WINDOWS_CANONICAL_EVIDENCE.ps1 -Stage P31 -GodotPath $Godot
.\RUN_ECO_P3_WINDOWS_CANONICAL_EVIDENCE.ps1 -Stage P32 -GodotPath $Godot
.\RUN_ECO_P3_WINDOWS_CANONICAL_EVIDENCE.ps1 -Stage P33 -GodotPath $Godot
```

`P32` fail-closed blocked пока P3.1 не `ACCEPTED*`; `P33` blocked пока P3.2 не `ACCEPTED*`.

## Evidence output

Default directory:

```text
test-results/ecology/p3-windows-canonical/
```

Successful run writes matching raw log + JSON pair:

```text
P31-<UTC>-<HEAD12>.log/.json
P32-<UTC>-<HEAD12>.log/.json
P33-<UTC>-<HEAD12>.log/.json
```

JSON содержит:

- stage/result;
- UTC timestamp;
- repository/branch/HEAD/tree;
- tracked-worktree cleanliness assertion;
- host/PowerShell/Godot identity;
- pinned source blob identities;
- P3.1/P3.2/P3.3 validation status/blob identities;
- canonical runner name;
- observed aggregate and parent hash;
- raw-log filename and SHA-256;
- immutable expected P2.8/P3.1/P3.2/P3.3 aggregates;
- explicit `acceptance_mutation_performed = false`;
- next lifecycle action for the selected stage.

Console additionally prints `evidence_sha256` after JSON creation.

## Current legal next run

Current factual state:

```text
P3.1 = ACCEPTED_EXACT_WINDOWS_CANONICAL
P3.2 = ACCEPTED_EXACT_WINDOWS_CANONICAL
P3.3 = CANDIDATE_TARGETED_LINUX_PASS_EXACT_WINDOWS_CANONICAL_PENDING
```

Therefore `-Stage Auto` resolves to:

```text
P33 / P3.3 Spatial Dispersal
```

P3.4 remains closed until a separate reviewed lifecycle commit accepts exact P3.3 Windows canonical evidence.
