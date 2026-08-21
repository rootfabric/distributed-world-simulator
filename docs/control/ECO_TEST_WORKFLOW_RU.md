# ECO Test Workflow

Статус: `ACTIVE`.

Цель: запускать ECO production tests из проекта без зависимости от текущей PowerShell-директории, без привязки test logic к конкретному абсолютному пути checkout и без необходимости переписывать рабочую ветку ради validation run.

## Основной Windows checkout

Текущий рабочий checkout пользователя:

```text
C:\distributed-world-simulator\distributed-world-simulator\
```

Этот путь не зашит в test logic. `RUN_ECO_TEST_WORKFLOW.ps1` определяет корень репозитория по собственному расположению и через `git rev-parse --show-toplevel`.

Exact Godot по умолчанию:

```text
C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe
```

Required identity:

```text
4.7.1.stable.double.custom_build.a13da4feb
```

## Единый repository-local entrypoint

Если рабочая ветка синхронизирована с нужным ECO HEAD, из корня проекта:

```powershell
$Godot = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"
.\RUN_ECO_TEST_WORKFLOW.ps1 -Suite current -GodotPath $Godot
```

Из любой другой директории:

```powershell
$Repo = "C:\distributed-world-simulator\distributed-world-simulator"
$Godot = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"
& "$Repo\RUN_ECO_TEST_WORKFLOW.ps1" -Suite current -GodotPath $Godot
```

`RUN_ECO_TEST_WORKFLOW.ps1` сам меняет рабочую директорию только на время тестов и затем возвращает её обратно.

## Divergent рабочая ветка: isolated validation workspace

Если `git pull --ff-only` сообщает `Not possible to fast-forward`, нельзя автоматически делать merge/rebase/reset рабочей копии только ради тестов.

Для этого committed bootstrap:

```text
RUN_ECO_VALIDATION_WORKSPACE.ps1
```

Он использует основной checkout только как источник `origin`, после чего создаёт/обновляет отдельную dedicated test-копию:

```text
C:\distributed-world-simulator\eco-validation-workspace\
```

В этой копии разрешена exact synchronization на `origin/feature/eco-evolutionary-ecology`, потому что она предназначена только для validation. Основной checkout не изменяется.

После того как bootstrap присутствует локально, стандартный запуск:

```powershell
$Repo = "C:\distributed-world-simulator\distributed-world-simulator"
$Godot = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"

& "$Repo\RUN_ECO_VALIDATION_WORKSPACE.ps1" `
    -SourceRepo $Repo `
    -Suite current `
    -GodotPath $Godot
```

Если рабочая ветка divergent и bootstrap ещё не появился в ней, его можно безопасно взять из remote branch, не изменяя рабочий checkout:

```powershell
$Repo = "C:\distributed-world-simulator\distributed-world-simulator"
$Godot = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"
$Bootstrap = Join-Path $env:TEMP "RUN_ECO_VALIDATION_WORKSPACE.ps1"

git -C $Repo fetch origin feature/eco-evolutionary-ecology
git -C $Repo show origin/feature/eco-evolutionary-ecology:RUN_ECO_VALIDATION_WORKSPACE.ps1 |
    Set-Content -LiteralPath $Bootstrap -Encoding UTF8

& $Bootstrap -SourceRepo $Repo -Suite current -GodotPath $Godot
```

Этот bootstrap path является штатным способом validation при local divergence. Он не является способом разрешения divergence рабочей feature-ветки; решение о merge/rebase/convergence принимается отдельно.

## Suites

```text
current   = P4.7 + P4.8 preparation
accepted  = P4.4 + P4.5 + P4.6 regression gates
full      = P4.4 + P4.5 + P4.6 + P4.7 + P4.8
p4.4      = RUN_ECO_P4_4_TESTS.ps1
p4.5      = RUN_ECO_P4_5_TESTS.ps1
p4.6      = RUN_ECO_P4_6_TESTS.ps1
p4.7      = RUN_ECO_P4_7_PREACCEPTANCE_TESTS.ps1
p4.8      = RUN_ECO_P4_8_PREACCEPTANCE_TESTS.ps1
```

`current` является стандартным продолжением текущего P4 frontier. `full` предназначен для полного regression evidence и заметно тяжелее.

Сам `RUN_ECO_TEST_WORKFLOW.ps1` не выполняет `git pull`, `git reset`, branch switch или другие Git mutations. Он тестирует ровно текущий checkout/HEAD и печатает `repo_root`, branch и HEAD перед запуском.

Git synchronization изолирована исключительно в `RUN_ECO_VALIDATION_WORKSPACE.ps1` и применяется только к dedicated validation clone.

## GitHub Actions

Project workflow:

```text
.github/workflows/eco-production-tests.yml
```

Он запускается вручную через `workflow_dispatch` на Windows self-hosted runner и вызывает тот же `RUN_ECO_TEST_WORKFLOW.ps1`.

Runner labels:

```text
self-hosted
Windows
X64
```

Для Godot можно определить repository variable:

```text
DWS_GODOT_DOUBLE_BIN
```

Если переменная отсутствует, используется стандартный Windows путь Godot, указанный выше. Workflow fail-closed проверяет exact Godot version перед тестами.

## Правило путей

Новые ECO tests/workflows не должны содержать абсолютный checkout path как runtime dependency. Абсолютный путь допустим только как default bootstrap convenience/user-facing launch path. Все внутренние project paths вычисляются относительно repository root.
