# ECO Test Workflow

Статус: `ACTIVE`.

Цель: запускать ECO production tests из самого checkout проекта, без зависимости от текущей PowerShell-директории и без привязки test logic к конкретному абсолютному пути checkout.

## Локальный checkout

Текущий рекомендуемый Windows checkout:

```text
C:\distributed-world-simulator\distributed-world-simulator\
```

Этот путь не зашит в тестовые сценарии. `RUN_ECO_TEST_WORKFLOW.ps1` определяет корень репозитория по собственному расположению и через `git rev-parse --show-toplevel`.

Exact Godot по умолчанию:

```text
C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe
```

Required identity:

```text
4.7.1.stable.double.custom_build.a13da4feb
```

## Единый локальный entrypoint

Из корня проекта:

```powershell
$Godot = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"
.\RUN_ECO_TEST_WORKFLOW.ps1 -Suite current -GodotPath $Godot
```

Из любой другой директории, включая `C:\Users\root`:

```powershell
$Godot = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"
& "C:\distributed-world-simulator\distributed-world-simulator\RUN_ECO_TEST_WORKFLOW.ps1" -Suite current -GodotPath $Godot
```

Не требуется предварительный `Set-Location`.

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

Workflow не выполняет `git pull`, `git reset`, branch switch или другие Git mutations. Он тестирует ровно текущий checkout/HEAD и печатает `repo_root`, branch и HEAD перед запуском.

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

Новые ECO tests/workflows не должны содержать абсолютный путь checkout вроде:

```text
C:\distributed-world-simulator\distributed-world-simulator\
```

как runtime dependency. Абсолютный путь допустим только в документации/команде запуска пользователя. Все внутренние пути должны вычисляться относительно repository root.
