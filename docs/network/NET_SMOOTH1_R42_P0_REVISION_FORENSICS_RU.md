# NET-SMOOTH1 R4.2-P0 — fail-closed диагностика M6 revision divergence

**Тип:** Bounded Work Order / implementation candidate. **База:** R4.1-P1 r31 `a23ee541c2cda7d03bb6f497a844e7ec2348a6b2`, дерево `dfded179a995787b7e41043ba24f3566f41014e8`. PR #756 остаётся Draft/NOT VERIFIED; parent #755 также не принят. **Никаких merge, push в main и self-acceptance.**

## Evidence input и честное разделение

- r31 checksum repair: independent Windows checksum functional PASS, 23 focused suites + analyzer 20/20, GUI `r31-reconnect-roundtrip` 3/3, два Quaternius, 0 compact/full/payload rejects, 24/24 и 28/28 durable-команд. **Не равно** общему VERIFIED или разрешению merge.
- Ожидаемый performance FAIL: синхронный M6 `persist_checkpoint` на главном потоке: в ранних точных GUI-trace p99 message до ~1515 мс и persist_atomic p50 ~846 мс. Отдельно держать пороги client frame p99 ≤25 мс, p99.9 ≤50 мс, no >100 мс gap, server ≥59 Гц, no >50 мс main-thread persistence.
- Не приписывать checksum repair: 5 startup readiness timeouts при конкуренции CI; одиночный frame-layer `PAYLOAD_CHECKSUM_MISMATCH`; M6 `SAME_REVISION_AUTHORITATIVE_MUTATION` с `PERSISTENCE_FATAL` в 1/28 checkpoints под нагрузкой; M6 force-kill observation flake, который прошёл retry 128/0.
- Первопричина `SAME_REVISION_...` **пока не доказана**. M6 `authoritative_checkpoint.gd::validate_progression` сравнивает снимки по `_revision_semantic_hash` только при равной revision; снятие этой проверки, игнорирование checksum/epoch, автоматическое увеличение revision при любой ошибке и relaxed persistence **запрещены**.

## Scope P0 — реализовано, но не принято

1. В `scripts/persistence/authoritative_checkpoint.gd` original `_revision_semantic_hash` и `SAME_REVISION_AUTHORITATIVE_MUTATION` остаются gate. При его срабатывании вычисляется **первый путь семантического несовпадения** только из уже сравниваемой нормализованной проекции. Выход содержит schema path (не payload, не значения, не идентификаторы сессий), с детерминированным обходом, ограничением глубины и количества siblings; checksum-поля сравниваются последними только в диагностике. Возвращаемый error_code и критичность отказа НЕ меняются.
2. Новый falsifier `tests/runtime/test_net_smooth1_r42_revision_fence_diagnostics.gd`: настоящий Service → M6 Adapter → Checkpoint → Repository. Проверяет один и тот же revision/состояние (PASS), честное увеличение revision (PASS), намеренно нарушенный revision при валидной SHA (строгий FAIL с field path), atomic rejection без замены предыдущего checkpoint, правильный retry нового поколения. Искусственное нарушение служит *контролем класса*, но не выдаётся за воспроизведение durable-r2.
3. Тест зарегистрирован в `tools/net_smooth1/run_net_smooth1.py`: **24 focused suites** (20 ordinary + 4 process) вместо прежних 23. Analyzer по-прежнему 20/20.
4. Production M3 ACK gate, M6 writer, on-wire checksum, runtime cadence, Construction, PLAYER movement и replay не изменены. **Нулевое заявление об улучшении p99.**

## Windows exact execution (уникальный worktree; не затрагивать другие процессы)

Прочитать корневые `AGENTS.md`, `PROJECT_CONTROL.md`, `HARNESS_CONTROL.md`, `docs/GODOT_LOCAL_TESTING_RU.md`, а также R4.0/R4.1/F1F2/r31 reports. PowerShell 7:

```powershell
$ErrorActionPreference = 'Stop'
$Repo   = 'C:\distributed-world-simulator\distributed-world-simulator'
$Branch = 'repair/net-smooth1-r42-p0-revision-forensics-r1'
$WT     = 'C:\distributed-world-simulator\worktrees\net-smooth1-r42-p0-revision-r1'
$Godot  = 'C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe'
git -C $Repo fetch origin $Branch
if ($LASTEXITCODE -ne 0) { throw 'FETCH_FAILED' }
$Remote = (git -C $Repo rev-parse "origin/$Branch").Trim()
if (Test-Path $WT) { throw "Existing worktree: $WT; use it only after exact HEAD/status audit" }
git -C $Repo worktree add --detach $WT $Remote
if ($LASTEXITCODE -ne 0) { throw 'WORKTREE_FAILED' }
Set-Location $WT
$Head = (git rev-parse HEAD).Trim()
$Tree = (git rev-parse 'HEAD^{tree}').Trim()
if ($Head -ne $Remote) { throw 'HEAD_NOT_REMOTE_EXACT' }
if ((git status --porcelain | Measure-Object -Line).Lines -ne 0) { throw 'DIRTY_TREE' }
Write-Host "PRODUCT_HEAD=$Head PRODUCT_TREE=$Tree"
& $Godot --version
if ($LASTEXITCODE -ne 0) { throw 'GODOT_VERSION_FAILED' }
Get-FileHash $Godot -Algorithm SHA256
$env:BREAKPOINT_RUNTIME_DISABLED = '1'
New-Item -ItemType Directory -Force 'artifacts\net-smooth1\r42-p0-import' | Out-Null
& $Godot --headless --editor --path $WT --log-file "$WT\artifacts\net-smooth1\r42-p0-import\import.log" --import
if ($LASTEXITCODE -ne 0) { throw 'COLD_IMPORT_FAILED' }
& $Godot --headless --path $WT --script 'res://tests/runtime/test_net_smooth1_r42_revision_fence_diagnostics.gd'
if ($LASTEXITCODE -ne 0) { throw 'R42_REVISION_FALSIFIER_FAILED' }
python -m unittest discover -s tests/tools -p test_net_smooth1_analyzer.py -v
if ($LASTEXITCODE -ne 0) { throw 'ANALYZER_FAILED' }
.\RUN_NET_SMOOTH1.ps1 -Mode focused -GodotConsole $Godot -IncludeProcessTests -OutputDirectory "$WT\artifacts\net-smooth1\r42-p0-focused"
if ($LASTEXITCODE -ne 0) { throw '24_FOCUSED_FAILED' }
```

Ожидание: новый тест exit=0 без `SCRIPT ERROR/Parse Error/ERROR`, 24/24 suites, analyzer 20/20. 1 M6 crash-observation flake: сохранить исходный FAIL-лог, сделать **один** exact повтор с отличением timing flake от детерминированной ошибки. Исходный FAIL не стирать.

Затем на том же HEAD/TREE в **эксклюзивном** окне runner (не повышать threshold readiness для скрытия проблемы) — полный GUI р31 3×120s + 30s warmup, два настоящих клиента Quaternius, authority crossing + B reconnect, 0 checksum rejects. Для потерянных игнорируемых ассетов применять только верифицированный локальный `-AssetSource`, never fallback:

```powershell
foreach ($n in 1..3) {
  .\RUN_NET_SMOOTH1.ps1 -Mode gui -GodotConsole $Godot -Scenario r31-reconnect-roundtrip -DurationSeconds 120 -WarmupSeconds 30 -OutputDirectory "$WT\artifacts\net-smooth1\r42-p0-roundtrip-$n"
  if ($LASTEXITCODE -ne 0) { throw "R31_ROUNDTRIP_$n FAILED" }
}
foreach ($n in 1..10) {
  .\RUN_NET_SMOOTH1.ps1 -Mode gui -GodotConsole $Godot -Scenario durable-commands -DurationSeconds 120 -WarmupSeconds 30 -OutputDirectory "$WT\artifacts\net-smooth1\r42-p0-durable-$n"
  if ($LASTEXITCODE -ne 0) { Write-Warning "PERSISTENCE_OR_OTHER_FAIL_$n — keep ALL raw logs; stop and investigate"; break }
}
```

Для каждого durable-прогона сохранить `manifest.json`, `trace`, M6 checkpoint generation, `persist_atomic_ms` и `wait_async_ms`, `PERSISTENCE_FATAL` cause и `first_changed_path`. Если хоть один `SAME_REVISION_...`: зафиксировать путь и воспроизвести RED на текущем HEAD до исправления **конкретного владельца** revision. Не менять `authoritative_checkpoint.gd` так, чтобы старое состояние принималось.

В полном заключении разделить: r31 wire checksum; R4.1 ACK/FIFO/disconnect; M6 revision; performance; startup scheduling; Protocol Frame V2; Project Control candidate `CANDIDATE_MAIN_DRIFT`; Windows exclusive vs CI contention. Блокирующий RED запрещает VERIFIED, независимо от числа прошлых зелёных прогонов. Желателен отдельный exact fresh Linux Reviewer и Windows Independent Verifier на новом HEAD/TREE.

## P1 после P0: реальное устранение фризов (отдельный high-risk slice)

Включить bounded single-writer async **durable-command** path только при доказанном R4.1 FIFO, M6 recovery и строгой сериализации поколений: `APPLIED_NOT_PUBLISHED -> FROZEN_CHECKPOINT -> COMMIT_PENDING -> DURABLE -> ACK_ELIGIBLE -> DELIVERED`. На main-thread допускается только bounded snapshot capture; hash/JSON/IO — worker, ACK и broadcast только после успешного commit. Пока запись в полёте, конфликтующие мутации отклонять/очередить, а realtime movement разрешать **только** с доказанной консистентной recovery-проекцией. Падение перед/после pending/atomic replace, повторный operation_id, stale session/epoch и Construction должны иметь fail-closed falsifiers. Если checkpoint после оптимизации остаётся тяжёлым — WAL допустим только с доказанным deterministic redo/undo, не в этом P0.

**P0 ACCEPTANCE:** верифицированные точные HEAD/TREE, тест/focused/GUI и диагностическая пригодность; узкий repair при найденном конкретном field path. **R4.2-P1 PERFORMANCE ACCEPTANCE:** честное выполнение 25/50/100 ms и ≥59 Hz, а не понижение порогов. **MERGE:** отдельный human gate после независимого review/verifier и PC0, не на основании implementer PASS.
