# NET-SMOOTH1 R4.0 — Windows exact diagnostics, NOT R4 durability fix

**Субъект:** ветка `repair/net-smooth1-r4-durable-commit-r0`, дочерняя PR #753. Перед запуском взять текущий опубликованный HEAD (проверить удалённый SHA), tree и точный Godot 4.7.1 double SHA256 `3633c3e609c8ce2f9bae334a9c7e75c7f974de3af0415ab4a8050a625a15a7a5`. Проверяем **R4.0 telemetry only**, не claiming performance repair/VERIFIED.

## 1. Подготовка

```powershell
$ErrorActionPreference='Stop'
$Repo='C:\distributed-world-simulator\distributed-world-simulator'
$Branch='repair/net-smooth1-r4-durable-commit-r0'
$WT='C:\distributed-world-simulator\worktrees\net-smooth1-r4-durable-r0'
$Godot='C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe'
git -C $Repo fetch origin $Branch
if ($LASTEXITCODE -ne 0) { throw 'R4_FETCH_FAILED' }
$Head=(git -C $Repo rev-parse "origin/$Branch").Trim()
if (Test-Path $WT) { throw 'WORKTREE_ALREADY_EXISTS' }
git -C $Repo worktree add --detach $WT $Head
if ($LASTEXITCODE -ne 0) { throw 'WORKTREE_ADD_FAILED' }
Set-Location $WT
git rev-parse HEAD
git rev-parse 'HEAD^{tree}'
& $Godot --version
Get-FileHash -LiteralPath $Godot -Algorithm SHA256
```

Перед изменениями прочитать `AGENTS.md`, `PROJECT_CONTROL.md`, `HARNESS_CONTROL.md`, `docs/GODOT_LOCAL_TESTING_RU.md`, `docs/network/NET_SMOOTH1_R4_DURABLE_COMMIT_DESIGN_RU.md`. Использовать отдельный каталог evidence `artifacts/net-smooth1/r40-*`; чужие процессы/пользовательские игры не завершать.

## 2. Проверка схемы, analyzer и регрессий

```powershell
python -m unittest discover -s tests/tools -p test_net_smooth1_analyzer.py -v
if ($LASTEXITCODE -ne 0) { throw 'R4_ANALYZER_FAILED' }
.\RUN_NET_SMOOTH1.ps1 -Mode focused -GodotConsole $Godot -IncludeProcessTests -OutputDirectory "$WT\artifacts\net-smooth1\r40-focused"
$Exit=$LASTEXITCODE
Get-Content "$WT\artifacts\net-smooth1\r40-focused\focused.json"
if ($Exit -ne 0) { throw 'R4_FOCUSED_FAILED' }
```

Ожидается **20 focused-наборов** R3.1, не 21 (R4.0 добавляет только Python tests). Проверить новое `durable_stage_metrics` в Python analyzer; invalid/negative durable duration → INCONCLUSIVE, `success=false` → FAIL. Проверить, что trace остаётся bounded без утечек operation_id/token/snapshot.

## 3. Фактический durable-workload: отдельный сценарий, не фальсифицировать

Обычный NET-SMOOTH1 GUI `-Scenario local` почти целиком шлёт NX3 PLAYER_INPUT_BATCH и **может не выполнять ни одной durable-команды в измеряемом окне**. `require_durable_stages=True` для такого прогона вернёт INCONCLUSIVE по определению. **Нельзя объявить R4.0 измеренным по одному локальному движению.**

Из существующих project command/automation contracts выбрать минимум один реальный разрешённый action (например, валидный ITEM_COMMAND / CONSTRUCTION_COMMAND с настоящим авторитетным результатом), подтвердить `_durable_commits` и generation++ именно в процессе. Не использовать прямую запись world-state, локальную подмену координат, фальшивый trace или локальный `_persist_checkpoint` без команд. Если в automation нет безопасного action, добавить **отдельный минимальный диагностический сценарий** с явным allowlist и tests в этой же ветке (после реализации — новый exact HEAD, новые gates). Сохранить исходные действия/отказы, rejection не считать committed.

В измеряемой фазе выполнить >=20 авторитетно durable успешных действий, документировать типы, generation deltas, ACK order и trace. При `R4_DURABLE_STAGE_REQUIRED` проверять не пустые `durable_command_stages` и `durable_checkpoint_stages`; если отсутствуют — INCONCLUSIVE. Сравнить stage `player_checksum_ms`, `item_graph_checksum_ms`, `outbox_stage_ms`, `checkpoint_total_ms`, `wait_async_ms`, `quiesce_ms`, `persist_atomic_ms`, server frame/loop `message_ms`/`persistence_ms` по одному монотонному process clock.

Параллельно проверять 2 GUI Earth+Quaternius, движение A/B, reconnect, реальный A→secondary→primary в отдельном seam-gate. Сценарий с ударами по миру и Item Graph — один владелец M6, no optimistic ACK.

## 4. Failure gates и отчёт

Инъекции искусственного server/client stall 250ms по прошлому протоколу; они должны давать FAIL с `injected_stall` в правильном trace. Должны оставаться неизменными M6 replay, R3.1 reconnect 37/37, USER1 57/57, 4 process-gates. GUI performance thresholds: frame p99≤25ms, p99.9≤50ms, max≤100ms, server≥59Hz, no main-thread persistence>50ms; **не менять**. R4.0 инструменты не обязаны улучшать эти цифры.

Project Control: отдельный CI `--candidate` может выдавать `CANDIDATE_MAIN_DRIFT` при старом observed main в main-owned registry; документировать источник и точную canonical SHA, не чинить registry из repair-ветки и не скрывать красный workflow.

Сформировать `docs/network/NET_SMOOTH1_R40_WINDOWS_REPORT_RU.md`, собрать manifests, traces, p50/p95/p99/p99.9/max per-role, server staged timings, checksums и проверить соответствие HEAD/TREE. Сдать фактический verdict (PASS по контрактам возможно, performance FAIL допустим и ожидаем); только после stage-classification начинать R4.1 bounded async commit/ACK с crash-matrix. **No merge, no self-VERIFIED.**
