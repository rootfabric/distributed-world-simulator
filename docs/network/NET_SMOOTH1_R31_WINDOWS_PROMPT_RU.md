# Exact Windows agent — NET-SMOOTH1 r31 checksum repair

Прочитать `AGENTS.md`, `PROJECT_CONTROL.md`, `HARNESS_CONTROL.md`, `docs/network/NET_SMOOTH1_R31_CHECKSUM_REPAIR_RU.md`, `docs/network/NET_SMOOTH1_R41_P1_F1F2_WINDOWS_RU.md`.

PowerShell 7 (не трогать чужие Godot-процессы):

```powershell
$ErrorActionPreference='Stop'
$Repo='C:\distributed-world-simulator\distributed-world-simulator'
$Branch='repair/net-smooth1-r41-p1-durable-ack-integration-r1'
$WT='C:\distributed-world-simulator\worktrees\net-smooth1-r31-checksum-verify'
$Godot='C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe'
git -C $Repo fetch origin $Branch
if ($LASTEXITCODE -ne 0) {throw 'FETCH_FAILED'}
$Head=(git -C $Repo rev-parse "origin/$Branch").Trim()
if(Test-Path $WT) {throw 'WORKTREE_ALREADY_EXISTS'}
git -C $Repo worktree add --detach $WT $Head
if ($LASTEXITCODE -ne 0) {throw 'WORKTREE_FAILED'}
Set-Location $WT
git rev-parse HEAD
git rev-parse 'HEAD^{tree}'
& $Godot --version
Get-FileHash $Godot -Algorithm SHA256
python -m unittest discover -s tests/tools -p test_net_smooth1_analyzer.py -v
if ($LASTEXITCODE -ne 0) {throw 'ANALYZER_FAILED'}
.\RUN_NET_SMOOTH1.ps1 -Mode focused -GodotConsole $Godot -IncludeProcessTests -OutputDirectory "$WT\artifacts\net-smooth1\r31-checksum-focused"
$Focused=$LASTEXITCODE
Get-Content "$WT\artifacts\net-smooth1\r31-checksum-focused\focused.json"
if($Focused -ne 0) {throw 'FOCUSED_FAILED'}
```

Ожидание: 23 focused suites; новый `test_net_smooth1_r31_compact_wire_checksum` 121/121; analyzer 20/20. Если Quaternius-assets отсутствуют в worktree, передай точный `-AssetSource` из ранее проверенного Windows-стенда. Не использовать fallback avatar.

GUI:

```powershell
foreach($n in 1..3) {
  .\RUN_NET_SMOOTH1.ps1 -Mode gui -GodotConsole $Godot -Scenario r31-reconnect-roundtrip -DurationSeconds 120 -WarmupSeconds 30 -OutputDirectory "$WT\artifacts\net-smooth1\r31-roundtrip-$n"
  Write-Host "roundtrip-$n exit=$LASTEXITCODE"
}
.\RUN_NET_SMOOTH1.ps1 -Mode gui -GodotConsole $Godot -Scenario durable-commands -DurationSeconds 120 -WarmupSeconds 30 -OutputDirectory "$WT\artifacts\net-smooth1\r31-durable"
```

Негативные stall server/client A 250ms отдельно и прежние pre-existing M6 flake / candidate main drift отдельно. Принимать roundtrip только по серверным authority-счётчикам, не по локальной позиции. Точный Windows report с SHA продукта, числом compact/full checksum rejects, 3/3 roundtrips, Quaternius/screenshots, client/server p99, generation/replay и реальным F1/F2 и Construction-negative status. Все пороги прежние; не менять main/parent branch; не merge. Если появились другие нестабильные числа или серверные errors — fail closed и narrow repair в той же ветке с новым exact SHA.
