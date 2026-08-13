# ECO P3 — Windows Canonical Evidence Runner

Статус: `IMPLEMENTED / EVIDENCE-ONLY / P3.1→P3.5 / NO ACCEPTANCE MUTATION`.

Ветка: `feature/eco-evolutionary-ecology`.

## Цель

`RUN_ECO_P3_WINDOWS_CANONICAL_EVIDENCE.ps1` собирает exact Windows canonical evidence для следующего незакрытого P3 gate.

Collector не изменяет validation JSON, не переводит checkpoint в `ACCEPTED` и не открывает следующий P3 checkpoint. Acceptance всегда остаётся отдельным lifecycle commit после проверки evidence.

Строгая последовательность:

```text
P3.1 Windows canonical -> accept P3.1
P3.2 Windows canonical -> accept P3.2
P3.3 Windows canonical -> accept P3.3
P3.4 Windows canonical -> accept P3.4
P3.5 Windows canonical -> accept P3.5
P3.6 may open
```

## Fail-closed preflight

Collector требует:

- exact branch `feature/eco-evolutionary-ecology`;
- отсутствие staged/unstaged tracked changes;
- exact Godot `4.7.1.stable.double.custom_build.a13da4feb`;
- byte-identical pinned P2.8/P3.1/P3.2/P3.3/P3.4/P3.5 runner, kernel и acceptance-test surfaces;
- P3.2 требует `P3.1 = ACCEPTED*`;
- P3.3 требует `P3.2 = ACCEPTED*`;
- P3.4 требует `P3.3 = ACCEPTED*`;
- P3.5 требует `P3.4 = ACCEPTED*`.

Новые P3.5 pins:

```text
RUN_ECO_P3_5_TESTS.ps1
510ceaa8ed82902ea8a0b0c62f87fe038894b674

scripts/research/ecology/plant_seasonal_world_v1.gd
649d26457ac8383f890f0dfca890353cc200ee7e

tests/research/ecology/eco_p3_5_seasonal_world_acceptance.gd
c91ed0c25c418be1a7c7c4352423b7214c8706f8
```

Предыдущие P3.1→P3.4 pins остаются неизменными и также проверяются collector'ом.

## Immutable aggregates

```text
ECO.EVO1/P2.8
ba4e4bcef779764c86b20f1a76b452e0a2edcc88d351a1f9b4d2d41e10c420d6

ECO.P3.1
f3e5ff9efbdee004cde58bc7de4a971cc9a17b51a13060cfc98df548c7cc425a

ECO.P3.2
172ff809b1442fc43c2534c46f1fe59363efda7d04a3f128832d61e39e144639

ECO.P3.3
37342327500b79f71ff2f5adbab51b659015311039ae5105eb00bb1705ac6c41

ECO.P3.4
a4464e5d42fb4a9e29c4a6ddfcb4c338ecbb4547bcd8bd80f430a7565df90813

ECO.P3.5
255912c4da9f1296d11f9e64bf91812ae3d32dff2726b4866c4ba761be8b8c83
```

Canonical run fail-closed останавливается при любом несовпадении aggregate или parent identity.

## Usage

Следующий legal stage автоматически:

```powershell
$Godot = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"
.\RUN_ECO_P3_WINDOWS_CANONICAL_EVIDENCE.ps1 -GodotPath $Godot
```

Explicit stages:

```powershell
.\RUN_ECO_P3_WINDOWS_CANONICAL_EVIDENCE.ps1 -Stage P31 -GodotPath $Godot
.\RUN_ECO_P3_WINDOWS_CANONICAL_EVIDENCE.ps1 -Stage P32 -GodotPath $Godot
.\RUN_ECO_P3_WINDOWS_CANONICAL_EVIDENCE.ps1 -Stage P33 -GodotPath $Godot
.\RUN_ECO_P3_WINDOWS_CANONICAL_EVIDENCE.ps1 -Stage P34 -GodotPath $Godot
.\RUN_ECO_P3_WINDOWS_CANONICAL_EVIDENCE.ps1 -Stage P35 -GodotPath $Godot
```

## Evidence output

Default directory:

```text
test-results/ecology/p3-windows-canonical/
```

Successful stage writes matching `.log` and `.json`:

```text
P31-<UTC>-<HEAD12>.log/.json
P32-<UTC>-<HEAD12>.log/.json
P33-<UTC>-<HEAD12>.log/.json
P34-<UTC>-<HEAD12>.log/.json
P35-<UTC>-<HEAD12>.log/.json
```

Evidence JSON records repository/branch/HEAD/tree, tracked-worktree cleanliness, OS/PowerShell/Godot identity, all pinned source blobs, P3.1→P3.5 validation blob/status identities, canonical runner, observed aggregate/parent, raw-log SHA-256 and expected immutable aggregates.

`acceptance_mutation_performed = false` remains mandatory.

## Current legal next run

Current lifecycle state remains:

```text
P3.1 = ACCEPTED_EXACT_WINDOWS_CANONICAL
P3.2 = ACCEPTED_EXACT_WINDOWS_CANONICAL
P3.3 = CANDIDATE / Windows canonical pending
P3.4 = implementation candidate / blocked on P3.3 ACCEPTED
P3.5 = implementation candidate / blocked on P3.4 ACCEPTED
```

Therefore `-Stage Auto` still resolves to `P33`.

After a separate P3.3 acceptance commit Auto advances to `P34`; after P3.4 acceptance it advances to `P35`. P3.5 targeted Linux PASS never authorizes P3.6 by itself.
