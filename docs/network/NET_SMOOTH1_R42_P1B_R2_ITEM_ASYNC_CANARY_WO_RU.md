# NET-SMOOTH1 R4.2-P1-B R2 — production ITEM async canary

**Статус:** `IMPLEMENTED_CANDIDATE / NOT_WINDOWS_VERIFIED / HIGH_RISK / NO_MERGE`. Активация по P1-A VERIFIED, R1 safety — отдельный родитель PR #761. P1-B R1 Windows exact run `38311341864` был QUEUED при начале R2; отсутствие CI результата нельзя считать PASS.

## Exact и границы

- База R1 `b3cd6b6d79e12dbdc25f9b162d1d024b8ea9fbde`, branch `feature/net-smooth1-r42-p1b-r2-item-async-canary-r1`.
- PR #759 independently VERIFIED на implementation `14965cc745b89c07faafefe211b835c3c2955313`, HEAD evidence `6667fe37f789839a53af03085445d1c4a1c44a7b`. Только два production-файла wire-normalization + оригинальный falsifier перенесены в R2 на IDENTICAL BLOB SHA; не выдавать за merge PR #759.
- PR #760 P1-A independently VERIFIED, 97/0 proof, Windows CI PASS. PR #761 R1 safety — fail-closed periodic completion/defensive copy.
- `main` НЕ изменён. Project Control `CANDIDATE_MAIN_DRIFT` должен решаться отдельной main-owned convergence, не изменением registry в NET ветке.

## Реализация ограниченного канареечного production-пути

`scripts/runtime/networked_gameplay/m3/m3_dedicated_server_runtime_p2.gd`: только успешные **новые canonical ITEM_COMMAND** проходят P1-B R2. Canаry **выключена по умолчанию**; opt-in:
- конфиг сервера `async_durable_item_canary: true` или
- серверная переменная `DWS_NET_P1B_ITEM_ASYNC=1`.

Без `playable_sandbox` и `persistence_root`, либо без уже действующего единственного async movement checkpoint writer, setup fail-closed. Обычные server builds продолжают проверенный P1-A/R4.1 sync путь.

1. `reserve_mutation()` вызывается до `_service.handle_canonical_item_command`. Пока periodic writer занят, команда **явно отклоняется** (`P1A_WAIT_PRIOR_PERIODIC`) до изменения мира; существующий клиент должен делать canonical retry с тем же operation_id. В R2 **нет bounded pre-mutation queue**, автоматической переотправки и гарантированной непрерывности при длительном IO. Это блокер продуктового VERIFIED, но не повод выполнить mutation поверх pending generation.
2. Успешный новый canonical ITEM: SHA двух snapshots → `M6ReplayOutbox.stage_committed` → `prepare_product_persistence` → detached authority/replay snapshot → `M6AsyncDurableCommandProof.submit_frozen` → **возврат в обычный серверный loop без fsync/wait**.
3. `M6PendingDurableAckGate` защищает generation/epoch/FIFO. Полезная нагрузка результата и before ITEM graph сохраняются как detached copies. Параллельные durable-мутации отсекаются до применения.
4. `_process` первым вызывает `_p1b_poll_item_async_commit`; не даёт старому periodic poll украсть completion. При успешном exact operation/generation/checkpoint worker ACK становится доступен. Только ПОСЛЕ этого публикуются `COMMAND_RESULT`, ITEM delta / full fallback, `GAMEPLAY_SNAPSHOT` и отложенные `ITEM_GRAPH_RESYNC` (до 32 peer/session request).
5. Во время uncommitted ITEM основной `COMPACT_GAMEPLAY_SNAPSHOT` и `GAMEPLAY_SNAPSHOT` **подавляются**; иначе ITEM/inventory могут быть видимы до atomically committed checkpoint. Fixed simulation/получение input при этом НЕ блокируются. Это **safety-over-smoothness R2**: remote interpolation может дать новый frame gap до completion. Ни один connected p99, p99.9 и smoothness критерий не считается выполненным до последующего committed-view realtime projection без утечки незакоммиченного ITEM. Нельзя снимать barrier ради зелёного p99.
6. Disconnect карантинит ACK owner и gate, old session не получает результат. Failure IO, outbox/replay, generation, staging → `PERSISTENCE_FATAL` без успеха; crash после atomic commit восстанавливает canonical replay.
7. `stop()` может подождать завершения in-flight ITEM **только как explicit shutdown barrier**, после чего старый peer не получает success и durable outbox остаётся для replay. Никаких ожиданий в `_process`.
8. MOVE, PRESENTATION, LEAVE, DISCONNECT, canonical RESOURCE и некоторые другие команды ещё используют старую R4.1 sync durability; persistent CONSTRUCTION по-прежнему fail-closed. **Этот R2 не устраняет все серверные фризы**, хотя новый ITEM-success path переносит IO с main-thread. Claim о perf улучшениях возможен только по настоящим GUI traces.

## Тесты и gates

- Новый настоящий M3 тест `tests/runtime/test_net_smooth1_r42_p1b_item_async_canary.gd`: opt-in без persistence fail; real runtime/service/canonical item graph; async ITEM stage; преждевременный ACK запрещён; другой ITEM до commit не применяется; compact/full/item resync блокируются; disconnect/retained durable replay; repository generation + restart recovery.
- Старые P1-A 97/0, P1-B R1 strict periodic, R4.1 FIFO / pending gate, M6 recovery 126/0, revision fence 21/0, USER1/CHAR2, PR759 full-frame checksum falsifier, analyzer 20/20. В этой R2 ветке **28 focused suites** (24 ordinary + 4 process).
- Отдельный Windows workflow `.github/workflows/net-smooth-r42-p1b-r2-item-async-windows.yml`: canonical self-hosted Windows, Godot 4.7.1 double SHA, cold import, 10 source suites, immutable logs. Если queued/offline, Windows-агент должен сделать independent local detached worktree exact SHA и те же тесты, сохранить evidence. Не выдавать queued за PASS.
- R2 GUI canary: 2 настоящих Quaternius клиента, отдельно 3 ×120s `r31-reconnect-roundtrip` и 10 ×120s `durable-commands` (30s warmup), checksum 0 rejects и успешные canonical ITEM ACK/операции. Включать canary отдельным запуском `$env:DWS_NET_P1B_ITEM_ASYNC='1'`; отключать после завершения. Два workload типа — normal baseline vs canary, одинаковый Windows host и нагрузка. Результат FAIL/INCONCLUSIVE по общей smoothness метрике сохранять как есть; не удалять из отчёта.
- Crash matrix: worker pending + kill before/after atomic rename, stale transport, two concurrent ITEM, periodic busy, replay after restart, forced disk error. Ни один тест не вправе получить success до реального commit. Восстановление допускает только один canonical эффект.
- Метрики: `item_async_capture_ms`, `item_async_worker_ms`, `item_async_ack_wait_ms`, `item_async_snapshot_holds`; stage event `p1b_item_async_stages`. На production не включать debug/trace без измеренной цены.
- Прежние требования: client frame p99 ≤25ms, p99.9 ≤50ms, без connected gap >100ms; server ≥59Hz; main-thread persistence ≤50ms. R2 canary не снимает ни одного.
- Обязателен independent Reviewer→ Windows independent Verifier→ Director→ PC0/directional audit→ human gate merge. Implementer не может присвоить VERIFY себе.

## Запуск на Windows (PowerShell 7, DESKTOP-QNAGSTI)

Строго после чтения `AGENTS.md`, `PROJECT_CONTROL.md`, `HARNESS_CONTROL.md`, `docs/GODOT_LOCAL_TESTING_RU.md`, `docs/MCP_GODOT.md` и source Work Order; не трогать чужие процессы.

```powershell
$ErrorActionPreference = 'Stop'
$Repo = 'C:\distributed-world-simulator\distributed-world-simulator'
$Branch = 'feature/net-smooth1-r42-p1b-r2-item-async-canary-r1'
$WT = 'C:\distributed-world-simulator\worktrees\net-smooth1-r42-p1b-r2-item-canary'
$Godot = 'C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe'
git -C $Repo fetch origin $Branch
if ($LASTEXITCODE -ne 0) { throw 'FETCH_FAILED' }
if (Test-Path $WT) { throw 'WORKTREE_ALREADY_EXISTS' }
git -C $Repo worktree add --detach $WT "origin/$Branch"
if ($LASTEXITCODE -ne 0) { throw 'WORKTREE_FAILED' }
Set-Location $WT
git rev-parse HEAD
git rev-parse 'HEAD^{tree}'
& $Godot --version
Get-FileHash $Godot -Algorithm SHA256
$env:BREAKPOINT_RUNTIME_DISABLED = '1'
& $Godot --headless --editor --path $WT --import --quit
if ($LASTEXITCODE -ne 0) { throw 'IMPORT_FAILED' }
& $Godot --headless --path $WT --script 'res://tests/runtime/test_net_smooth1_r42_p1b_item_async_canary.gd'
if ($LASTEXITCODE -ne 0) { throw 'P1B_ITEM_CANARY_RED' }
& $Godot --headless --path $WT --script 'res://tests/runtime/test_net_smooth1_r42_seam_full_snapshot_wire_checksum.gd'
if ($LASTEXITCODE -ne 0) { throw 'WIRE_CHECKSUM_REGRESSION_RED' }
.\RUN_NET_SMOOTH1.ps1 -Mode focused -GodotConsole $Godot -IncludeProcessTests -OutputDirectory "$WT\artifacts\net-smooth1\r42-p1b-r2-focused"
if ($LASTEXITCODE -ne 0) { throw '28_FOCUSED_RED' }
```

Для standalone GUI перед запуском выставить `$env:DWS_NET_P1B_ITEM_ASYNC = '1'`, затем CLI `RUN_NET_SMOOTH1.ps1 -Mode gui -Scenario durable-commands` с тем же Godot, строго с verified Quaternius AssetSource. После GUI `Remove-Item Env:DWS_NET_P1B_ITEM_ASYNC -ErrorAction SilentlyContinue`. Изолировать runner от concurrent heavy tests.

## Отдельный следующий R3 — устранение stutter, не маскировка

- Durable ITEM канареечный путь должен остаться safe.
- Нужен wire-совместимый *committed-view realtime movement projection*, который на 20Hz обновляет положение игроков во время pending ITEM без выдачи speculative Item Graph/inventory/state revision. Исключить `MULTIPLAYER_SAME_REVISION_MUTATION`, checksum и искусственное превышение network revision.
- После acceptance projection — расширить async на остальные M3 durable command types через отдельные bounded Work Orders и повторить весь GUI/4h soak.
