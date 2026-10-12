# NET-SMOOTH1 R4.2 — USER1 full snapshot checksum repair после P0 Windows

**Work Order:** `NET-SMOOTH1-R42-CHECKSUM-R1` / bounded product repair. База — **evidence HEAD** `7ef9b80671d4ae8aa53680a0e72854e2db1a01c3` (PR #758). Родительский tested P0 HEAD `88f976412b4c887305bdb94247e37e6881788355` / TREE `935deb587fb41e6da35d7dce79637e2d1c2c8061`. `main` и родительские PR не переписывать, не merge, independent VERIFIED не объявлять.

## Что показали Windows evidence

- P0 M6 revision fence 21/21; analyzer 20/20; 24 focused suites PASS; durable 10 прогона — 0 `SAME_REVISION_AUTHORITATIVE_MUTATION`, 0 `PERSISTENCE_FATAL`.
- Дефект **вложенного полного snapshot**, а не обязательно внешнего Protocol Frame V2: клиент отклоняет `MULTIPLAYER_SNAPSHOT_CHECKSUM_MISMATCH` после декодирования. D2/D7/D9/D10 — B на reconnect-join; D5 — A на другом полном snapshot. >=5/10 под нагрузкой.
- GUI сервер perf FAIL остаётся отдельным: synchronous M6 `persist_atomic_ms` median ~492–617 ms, ни один сетевой checksum repair не может считаться исправлением frame p99. Отдельно измерять B reconnect gap (~3.4 s) и connected-only frame-gap, не подменяя непрерывность игровой сессии «зелёной» метрикой.
- Проба `_wire_number` 400000/400000 сошлась, **это не опровергает** отдельный класс обхода wire-нормализации другим владельцем snapshot. Не утверждать, что это точная причина всех Windows-инцидентов до воспроизводимого реального GUI подтверждения.

## Узко найденный source gap

`USER1ProductSeamGameplayService.create_snapshot()` сначала получает `super.create_snapshot()` (обычный FullSnapshot с r31 normalization). Когда имеется ACTIVE secondary SM1 binding, он заменяет данные игроков сырыми movement-row значениями, удаляет `checksum` и вычисляет SHA непосредственно через `SeamUtils.payload_hash(snapshot)`. Это **обходит** r31 `PlayerStateSnapshot._wire_number()` именно для заменённых remote-rows. Godot JSON parse способен изменить значение между source SHA и клиентским пересчётом.

Канонический Linux Godot 4.7.1 double SHA `bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7`: **изолированный numeric-probe** для `sin(0.1415)/11.0` обнаружил raw source SHA ≠ JSON-parsed SHA; применение того же scalar fixed point дало равные hashes. **Это механизм, не acceptance живого USER1 test и не доказательство инцидента D2/D7/D9/D10.** В частности в изолированной пробе `_wire_number` сходится, а не осциллирует.

## Реализация R1 (проверка независимым Windows агентом обязательна)

1. Ровно один shared `PlayerStateSnapshot.normalize_wire_players(players)` для самого `PlayerStateSnapshot.create` и агрегирующего USER1 seam. Нормализуется только копия сетевых DTO `position/velocity/orientation_yaw`. Authoritative sim/SM1/ownership/item graph/replay не меняются. Schema / SHA / server cadence / M6 ACK unchanged. USER1 не добавляет вторую тяжёлую сериализацию полного snapshot; повторный источник hashes только `SeamUtils.payload_hash` уже стабилизированной DTO.
2. Новая регрессия `tests/runtime/test_net_smooth1_r42_seam_full_snapshot_wire_checksum.gd` на **реальном** USER1 Service. A проходит SM1 primary→secondary, легитимная remote-презентация записывает wire-sensitive yaw без изменения authoritative float, B покидает transport и re-join с новым epoch. Тест передаёт server full snapshot и фактический B JOIN_ACK snapshot через `ProtocolFrameV2.create/encode/decode`, проверяет независимый Full checksum и negative tamper.
3. Runner `tools/net_smooth1/run_net_smooth1.py` включает новый falsifier: **25 suites** (21 ordinary + 4 process), analyzer остаётся 20/20.
4. Метаданные триангуляции при `DWS_NET_FULL_CHECKSUM_PROBE=1`: `SERVER_JOIN_ACK_BEFORE_FRAME`, `SERVER_GAMEPLAY_SNAPSHOT_BEFORE_FRAME`, `CLIENT_JOIN_ACK_AFTER_FRAME`, `CLIENT_FULL_SNAPSHOT_REJECTED_AFTER_FRAME`. Новый `net_full_snapshot_wire_probe.gd` пишет в существующий `SmoothTrace` только `declared_sha256`, `source_sha256`, `after_json_sha256`, валидность Full, stage, revision, tick и количество игроков. **Не пишет байты frame, содержимое инвентаря, игроков/сессии, raw payload или значения координат.** Это opt-in forensic fingerprint, не транспортное изменение; capture из исходных payload потребуется только если fingerprints не локализуют причину, исключительно в защищённый ignored artifact.
5. Если roundtrip ещё FAIL, сохранить точный stage-трейс и отдельным narrow repair исправить конкретного второго владельца. Не разрешать ошибки выключением `Full.validate`, `Frame.validate`, SHA-256, очередей ACK, снижением частоты, устранением клиента или переформулировкой perf threshold.

## Windows exact instructions

PowerShell 7, HOST DESKTOP-QNAGSTI, Godot `4.7.1.stable.double.custom_build.a13da4feb`, Windows SHA256 `3633C3E609C8CE2F9BAE334A9C7E75C7F974DE3AF0415AB4A8050A625A15A7A5`. Перед началом прочитать `AGENTS.md`, `PROJECT_CONTROL.md`, `HARNESS_CONTROL.md`, `docs/GODOT_LOCAL_TESTING_RU.md`, P0 evidence, r31 и этот WO. **Не завершать чужие процессы и не менять main.**

```powershell
$ErrorActionPreference = 'Stop'
$Repo   = 'C:\distributed-world-simulator\distributed-world-simulator'
$Branch = 'repair/net-smooth1-r42-p0-seam-full-checksum-r1'
$WT     = 'C:\distributed-world-simulator\worktrees\net-smooth1-r42-seam-checksum-r1'
$Godot  = 'C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe'
git -C $Repo fetch origin $Branch
if ($LASTEXITCODE -ne 0) { throw 'FETCH_FAILED' }
if (Test-Path $WT) { throw 'WORKTREE_ALREADY_EXISTS' }
git -C $Repo worktree add --detach $WT "origin/$Branch"
if ($LASTEXITCODE -ne 0) { throw 'WORKTREE_CREATE_FAILED' }
Set-Location $WT
$Head = (git rev-parse HEAD).Trim()
$Tree = (git rev-parse 'HEAD^{tree}').Trim()
Write-Host "PRODUCT_HEAD=$Head PRODUCT_TREE=$Tree"
& $Godot --version
if ($LASTEXITCODE -ne 0) { throw 'GODOT_VERSION_FAILED' }
Get-FileHash $Godot -Algorithm SHA256
$env:BREAKPOINT_RUNTIME_DISABLED = '1'
New-Item -ItemType Directory -Force 'artifacts\net-smooth1\r42-checksum-import' | Out-Null
& $Godot --headless --editor --path $WT --log-file "$WT\artifacts\net-smooth1\r42-checksum-import\import.log" --import
if ($LASTEXITCODE -ne 0) { throw 'COLD_IMPORT_FAILED' }
& $Godot --headless --path $WT --script 'res://tests/runtime/test_net_smooth1_r42_seam_full_snapshot_wire_checksum.gd'
if ($LASTEXITCODE -ne 0) { throw 'SEAM_FULL_CHECKSUM_RED' }
python -m unittest discover -s tests/tools -p test_net_smooth1_analyzer.py -v
if ($LASTEXITCODE -ne 0) { throw 'ANALYZER_RED' }
.\RUN_NET_SMOOTH1.ps1 -Mode focused -GodotConsole $Godot -IncludeProcessTests -OutputDirectory "$WT\artifacts\net-smooth1\r42-checksum-focused"
if ($LASTEXITCODE -ne 0) { throw '25_FOCUSED_RED' }
```

Потом **эксклюзивное** GUI-окно без конкурирующих CI heavy runs. Использовать ранее подтверждённый Quaternius `-AssetSource` ровно при первом импорте во fresh worktree, затем без повторного копирования; fallback avatar запрещён. Включить forensic probe и сохранить все по-ролевые трассы:

```powershell
$env:DWS_NET_FULL_CHECKSUM_PROBE = '1'
foreach ($n in 1..3) {
  .\RUN_NET_SMOOTH1.ps1 -Mode gui -GodotConsole $Godot -Scenario r31-reconnect-roundtrip -DurationSeconds 120 -WarmupSeconds 30 -OutputDirectory "$WT\artifacts\net-smooth1\r42-checksum-roundtrip-$n"
  Write-Host "roundtrip-$n exit=$LASTEXITCODE"
}
foreach ($n in 1..10) {
  .\RUN_NET_SMOOTH1.ps1 -Mode gui -GodotConsole $Godot -Scenario durable-commands -DurationSeconds 120 -WarmupSeconds 30 -OutputDirectory "$WT\artifacts\net-smooth1\r42-checksum-durable-$n"
  Write-Host "durable-$n exit=$LASTEXITCODE"
}
Remove-Item Env:DWS_NET_FULL_CHECKSUM_PROBE -ErrorAction SilentlyContinue
```

Каждый `FAIL` или `INCONCLUSIVE` сохранять как отдельную запись, даже если общая функциональность пройдена. Сравнить `declared_sha256`, `source_sha256`, `after_json_sha256` между SERVER/JOIN и CLIENT/JOIN после frame — **сопоставлять по SHA**, а не вычитать wall-clock разных процессов. Сохранять trace `end` и `dropped=0`, original log + evidence SHA. Проверить не только B на reconnect (D2/D7/D9/D10), но A full snapshot (D5), старые r31 compact/full falsifiers, F1/F2, M6 FIFO/fatal.

## Приёмка

- **RED→GREEN**: фиксировать прямую проверку на base `7ef9b806` с новым тестом против старого raw seam-кода, и exact GREEN после narrow repair на новом HEAD. Никакого `--skip-import` до cold import.
- Analyzer 20/20, 25 focused 25/25, real full+compact checksums 0 rejects, B reconnect epoch increases, A authority undisturbed; явное negative tamper rejection.
- Не объявлять улучшения server p99 или durable performance: P1 async checkpoint отдельный Work Order. Server p99/геймплейные пороги остаются прежними.
- Fresh independent Reviewer и Windows Verifier на immutable HEAD/TREE, per-run traces/screenshots/Quaternius, signed artifact SHA, Project Control drift как отдельный product gate.
- `main` не трогать и merge не выполнять; родительские #758/#756 остаются в состоянии NO_MERGE до итоговой композиции.
