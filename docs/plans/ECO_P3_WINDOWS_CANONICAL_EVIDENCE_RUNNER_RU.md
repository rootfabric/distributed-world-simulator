# ECO P3 — Windows Canonical Evidence Runner

Статус: `IMPLEMENTED / EVIDENCE-ONLY / NO ACCEPTANCE MUTATION`.

Ветка: `feature/eco-evolutionary-ecology`.

## Цель

`RUN_ECO_P3_WINDOWS_CANONICAL_EVIDENCE.ps1` собирает точное Windows canonical evidence для следующего незакрытого P3 gate.

Он не изменяет validation JSON, не переводит checkpoint в `ACCEPTED` и не открывает P3.3.

Основная последовательность остаётся строгой:

```text
P3.1 Windows canonical evidence
-> review evidence
-> separate P3.1 ACCEPTED lifecycle commit
-> P3.2 Windows canonical evidence
-> review evidence
-> separate P3.2 ACCEPTED lifecycle commit
-> P3.3 may open
```

## Fail-closed preflight

Перед запуском canonical runner collector требует:

- exact branch `feature/eco-evolutionary-ecology`;
- отсутствие staged/unstaged изменений tracked files;
- exact Godot `4.7.1.stable.double.custom_build.a13da4feb`;
- byte-identical pinned P2.8/P3.1/P3.2 runner, kernel и acceptance-test surfaces;
- для P3.2 — factual P3.1 validation status `ACCEPTED*`.

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
```

The collector also records its own current blob, both validation-file blobs, current HEAD/tree, PowerShell version, OS, architecture and Godot path/version into evidence JSON.

## Expected immutable aggregates

```text
ECO.EVO1/P2.8
ba4e4bcef779764c86b20f1a76b452e0a2edcc88d351a1f9b4d2d41e10c420d6

ECO.P3.1
f3e5ff9efbdee004cde58bc7de4a971cc9a17b51a13060cfc98df548c7cc425a

ECO.P3.2
172ff809b1442fc43c2534c46f1fe59363efda7d04a3f128832d61e39e144639
```

A canonical run fails if the observed aggregate or parent identity differs from those values.

## Usage

Normal mode selects the next legal stage from validation state:

```powershell
$Godot = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"
.\RUN_ECO_P3_WINDOWS_CANONICAL_EVIDENCE.ps1 -GodotPath $Godot
```

Explicit P3.1:

```powershell
.\RUN_ECO_P3_WINDOWS_CANONICAL_EVIDENCE.ps1 -Stage P31 -GodotPath $Godot
```

Explicit P3.2 is deliberately blocked until P3.1 is already `ACCEPTED*`:

```powershell
.\RUN_ECO_P3_WINDOWS_CANONICAL_EVIDENCE.ps1 -Stage P32 -GodotPath $Godot
```

## Evidence output

Default directory:

```text
test-results/ecology/p3-windows-canonical/
```

Each successful run writes:

```text
P31-<UTC>-<HEAD12>.log
P31-<UTC>-<HEAD12>.json
```

or:

```text
P32-<UTC>-<HEAD12>.log
P32-<UTC>-<HEAD12>.json
```

JSON contains:

- stage/result;
- UTC timestamp;
- repository/branch/HEAD/tree;
- tracked-worktree cleanliness assertion;
- host/PowerShell/Godot identity;
- pinned source blob identities;
- validation status/blob identities;
- canonical runner name;
- observed aggregate and parent hash;
- raw-log filename and SHA-256;
- immutable expected P2.8/P3.1/P3.2 aggregates;
- explicit `acceptance_mutation_performed = false`.

The console additionally prints `evidence_sha256` after writing the JSON.

## Current legal next run

At the current candidate state, `-Stage Auto` resolves to `P31`.

P3.2 remains fail-closed until a separate reviewed lifecycle commit changes P3.1 validation to `ACCEPTED*`.
