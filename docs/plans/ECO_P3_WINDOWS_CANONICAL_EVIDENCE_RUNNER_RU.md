# ECO P3 — Windows Canonical Evidence Runner

Статус: `IMPLEMENTED / EVIDENCE-ONLY / NO ACCEPTANCE MUTATION`.

Ветка: `feature/eco-evolutionary-ecology`.

`RUN_ECO_P3_WINDOWS_CANONICAL_EVIDENCE.ps1` выбирает первый незакрытый canonical checkpoint и собирает exact Windows evidence. Он не меняет validation status и не выполняет lifecycle acceptance.

## Поддерживаемые stages

```text
Auto
P31
P32
P33
P34
P35
P36
P37
P38
```

`Auto` выбирает первый checkpoint, чей validation status не начинается с `ACCEPTED`. При текущем lifecycle это по-прежнему `P33`.

Строгая последовательность:

```text
P3.3 Windows canonical -> separate P3.3 acceptance
P3.4 Windows canonical -> separate P3.4 acceptance
P3.5 Windows canonical -> separate P3.5 acceptance
P3.6 Windows canonical -> separate P3.6 acceptance
P3.7 Windows canonical -> separate P3.7 acceptance
P3.8 Windows canonical -> separate P3.8 acceptance / P3 route complete
```

Explicit stage также fail-closed проверяет accepted parent: P34 требует P33 accepted, P35 требует P34 accepted, P36 требует P35 accepted, P37 требует P36 accepted, P38 требует P37 accepted.

## Exact immutable aggregates

```text
P2.8 ba4e4bcef779764c86b20f1a76b452e0a2edcc88d351a1f9b4d2d41e10c420d6
P3.1 f3e5ff9efbdee004cde58bc7de4a971cc9a17b51a13060cfc98df548c7cc425a
P3.2 172ff809b1442fc43c2534c46f1fe59363efda7d04a3f128832d61e39e144639
P3.3 37342327500b79f71ff2f5adbab51b659015311039ae5105eb00bb1705ac6c41
P3.4 a4464e5d42fb4a9e29c4a6ddfcb4c338ecbb4547bcd8bd80f430a7565df90813
P3.5 255912c4da9f1296d11f9e64bf91812ae3d32dff2726b4866c4ba761be8b8c83
P3.6 a7abcc49c2b9e7d473ceefb147996cb2febf6248bafe7004e3d5da01827cc5cc
P3.7 ef05ffb15d33819d3a6c4a1d534670e570ecb2ec674ad4a232e151e680a0e53a
P3.8 6132820a5c6597765b4f3abeeb8cf9fc9e6aaffb90ba83a1263997b17fc6f3a0
```

## P3.6/P3.7/P3.8 pinned surfaces

```text
RUN_ECO_P3_6_TESTS.ps1
12b7da45290c52c420a7629ae2b6d0c3b0a558b6

scripts/research/ecology/plant_disturbance_succession_v1.gd
ee83e97e3f4dbea23a591e745101aa3e2d235433

tests/research/ecology/eco_p3_6_disturbance_succession_acceptance.gd
ef8e8565246fb454ed6483f95df3b33c1d253802

RUN_ECO_P3_7_TESTS.ps1
51d326ad204a6c5bf6835784de6ec8de7a058265

scripts/research/ecology/plant_multi_niche_coexistence_v1.gd
7379c422f2d3f5723a2bfff8b46790f9cce30ddc

tests/research/ecology/eco_p3_7_multi_niche_coexistence_acceptance.gd
d14a24aaef42379ed199b9fbe3b4c3e9db58e15d

RUN_ECO_P3_8_TESTS.ps1
51483ce2ae398a075a3aa829c6bd3b347d81752e

scripts/research/ecology/plant_ecosystem_persistence_v1.gd
3d752f0d0a91fbbca5303b8ac7d49a8d8065c14e

tests/research/ecology/eco_p3_8_ecosystem_persistence_acceptance.gd
e0cef778f69ddd78b3f7d7aba6c3e2b8b9eef51c
```

Collector также пинит все более ранние P2.8/P3.1..P3.5 runner/kernel/test surfaces, exact Godot `4.7.1.stable.double.custom_build.a13da4feb`, текущий branch, clean tracked worktree, HEAD/tree и validation blobs/statuses.

## Использование

```powershell
$Godot = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"
.\RUN_ECO_P3_WINDOWS_CANONICAL_EVIDENCE.ps1 -GodotPath $Godot
```

Explicit пример:

```powershell
.\RUN_ECO_P3_WINDOWS_CANONICAL_EVIDENCE.ps1 -Stage P36 -GodotPath $Godot
```

P36 будет заблокирован, пока P3.5 не `ACCEPTED*`; P37 требует P3.6 `ACCEPTED*`, а P38 — P3.7 `ACCEPTED*`. При текущем lifecycle `Auto` всё равно выбирает P33.

Успешный run записывает raw `.log` и evidence `.json` в `test-results/ecology/p3-windows-canonical/`, включая observed aggregate/parent, SHA-256 raw log, source pins, validation status, host/Godot identity и `acceptance_mutation_performed=false`.
