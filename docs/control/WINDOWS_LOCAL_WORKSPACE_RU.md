# Windows local workspace contract

Status: **ACTIVE**

Scope: локальная Windows-разработка, Git worktree, clean-checkout verification, Godot runtime и MCP для Distributed World Simulator.

Этот документ задаёт единую файловую схему для Windows. Если старый README, отчёт, checkpoint или пример команды содержит прежний путь проекта, для текущей работы применяется этот контракт.

## 1. Каноническая раскладка

```text
C:\distributed-world-simulator\
├── distributed-world-simulator\     # центральный checkout
├── <task-worktree>\                  # рабочие worktree
├── <verification-worktree>\          # clean/exact-head проверки
└── ...

C:\Godot\
└── godot\bin\                        # только Godot tooling
    ├── godot.windows.editor.double.x86_64.console.exe
    └── godot.windows.editor.double.x86_64.exe
```

Точные значения:

```text
WorkspaceRoot   = C:\distributed-world-simulator\
CentralCheckout = C:\distributed-world-simulator\distributed-world-simulator\
GodotBin        = C:\Godot\godot\bin\
GodotConsole    = C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe
GodotGui        = C:\Godot\godot\bin\godot.windows.editor.double.x86_64.exe
```

## 2. Обязательные правила

1. `C:\distributed-world-simulator\distributed-world-simulator\` — центральный checkout для fetch/control/coordination.
2. Новые task worktree и verification worktree создаются рядом с центральным checkout, непосредственно под `C:\distributed-world-simulator\`.
3. Не создавать worktree внутри центрального checkout.
4. Не создавать clone/worktree проекта под `C:\Godot\`. `C:\Godot\` зарезервирован для движка и инструментов.
5. Clean/exact-head проверка не должна переключать центральный checkout на проверяемый SHA. Для неё создаётся отдельный detached worktree.
6. Reusable `.ps1`/`.bat` launchers должны определять project root из собственного расположения, чтобы одинаково работать из central checkout и любого worktree.
7. Фиксированный путь к утверждённому Godot double executable допустим. Фиксированный путь к repository checkout внутри reusable launcher запрещён.
8. Перед runtime acceptance фиксируются exact SHA и чистота worktree; после preflight/runtime `git status --short` снова должен быть чистым, кроме специально разрешённых ignored artifacts.
9. Старые пути `C:\Godot\lunar-world-double-godot`, `C:\Godot\v0-*` и другие repository paths под `C:\Godot\` считаются устаревшими и не должны копироваться в новые Work Orders или test instructions.

## 3. Стандарт создания verification worktree

Пример. Вместо `<EXACT_SHA>` и имени каталога подставляется конкретный кандидат текущей проверки.

```powershell
$WorkspaceRoot = "C:\distributed-world-simulator"
$Central = Join-Path $WorkspaceRoot "distributed-world-simulator"
$Verify = Join-Path $WorkspaceRoot "verify-exact-head"
$ExactSha = "<EXACT_SHA>"

if (-not (Test-Path -LiteralPath $Central)) {
    throw "Central checkout not found: $Central"
}
if (Test-Path -LiteralPath $Verify) {
    throw "Verification worktree already exists: $Verify"
}

git -C $Central fetch origin --prune
if ($LASTEXITCODE -ne 0) { throw "git fetch failed" }

git -C $Central worktree prune
if ($LASTEXITCODE -ne 0) { throw "git worktree prune failed" }

git -C $Central worktree add --detach $Verify $ExactSha
if ($LASTEXITCODE -ne 0) { throw "git worktree add failed" }

Set-Location $Verify

git rev-parse HEAD
git status --short
```

Требования:

- `git rev-parse HEAD` ровно равен назначенному exact SHA;
- исходный `git status --short` пуст;
- центральный checkout не был переключён на candidate SHA.

## 4. Стандарт Godot paths

В PowerShell-проверках рекомендуется объявлять пути явно:

```powershell
$GodotConsole = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"
$GodotGui = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.exe"

if (-not (Test-Path -LiteralPath $GodotConsole)) {
    throw "Godot console executable not found: $GodotConsole"
}
if (-not (Test-Path -LiteralPath $GodotGui)) {
    throw "Godot GUI executable not found: $GodotGui"
}
```

Для headless/test/import используется `GodotConsole`. Для графического клиента используется `GodotGui`.

## 5. MCP на Windows

Для MCP центральный checkout по умолчанию:

```toml
[mcp_servers.godot]
command = "npx"
args = ["-y", "breakpoint-mcp"]
env = { GODOT_PROJECT = "C:\\distributed-world-simulator\\distributed-world-simulator", GODOT_BIN = "C:\\Godot\\godot\\bin\\godot.windows.editor.double.x86_64.console.exe", BREAKPOINT_TOOLSETS = "cli,runtime,processes", BREAKPOINT_PRIVILEGED_GROUPS = "code-execution" }
```

Doctor для central checkout:

```powershell
npx -y breakpoint-mcp doctor --project "C:\distributed-world-simulator\distributed-world-simulator" --require-live --json
```

Если runtime evidence должен собираться на конкретном task/verification worktree, `GODOT_PROJECT` переключается ровно на этот worktree, например:

```text
C:\distributed-world-simulator\v0-p1-verify
```

При этом worktree обязан оставаться внутри `WorkspaceRoot`, а `GODOT_BIN` не меняется.

## 6. Стандарт запуска V0 Windows runtime

Из корня активного candidate/verification worktree:

```powershell
.\RUN_V0_P1_TESTS.ps1 -GodotExe $GodotConsole

.\RUN_V0_MVP_AUTO.ps1 `
    -Clients 2 `
    -Restart `
    -GodotExe $GodotConsole `
    -GodotGuiExe $GodotGui
```

Сам launcher обязан использовать текущий worktree как project root. Нельзя подменять его центральным checkout только потому, что central path известен.

## 7. Завершение verification worktree

Сначала остановить управляемые runtime-процессы из проверяемого worktree:

```powershell
.\RUN_V0_MVP.ps1 -Stop
```

Затем перейти обратно в central checkout и удалить verification worktree через Git:

```powershell
Set-Location "C:\distributed-world-simulator\distributed-world-simulator"

git worktree remove "C:\distributed-world-simulator\verify-exact-head"
git worktree prune
```

Не удалять зарегистрированный worktree вручную через Explorer до `git worktree remove`, если Git ещё считает его активным.

## 8. Правило для новых инструкций агентов

Любая новая Windows-инструкция, Work Order или acceptance procedure должна:

- использовать `C:\distributed-world-simulator\` как workspace root;
- считать `C:\distributed-world-simulator\distributed-world-simulator\` central checkout;
- создавать task/verification worktree только под workspace root;
- использовать утверждённые double Godot executables из `C:\Godot\godot\bin\`;
- не возвращать устаревшие repository paths под `C:\Godot\`;
- предпочитать exact-head detached worktree для независимой локальной проверки.