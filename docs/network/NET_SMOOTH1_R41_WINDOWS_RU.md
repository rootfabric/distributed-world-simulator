# NET-SMOOTH1 R4.1-core — Windows exact proof и следующий product integration

Из PR #755 (номер после публикации проверить в GitHub) взять exact HEAD/TREE, Godot 4.7.1 double SHA256 `3633C3E609C8CE2F9BA334A9C7E75C7F974DE3AF0415AB4A8050A625A15A7A5`. R4.1-core — **не подключённый к server runtime** state machine; настоящий GUI performance всё ещё ожидается FAIL. Цель независимой стадии — проверить контракт escrow, подготовить R4.1-P1 интеграцию и crash fault-matrix, не создавать преждевременный ACK.

```powershell
$ErrorActionPreference='Stop'
$Repo='C:\distributed-world-simulator\distributed-world-simulator'
$Branch='repair/net-smooth1-r41-pending-ack-proof-r1'
$WT='C:\distributed-world-simulator\worktrees\net-smooth1-r41-pending-ack-r1'
$Godot='C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe'
git -C $Repo fetch origin $Branch
if ($LASTEXITCODE -ne 0) { throw 'FETCH_FAILED' }
$Head=(git -C $Repo rev-parse "origin/$Branch").Trim()
if (Test-Path $WT) { throw 'WORKTREE_EXISTS' }
git -C $Repo worktree add --detach $WT $Head
if ($LASTEXITCODE -ne 0) { throw 'WORKTREE_FAILED' }
Set-Location $WT
git rev-parse HEAD
git rev-parse 'HEAD^{tree}'
& $Godot --version
Get-FileHash -LiteralPath $Godot -Algorithm SHA256
python -m unittest discover -s tests/tools -p test_net_smooth1_analyzer.py -v
if ($LASTEXITCODE -ne 0) { throw 'ANALYZER_FAILED' }
.\RUN_NET_SMOOTH1.ps1 -Mode focused -GodotConsole $Godot -IncludeProcessTests -OutputDirectory "$WT\artifacts\net-smooth1\r41-core-focused"
$FocusedExit=$LASTEXITCODE
Get-Content "$WT\artifacts\net-smooth1\r41-core-focused\focused.json"
```

Ожидается 21 focused suite, новый `test_net_smooth1_r41_pending_durable_gate.gd` 63/63 PASS. Project Control `--candidate` выполнять отдельно от обычной `-CheckConsistency`, особенно old observed main drift. В focused случае известного M6 ENet timing flake не снижать пороги, сохранить все логи и replay/durability факты.

Следующая реализация P1: подключить gate ко всем мутирующим handlers только после review и матрицы, запустить настоящий durable workload из R4.0 (`-Scenario durable-commands`), проверить `no ACK before durable`, no uncommitted snapshots/broadcasts, fault points, replay under restart, preserving 60 Hz. Публиковать отдельный candidate exact head; ни на каком этапе не мержить в PR #754/#753/#751/main без human gate.
