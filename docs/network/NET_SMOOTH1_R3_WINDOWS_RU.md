# NET-SMOOTH1 R3 — Windows exact-head испытания (агент)

Это implementer-side validation, **не независимый VERIFIED**. Не менять main/CHAR2, не делать merge и не снижать frame/persistence пороги. Прочитать `AGENTS.md`, `PROJECT_CONTROL.md`, `HARNESS_CONTROL.md`, `docs/GODOT_LOCAL_TESTING_RU.md`, `docs/MCP_GODOT.md`, план R3 и результаты R2.

## 1. Получение только exact remote R3

```powershell
$ErrorActionPreference = 'Stop'
$WT = 'C:\distributed-world-simulator\worktrees\net-smooth1-char2-r1'
$Godot = 'C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe'
$Branch = 'repair/net-smooth1-char2-r1'
git -C $WT status --porcelain
git -C $WT fetch origin $Branch
if ($LASTEXITCODE -ne 0) { throw 'R3_FETCH_FAILED' }
git -C $WT switch $Branch
if ($LASTEXITCODE -ne 0) { throw 'R3_SWITCH_FAILED' }
git -C $WT merge --ff-only "origin/$Branch"
if ($LASTEXITCODE -ne 0) { throw 'R3_FAST_FORWARD_FAILED' }
Set-Location $WT
$HEAD = (git rev-parse HEAD).Trim()
$TREE = (git rev-parse 'HEAD^{tree}').Trim()
Write-Host "PRODUCT_HEAD=$HEAD PRODUCT_TREE=$TREE"
# Сверить значения с exact R3 identity, опубликованной директором.
& $Godot --version
Get-FileHash -LiteralPath $Godot -Algorithm SHA256
```

Если чужие отслеживаемые изменения есть в worktree — не перезаписывать их, а выполнить тест в отдельной exact рабочей копии. Не повторно использовать старые `OutputDirectory`.

## 2. Regression/contract gates

```powershell
python -m unittest discover -s tests/tools -p test_net_smooth1_analyzer.py -v
if ($LASTEXITCODE -ne 0) { throw 'ANALYZER_FAILED' }
.\RUN_NET_SMOOTH1.ps1 -Mode focused -GodotConsole $Godot -IncludeProcessTests -OutputDirectory "$WT\artifacts\net-smooth1\r3-win-focused"
$FocusedExit = $LASTEXITCODE
Get-Content "$WT\artifacts\net-smooth1\r3-win-focused\focused.json"
```

Ожидается **19 focused suites** = 15 обычных + 4 process. Новый test `test_net_smooth1_seam_change_delivery.gd` должен пройти **86/86**. Pre-existing `test_m6_dedicated_recovery_processes` уже падал на исходном CHAR2; повторить классификацию, но общий gate не объявлять зелёным при FAIL.

## 3. Windows GUI A/B, 2 реальных Earth-клиента + Quaternius

Проверить что Quaternius-assets доступны в этом worktree (`assets/external/quaternius`). Иначе использовать утверждённый точный источник только один раз через `-AssetSource`. Каждый прогон измеряет 120 с после warmup 30 с.

```powershell
foreach ($n in 1..3) {
    .\RUN_NET_SMOOTH1.ps1 -Mode gui -GodotConsole $Godot `
        -DurationSeconds 120 -WarmupSeconds 30 `
        -OutputDirectory "$WT\artifacts\net-smooth1\r3-gui-async-$n"
    Write-Host "R3 GUI-$n EXIT=$LASTEXITCODE"
    $p = Get-Content "$WT\artifacts\net-smooth1\r3-gui-async-$n\report.json" -Raw | ConvertFrom-Json
    $s = $p.processes | Where-Object role -eq 'server'
    Write-Host "R3 SNAP SEND+SEAM P99 $($s.snapshot_stage_metrics.send_and_seam_ms.p99)"
    Write-Host "R3 COMPACT SEND P99 $($s.snapshot_stage_metrics.compact_send_ms.p99)"
    Write-Host "R3 SEAM CHECK+SEND P99 $($s.snapshot_stage_metrics.seam_check_send_ms.p99)"
    Write-Host "R3 SEAM SENT/SKIPPED $($s.seam_messages_sent) / $($s.seam_unchanged_skipped)"
}
```

**Не объявлять PASS по снижению серверного `send_and_seam`:** сохранить 25/50/100ms и 59Hz бюджеты; оценить клиентский p99 (~32.5ms на R2) и persistence (R2 p99~63–66ms). Для общего GUI verdict значения из `report.json` остаются решающими.

## 4. Seam-stress и отрицательные контроли

```powershell
.\RUN_NET_SMOOTH1.ps1 -Mode gui -GodotConsole $Godot `
    -Scenario seam-stress -DurationSeconds 180 -WarmupSeconds 30 `
    -OutputDirectory "$WT\artifacts\net-smooth1\r3-seam-stress"
Write-Host "SEAM-STRESS EXIT=$LASTEXITCODE"
.\RUN_NET_SMOOTH1.ps1 -Mode gui -GodotConsole $Godot `
    -InjectStallRole server -InjectStallMs 250 -DurationSeconds 64 -WarmupSeconds 30 `
    -OutputDirectory "$WT\artifacts\net-smooth1\r3-negative-server"
Write-Host "SERVER NEGATIVE EXIT=$LASTEXITCODE"
.\RUN_NET_SMOOTH1.ps1 -Mode gui -GodotConsole $Godot `
    -InjectStallRole a -InjectStallMs 250 -DurationSeconds 64 -WarmupSeconds 30 `
    -OutputDirectory "$WT\artifacts\net-smooth1\r3-negative-client-a"
Write-Host "CLIENT NEGATIVE EXIT=$LASTEXITCODE"
```

Для seam-stress проверить **фактический** crossing/secondary-entry/roundtrip по авторитетным состояниям и соответствующий `PRODUCT_SEAM_STATE` у клиента; no-crossing = INCONCLUSIVE по seam-stress. Оценить надёжный ordered delivery при reconnect, ложный `USER1_PRODUCT_SEAM_STATE_STALE`, потерю remote avatar, повторный JOIN.

Негативный контроль обязан иметь exit 1 И event `injected_stall` в trace ровно той роли, куда вводили stall; сам по себе exit 1 не доказывает детектор, так как базовый R3 может остаться FAIL.

## 5. Отчёт и переход

Опубликовать `docs/network/NET_SMOOTH1_R3_WINDOWS_REPORT_RU.md` с проверенным HEAD/TREE/Godot SHA, explicit functional/performance verdict, 19-suite gate, A/B R2→R3, server stage measurements, client frames, seam sent/skipped, stage coverage, rejoin/crossing, negative controls, evidence SHA и replay/persistence caveats.

Если серверный `compact_send_ms` остаётся дорогим, отделить `Frame.create/validate`, очередь и flush в следующем performance slice. Если серверные `message_ms`/`persistence_ms` остаются красными, следующий HIGH-risk repair — ordered durable journal с crash-matrix; никаких premature ACK. Если клиентский frame p99 >25, отдельная стадийная CPU/render диагностика; не маскировать пороги. Затем independent reviewer/verifier; **никакого merge без пользовательского решения**.
