# Локальный запуск и тестирование Godot — Windows и Ubuntu

Этот документ — каноническая пользовательская инструкция для локального запуска
Distributed World Simulator на Windows и Ubuntu. Он дополняет `docs/MCP_GODOT.md`:

- этот файл описывает ручной локальный запуск человеком и команды, которые агент
  должен выдавать пользователю;
- `docs/MCP_GODOT.md` описывает управляемый MCP-запуск автономным агентом.

## 1. Правило для агента

Перед тем как давать команды запуска Godot, агент обязан:

1. Определить ОС пользователя: Windows или Ubuntu/Linux.
2. Уточнить или вывести из контекста нужную ветку/worktree и не переключать
   основной checkout без необходимости.
3. Проверить фактические launch/test entrypoints в выбранной ветке; не переносить
   команды со старой ветки вслепую.
4. Использовать double-precision Godot 4.7.1 custom build `a13da4feb`, пока
   проектный контракт не будет явно изменён.
5. Для свежего checkout/worktree сначала выполнить `--import`.
6. Хранить логи и временные результаты только в `artifacts/`.
7. Не предлагать `sudo` для запуска Godot.
8. Не выполнять `set -euo pipefail` прямо в интерактивном Ubuntu shell. Если
   строгий режим нужен, весь блок должен быть заключён в `( ... )`, чтобы ошибка
   не закрыла окно терминала пользователя.
9. Не считать `$HOME/distributed-world-simulator` на Ubuntu или
   `C:\distributed-world-simulator` на Windows самим Git checkout: это workspace.
10. Для точного воспроизведения checkpoint сначала проверить/fetch exact SHA; для
    обычной разработки использовать актуальный HEAD требуемой ветки.

## 2. Каноническая локальная структура

### Ubuntu

```text
/home/<user>/distributed-world-simulator/
├── distributed-world-simulator/      # основной Git checkout
└── worktrees/                         # linked worktrees
    ├── eco-evolutionary-ecology/
    └── ...
```

Переменные:

```bash
workspace="$HOME/distributed-world-simulator"
main_repo="$workspace/distributed-world-simulator"
worktrees_dir="$workspace/worktrees"
```

### Windows

```text
C:\distributed-world-simulator\
├── distributed-world-simulator\      # основной Git checkout
└── worktrees\                         # linked worktrees
    ├── eco-evolutionary-ecology\
    └── ...
```

Переменные PowerShell:

```powershell
$Workspace = "C:\distributed-world-simulator"
$MainRepo = Join-Path $Workspace "distributed-world-simulator"
$WorktreesDir = Join-Path $Workspace "worktrees"
```

Worktree должен находиться рядом с основным checkout, а не внутри его working
 tree. Это не загрязняет `git status` основного checkout.

## 3. Godot binary

### Ubuntu

Канонический путь установленной double-сборки:

```bash
godot_bin="$HOME/.local/opt/godot-double-4.7.1-a13da4f/godot.linuxbsd.editor.double.x86_64"
```

Ожидаемая версия:

```text
4.7.1.stable.double.custom_build.a13da4feb
```

Проверенный SHA-256 Linux binary:

```text
bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7
```

Проверка:

```bash
"$godot_bin" --version
sha256sum "$godot_bin"
```

Если binary ещё не установлен, архив обычно имеет имя, содержащее
`godot-4.7.1-linux-double-x86_64-a13da4f`, но браузер может добавить префикс или
изменить скобки. Поэтому искать его следует по подстроке:

```bash
download_dir="$(xdg-user-dir DOWNLOAD 2>/dev/null || true)"
[ -n "$download_dir" ] && [ -d "$download_dir" ] || download_dir="$HOME/Downloads"

godot_archive="$(find "$download_dir" -maxdepth 1 -type f \
    -iname '*godot-4.7.1-linux-double-x86_64-a13da4f*.gz' \
    -print -quit)"
```

Проверенный архив имеет структуру `tools/godot/linux-x86_64/...`, поэтому
установка выполняется с `--strip-components=3`:

```bash
godot_dir="$HOME/.local/opt/godot-double-4.7.1-a13da4f"
mkdir -p "$godot_dir"
tar --no-same-owner -xzf "$godot_archive" -C "$godot_dir" --strip-components=3
chmod +x "$godot_dir/godot.linuxbsd.editor.double.x86_64"
```

### Windows

Канонический console binary для тестов и MCP:

```powershell
$GodotBin = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"
```

Для ручного графического запуска допустим GUI executable той же double-сборки:

```powershell
$GodotGui = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.exe"
```

Проверка:

```powershell
& $GodotBin --version
```

Ожидаемая версия также должна содержать:

```text
4.7.1.stable.double.custom_build.a13da4feb
```

Не подменять её обычной single-precision сборкой Godot.

## 4. Проверка основного checkout

### Ubuntu

```bash
(
main_repo="$HOME/distributed-world-simulator/distributed-world-simulator"

echo "Git root:"
git -C "$main_repo" rev-parse --show-toplevel

echo "HEAD:"
git -C "$main_repo" rev-parse HEAD

echo "Status:"
git -C "$main_repo" status --short

test -f "$main_repo/project.godot" || { echo "project.godot not found"; exit 1; }
test -f "$main_repo/main.tscn" || { echo "main.tscn not found"; exit 1; }
)
```

### Windows

```powershell
$MainRepo = "C:\distributed-world-simulator\distributed-world-simulator"

git -C $MainRepo rev-parse --show-toplevel
git -C $MainRepo rev-parse HEAD
git -C $MainRepo status --short

if (-not (Test-Path (Join-Path $MainRepo "project.godot"))) {
    throw "project.godot not found: $MainRepo"
}
if (-not (Test-Path (Join-Path $MainRepo "main.tscn"))) {
    throw "main.tscn not found: $MainRepo"
}
```

## 5. Создание отдельного worktree для ветки

Основной checkout не нужно переключать для каждого направления разработки.

### Ubuntu

Пример для `feature/eco-evolutionary-ecology`:

```bash
(
set -Eeuo pipefail

workspace="$HOME/distributed-world-simulator"
main_repo="$workspace/distributed-world-simulator"
target_dir="$workspace/worktrees/eco-evolutionary-ecology"
branch="feature/eco-evolutionary-ecology"

mkdir -p "$workspace/worktrees"
git -C "$main_repo" fetch origin "$branch"

if [ ! -e "$target_dir" ]; then
    if git -C "$main_repo" show-ref --verify --quiet "refs/heads/$branch"; then
        git -C "$main_repo" worktree add "$target_dir" "$branch"
    else
        git -C "$main_repo" worktree add --track -b "$branch" "$target_dir" "origin/$branch"
    fi
fi

git -C "$target_dir" fetch origin "$branch"
git -C "$target_dir" merge --ff-only "origin/$branch"

git -C "$target_dir" branch --show-current
git -C "$target_dir" rev-parse HEAD
git -C "$target_dir" status --short
)
```

### Windows

```powershell
$Workspace = "C:\distributed-world-simulator"
$MainRepo = Join-Path $Workspace "distributed-world-simulator"
$TargetDir = Join-Path $Workspace "worktrees\eco-evolutionary-ecology"
$Branch = "feature/eco-evolutionary-ecology"

New-Item -ItemType Directory -Force -Path (Join-Path $Workspace "worktrees") | Out-Null
git -C $MainRepo fetch origin $Branch

if (-not (Test-Path $TargetDir)) {
    git -C $MainRepo show-ref --verify --quiet "refs/heads/$Branch"
    if ($LASTEXITCODE -eq 0) {
        git -C $MainRepo worktree add $TargetDir $Branch
    }
    else {
        git -C $MainRepo worktree add --track -b $Branch $TargetDir "origin/$Branch"
    }
}

git -C $TargetDir fetch origin $Branch
git -C $TargetDir merge --ff-only "origin/$Branch"

git -C $TargetDir branch --show-current
git -C $TargetDir rev-parse HEAD
git -C $TargetDir status --short
```

Перед `merge --ff-only` агент должен убедиться, что worktree не содержит
непредусмотренных локальных изменений.

## 6. Обязательный import свежего checkout/worktree

Godot создаёт `.godot/uid_cache.bin` и импортированные ресурсы. Свежий worktree
нельзя считать готовым к focused test до первого import.

### Ubuntu

```bash
(
godot_bin="$HOME/.local/opt/godot-double-4.7.1-a13da4f/godot.linuxbsd.editor.double.x86_64"
project_dir="$HOME/distributed-world-simulator/worktrees/eco-evolutionary-ecology"
log_dir="$project_dir/artifacts/runtime/local-import"

mkdir -p "$log_dir"

BREAKPOINT_RUNTIME_DISABLED=1 "$godot_bin" \
    --headless \
    --editor \
    --path "$project_dir" \
    --log-file "$log_dir/import.log" \
    --import

result=$?
echo "Godot import exit code: $result"
[ "$result" -eq 0 ] && echo "IMPORT: OK" || tail -n 200 "$log_dir/import.log"
)
```

### Windows

```powershell
$GodotBin = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"
$ProjectDir = "C:\distributed-world-simulator\worktrees\eco-evolutionary-ecology"
$LogDir = Join-Path $ProjectDir "artifacts\runtime\local-import"

New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
$previous = $env:BREAKPOINT_RUNTIME_DISABLED
try {
    $env:BREAKPOINT_RUNTIME_DISABLED = "1"
    & $GodotBin --headless --editor --path $ProjectDir --log-file (Join-Path $LogDir "import.log") --import
    if ($LASTEXITCODE -ne 0) {
        Get-Content (Join-Path $LogDir "import.log") -Tail 200
        throw "Godot import failed with exit code $LASTEXITCODE"
    }
}
finally {
    if ($null -eq $previous) { Remove-Item Env:\BREAKPOINT_RUNTIME_DISABLED -ErrorAction SilentlyContinue }
    else { $env:BREAKPOINT_RUNTIME_DISABLED = $previous }
}

Write-Host "IMPORT: OK"
```

## 7. Запуск конкретной сцены

Перед выдачей команды агент обязан проверить, что `.tscn` существует именно в
текущей ветке.

### Ubuntu

```bash
godot_bin="$HOME/.local/opt/godot-double-4.7.1-a13da4f/godot.linuxbsd.editor.double.x86_64"
project_dir="$HOME/distributed-world-simulator/worktrees/eco-evolutionary-ecology"

BREAKPOINT_RUNTIME_DISABLED=1 "$godot_bin" \
    --path "$project_dir" \
    res://scenes/labs/ecology/eco_ph5_s4_multiscale_lod_lab.tscn
```

### Windows

```powershell
$GodotGui = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.exe"
$ProjectDir = "C:\distributed-world-simulator\worktrees\eco-evolutionary-ecology"
$previous = $env:BREAKPOINT_RUNTIME_DISABLED
try {
    $env:BREAKPOINT_RUNTIME_DISABLED = "1"
    & $GodotGui --path $ProjectDir res://scenes/labs/ecology/eco_ph5_s4_multiscale_lod_lab.tscn
}
finally {
    if ($null -eq $previous) { Remove-Item Env:\BREAKPOINT_RUNTIME_DISABLED -ErrorAction SilentlyContinue }
    else { $env:BREAKPOINT_RUNTIME_DISABLED = $previous }
}
```

Для PH5-S4:

```text
Q / E              контрастные условия среды PH2
A / D, Left/Right  FULL / REDUCED / CANOPY / IMPOSTOR / POPULATION_ONLY
```

## 8. Focused headless test

Если в ветке есть `.ps1` runner, Windows-пользователю следует выдавать его как
первичный supported entrypoint. На Ubuntu агент должен прочитать runner и
воспроизвести его Godot invocation нативной bash-командой, сохранив preflight,
environment variables и test script.

Пример ECO.P1A-S1.

### Ubuntu

```bash
(
godot_bin="$HOME/.local/opt/godot-double-4.7.1-a13da4f/godot.linuxbsd.editor.double.x86_64"
project_dir="$HOME/distributed-world-simulator/worktrees/eco-evolutionary-ecology"

BREAKPOINT_RUNTIME_DISABLED=1 "$godot_bin" \
    --headless \
    --path "$project_dir" \
    --script res://tests/research/ecology/eco_p1a_s1_environment_acceptance.gd

result=$?
echo "Exit code: $result"
[ "$result" -eq 0 ] && echo "ECO.P1A-S1: PASS" || echo "ECO.P1A-S1: FAILED"
)
```

### Windows

Из корня соответствующего worktree:

```powershell
$env:GODOT_BIN = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"
.\RUN_ECO_P1A_S1_TESTS.ps1
```

## 9. Запуск main scene

Когда нужно запустить не отдельную lab scene, а `run/main_scene` проекта:

### Ubuntu

```bash
godot_bin="$HOME/.local/opt/godot-double-4.7.1-a13da4f/godot.linuxbsd.editor.double.x86_64"
project_dir="$HOME/distributed-world-simulator/distributed-world-simulator"

BREAKPOINT_RUNTIME_DISABLED=1 "$godot_bin" --path "$project_dir"
```

### Windows

```powershell
$GodotGui = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.exe"
$ProjectDir = "C:\distributed-world-simulator\distributed-world-simulator"
$env:BREAKPOINT_RUNTIME_DISABLED = "1"
& $GodotGui --path $ProjectDir
```

Если пользователь просит конкретный network MVP, acceptance phase или иной
режим, агент должен прочитать `scripts/runtime/launch_options.gd` и актуальный
runner выбранной ветки, а затем добавить только реально поддерживаемые аргументы.
Не использовать команды из старого PR как вечный контракт.

## 10. Диагностика типичных проблем

### `fatal: not a git repository`

Проверить, что `project_dir` указывает на checkout/worktree, а не на workspace.

Правильно на Ubuntu:

```text
$HOME/distributed-world-simulator/distributed-world-simulator
$HOME/distributed-world-simulator/worktrees/<name>
```

Неправильно:

```text
$HOME/distributed-world-simulator
```

### `Can't run project: no main scene defined`

Обычно Godot запущен с `--path` на неправильную папку. Проверить:

```bash
test -f "$project_dir/project.godot"
grep -F 'run/main_scene=' "$project_dir/project.godot"
```

### `Godot binary not found`

Ubuntu:

```bash
ls -lh "$HOME/.local/opt/godot-double-4.7.1-a13da4f/godot.linuxbsd.editor.double.x86_64"
```

Windows:

```powershell
Test-Path "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"
```

### Fresh worktree сообщает UID/autoload/resource errors

Сначала выполнить `--import`. Не лечить такой сбой заменой addon или ручным
редактированием UID-файлов до проверки import cache.

### Ubuntu terminal закрывается во время диагностики

Не выполнять строгий `set -euo pipefail` в основном интерактивном shell.
Заключить диагностический блок в `( ... )` или использовать `set +e`.

### Графическое окно не появляется на Ubuntu

Проверить:

```bash
echo "DISPLAY=${DISPLAY:-<empty>}"
echo "WAYLAND_DISPLAY=${WAYLAND_DISPLAY:-<empty>}"
echo "XDG_SESSION_TYPE=${XDG_SESSION_TYPE:-<empty>}"
```

Godot запускать обычным desktop-пользователем, не через `sudo`.

## 11. Что агент должен сообщать пользователю

Хорошая инструкция запуска всегда содержит:

- выбранную ветку и, если важна воспроизводимость, exact HEAD;
- полный локальный путь worktree;
- проверку версии Godot;
- import/preflight для свежего worktree;
- одну копируемую команду запуска;
- управление для конкретной lab/game scene, если оно известно из ветки;
- путь к логам;
- ожидаемый PASS/READY marker;
- безопасную диагностику при сбое.

Агент не должен смешивать Windows path syntax и Bash, использовать устаревший
checkout path из другой машины или предполагать, что имя скачанного архива
сохранилось браузером без изменений.
