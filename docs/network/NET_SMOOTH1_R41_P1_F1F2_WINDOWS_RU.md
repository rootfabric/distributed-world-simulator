# NET-SMOOTH1 R4.1-P1 F1/F2 — Windows exact verification

Роль: fresh Windows Implementer/Verifier. Это Draft PR #756; никакого merge/main rewrite и self-VERIFIED. Продуктовый HEAD перед тестами проверять на GitHub, не использовать старые HEAD #755/R4.0. Прочитать AGENTS.md и docs/network/NET_SMOOTH1_R41_P1_F1F2_REPAIR_RU.md.

## 1. Exact worktree

Запустить PowerShell 7:

    $ErrorActionPreference = 'Stop'
    $Repo = 'C:\distributed-world-simulator\distributed-world-simulator'
    $Branch = 'repair/net-smooth1-r41-p1-durable-ack-integration-r1'
    $WT = 'C:\distributed-world-simulator\worktrees\net-smooth1-r41-p1-f1f2'
    $Godot = 'C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe'
    git -C $Repo fetch origin $Branch
    if ($LASTEXITCODE -ne 0) { throw 'FETCH_FAILED' }
    if (Test-Path $WT) { throw 'WORKTREE_ALREADY_EXISTS' }
    $Head = (git -C $Repo rev-parse "origin/$Branch").Trim()
    git -C $Repo worktree add --detach $WT $Head
    if ($LASTEXITCODE -ne 0) { throw 'WORKTREE_FAILED' }
    Set-Location $WT
    git rev-parse HEAD
    git rev-parse 'HEAD^{tree}'
    git status --porcelain
    & $Godot --version
    Get-FileHash $Godot -Algorithm SHA256

Godot должен быть 4.7.1 double, SHA256 = 3633c3e609c8ce2f9bae334a9c7e75c7f974de3af0415ab4a8050a625a15a7a5. Перед скриптовыми тестами нужен cold import; runner выполняет его автоматически. Не трогать чужие Godot-процессы и пользовательские worktrees.

## 2. Regression and falsifier

    python -m unittest discover -s tests/tools -p test_net_smooth1_analyzer.py -v
    if ($LASTEXITCODE -ne 0) { throw 'ANALYZER_FAILED' }
    .\RUN_NET_SMOOTH1.ps1 -Mode focused -GodotConsole $Godot -IncludeProcessTests -OutputDirectory "$WT\artifacts\net-smooth1\r41-f1f2-focused"
    $FocusedExit = $LASTEXITCODE
    Get-Content "$WT\artifacts\net-smooth1\r41-f1f2-focused\focused.json"
    if ($FocusedExit -ne 0) { throw 'FOCUSED_FAILED' }

Ожидается 20 analyzer-tests и 22 Godot focused suites (18 обычных, 4 process). Новый test_net_smooth1_r41_p1_fifo_disconnect_repair.gd проверяет FIFO ACK, failed enqueue/quarantine, M6 replay, busy disconnect, stale session и Construction fail-closed. Ожидается 39/39 asserts: тест дополнительно вызывает реальный server CONSTRUCTION_COMMAND handler через контролируемый fake gateway и доказывает отсутствие mutation на persistence-enabled server и совместимость persistence-disabled. Проверить исходный pending durable kernel 66/66 и M6 force-kill/recovery, M7, NX3, USER1, CHAR2. При timing-flake сохранять исходные логи и фактический FAIL, не снижать критерии.

## 3. Negative contract F1/F2

1. A commit generation 11 success; reliable enqueue A FAIL: mark_delivered запрещён, ACK A quarantined, M6 replay same operation_id не повторяет world mutation.
2. B generation 12: при A как FIFO head выдача B запрещена; после карантина A — B получает ACK после exact durable checkpoint.
3. C peer disconnect во время COMMIT_PENDING: authority LEAVE не должен исполняться; terminal event deferred. После разрешения gate оно выполняется не более 1 раза, stale disconnect никогда не стирает новую session.
4. Persistence-enabled CONSTRUCTION_COMMAND временно возвращает M3_CONSTRUCTION_DURABILITY_CONTRACT_REQUIRED до мутации gateway, так как существующий Construction gateway не даёт M6 durable checkpoint guarantee. Это намеренное продуктовое ограничение, которое требуется явно проверить и отдельно согласовать перед merge. Persistence-disabled M3 construction regressions должны проходить как раньше.

## 4. Two-client product check

    .\RUN_NET_SMOOTH1.ps1 -Mode gui -GodotConsole $Godot -Scenario durable-commands -DurationSeconds 120 -WarmupSeconds 30 -OutputDirectory "$WT\artifacts\net-smooth1\r41-f1f2-gui"
    Write-Host "GUI EXIT=$LASTEXITCODE"
    Get-Content "$WT\artifacts\net-smooth1\r41-f1f2-gui\report.md"

Реальные Earth server + 2 Quaternius, минимум 24 successful ITEM durable commands, exact checkpoint generations, 0 duplicate Item Graph mutation при replay, reconnect B с ownership epoch. Дополнительно r31-reconnect-roundtrip с фактическим A primary→secondary→primary, F1 failed ACK через network fault injection, negative server/client stall 250ms. Если инструменты не умеют инжектировать конкретный reliable enqueue, разработать отдельный scoped injected port с test-first и новым exact HEAD, не подменять success.

Performance thresholds 25/50/100ms и server≥59Hz прежние. P1 всё ещё синхронен: overall performance FAIL ожидаем и **не является** свидетельством регрессии F1. Полный async checkpoint будет только в P2.

## 5. Отчёт

Опубликовать docs/network/NET_SMOOTH1_R41_P1_F1F2_WINDOWS_REPORT_RU.md с exact runtime HEAD/TREE и evidence SHA, raw focused.json, GUI reports/traces, негативными сценариями, прошедшими/не прошедшими критериями и отдельным Project Control --candidate (известный CANDIDATE_MAIN_DRIFT). Не менять тестируемый HEAD после фиксации evidence. Fresh Reviewer/Verifier должен вынести самостоятельное заключение, не просто повторить implementer PASS. Никакого merge.
