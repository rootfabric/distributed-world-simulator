# NET-SMOOTH1 R2 — инструкция Windows exact / GUI

Точное требование: запустить **R2 HEAD** из ветки `repair/net-smooth1-char2-r1` (не старый `eece0b6`, `29c75cd` или `a81df80`). Перед каждым прогоном зафиксировать `git rev-parse HEAD`, `git rev-parse HEAD^{tree}`, Godot 4.7.1 double version/hash. Main и CHAR2 не изменять. Не брать GUI package с устаревшей ветки.

## Контроль среды и тесты

```powershell
$ErrorActionPreference = 'Stop'
$WT = 'C:\distributed-world-simulator\worktrees\net-smooth1-char2-r1'
$Godot = 'C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe'
git -C $WT fetch origin repair/net-smooth1-char2-r1
git -C $WT switch repair/net-smooth1-char2-r1
git -C $WT merge --ff-only origin/repair/net-smooth1-char2-r1
if ($LASTEXITCODE -ne 0) { throw 'R2_FAST_FORWARD_FAILED' }
Set-Location $WT
git status --porcelain
git rev-parse HEAD
git rev-parse 'HEAD^{tree}'
& $Godot --version
Get-FileHash $Godot -Algorithm SHA256
python -m unittest discover -s tests/tools -p test_net_smooth1_analyzer.py -v
if ($LASTEXITCODE -ne 0) { throw 'ANALYZER_FAILED' }
.\RUN_NET_SMOOTH1.ps1 -Mode focused -GodotConsole $Godot -IncludeProcessTests -OutputDirectory "$WT\artifacts\net-smooth1\r2-win-focused"
$FocusedExit = $LASTEXITCODE
Get-Content "$WT\artifacts\net-smooth1\r2-win-focused\focused.json"
```

Тестов ожидается 18 (старые 17 + `test_net_smooth1_snapshot_hotpath.gd`). Известный `test_m6_dedicated_recovery_processes` уже падал на родительской CHAR2; фиксировать его отдельно, не считать новым регрессом и не превращать FAIL в PASS.

## Реальная GUI-клиентская приёмка

Использовать ранее установленный exact Quaternius asset-provider (или указать `-AssetSource` если это новый worktree). Для сравнения запустить три асинхронных прогона с уникальными каталогами, чередуя с R1 baseline на точно сохранённом старом SHA / отдельном worktree. Сценарии и пороги не менять.

```powershell
foreach ($n in 1..3) {
    .\RUN_NET_SMOOTH1.ps1 -Mode gui -GodotConsole $Godot -DurationSeconds 120 -WarmupSeconds 30 -OutputDirectory "$WT\artifacts\net-smooth1\r2-win-gui-async-$n"
    Write-Host "GUI-ASYNC-$n EXIT=$LASTEXITCODE"
    Get-Content "$WT\artifacts\net-smooth1\r2-win-gui-async-$n\report.md"
}
```

Обязательно доказать двумя GUI-клиентами, что камера, real Quaternius, remote walk/run/idle, seam, движение в обе стороны, diagonal, stop/start, jump и reconnect не изменились. Обязательны `movement_snapshot_stages` (сервер), `compact_snapshot_stages` (клиенты) и `snapshot_received`. В отчёте разделить `capture_ms / encode_ms / send_and_seam_ms` и `decode_ms / accept_ms / reconcile_ms / presentation_ms`. Если событий нет — INCONCLUSIVE, не PASS.

## Негативные контроли

```powershell
.\RUN_NET_SMOOTH1.ps1 -Mode gui -GodotConsole $Godot -DurationSeconds 64 -WarmupSeconds 30 -InjectStallRole server -InjectStallMs 250 -OutputDirectory "$WT\artifacts\net-smooth1\r2-win-stall-server"
Write-Host "SERVER-NEGATIVE-EXIT=$LASTEXITCODE"
.\RUN_NET_SMOOTH1.ps1 -Mode gui -GodotConsole $Godot -DurationSeconds 64 -WarmupSeconds 30 -InjectStallRole a -InjectStallMs 250 -OutputDirectory "$WT\artifacts\net-smooth1\r2-win-stall-a"
Write-Host "CLIENT-A-NEGATIVE-EXIT=$LASTEXITCODE"
```

Ожидаемый exit 1 + доказательство `injected_stall` в trace конкретной роли. Не объявлять PASS по одному exit 1: обычный p99 сейчас также FAIL.

## Вердикт и следующий repair

Вернуть точный `R2 HEAD/TREE`, 18 focused test results, R1/R2 paired p50/p95/p99/p99.9/max, runtime traces, GPU/renderer, frame stalls распределения, скриншоты и sha256 evidence. Общий verdict может оставаться FAIL, пока (а) клиент p99 >25ms, (б) сервер loop tail >100ms, (в) синхронный durable command checkpoint блокирует процесс. Этот slice **не изменяет durable checkpoint/ACK**; не приписывать ему исправление командных пауз. Не делать merge.
