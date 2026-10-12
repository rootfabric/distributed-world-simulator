# NET-SMOOTH1 R4.2 — независимая Windows-верификация checksum-ремонта (PR #759)

**Вердикт:** `VERIFIED` (функциональная корректность checksum; производительность — отдельный FAIL-класс P1-B).
**Роль:** независимый Reviewer/Verifier, не Implementer ремонта. Все прогоны выполнены заново в свежих worktree.
**Хост:** DESKTOP-QNAGSTI, Windows 10 Pro, PowerShell 7.6.
**Godot:** `4.7.1.stable.double.custom_build.a13da4feb`, SHA256 `3633C3E609C8CE2F9BAE334A9C7E75C7F974DE3AF0415AB4A8050A625A15A7A5` — проверен перед прогонами.

## Идентификация

| Ref | SHA | TREE |
| --- | --- | --- |
| База (PR #758 evidence) | `7ef9b80671d4ae8aa53680a0e72854e2db1a01c3` | — |
| Implementation HEAD (проверен) | `14965cc745b89c07faafefe211b835c3c2955313` | `969fa6bc383197291b881ffece58136db773114e` |
| Ветка/PR HEAD (implementation + evidence docs) | `1104e989fd308317051c50c276bc9cb760bb51a9` | `17c47d202b4064f9280414f46f5ae16f21cf9b5b` |

`14965cc7` является предком `1104e989` (ancestry подтверждён). Worktree:
`worktrees\net-smooth1-r42-checksum-verify-r1` (HEAD) и
`worktrees\net-smooth1-r42-checksum-base-verify-r1` (base), оба cold-import exit 0 без SCRIPT/Parse/Compile ошибок.

## Независимый RED → GREEN

- **RED на base `7ef9b806`** (новый falsifier добавлен как untracked probe): `FAIL assertions=18 failures=2` — ровно `remote full snapshot checksum survives real Protocol Frame V2` и `real B reconnect JOIN_ACK snapshot stays checksum-valid on wire`. Лог: `artifacts/net-smooth1/r42-checksum-independent-red/red.log`.
- **GREEN на `1104e989`**: `PASS assertions=18 failures=0`. Лог: `artifacts/net-smooth1/r42-checksum-independent-green/green.log`.

## Code review

- `PlayerStateSnapshot.normalize_wire_players()` — единственный shared path: используется и в `create`, и в USER1 seam `create_snapshot()`. Нормализуется только копия сетевых DTO (`players` собран из `.duplicate(true)`), authoritative sim/SM1/ownership/Item Graph не изменяются. Вторая тяжёлая JSON-сериализация на hot-path не добавлена.
- `net_full_snapshot_wire_probe.gd` — opt-in (`DWS_NET_FULL_CHECKSUM_PROBE=1`), пишет только stage/counts/SHA-256 (`declared_sha256`, `source_sha256`, `after_json_sha256`); raw payload, координаты и идентификаторы не записываются.
- Все 4 стадии проб присутствуют: `SERVER_JOIN_ACK_BEFORE_FRAME`, `SERVER_GAMEPLAY_SNAPSHOT_BEFORE_FRAME`, `CLIENT_JOIN_ACK_AFTER_FRAME`, `CLIENT_FULL_SNAPSHOT_REJECTED_AFTER_FRAME`.
- Full/Compact checksum validation, Protocol Frame V2, revision fence, M6 ACK/replay не ослаблены; tamper-тесты в focused suite продолжают отклонять изменённые данные; USER1 primary/secondary authority без изменений.

## Headless

- Analyzer: 20/20 OK. Forensic analyzer: 5/5 OK.
- `RUN_NET_SMOOTH1.ps1 -Mode focused -IncludeProcessTests`: **25/25 PASS**, `complete=true` (`r42-checksum-focused-independent/focused.json`).

## GUI exact (`DWS_NET_FULL_CHECKSUM_PROBE=1`, эксклюзивное окно, Quaternius без fallback)

3× `r31-reconnect-roundtrip`, 10× `durable-commands`, Duration 120 s, Warmup 30 s.

- **Checksum: 0 отказов.** `MULTIPLAYER_SNAPSHOT_CHECKSUM_MISMATCH`: 0 вхождений во всех 91 логах 13 прогонов.
- **Forensics: 13/13 `PROBE_HASHES_MATCH_ONLY`** (`declared == source == after_json` по всем stage-пробам; `mismatch_records=[]`, `unpaired_client_join_count=0`). Отдельный прогон без завершённой трассы отсутствует — все 13 трасс полные, INCONCLUSIVE не объявлен.
- **Functional scenario: PASS 13/13.** B reconnect full snapshot принят с валидным checksum в каждом прогоне; durable stage failures = 0.
- **B reconnect frame gap**: max client-B frame ≈ 3.28–3.30 s в каждом roundtrip — преднамеренный disconnect→reconnect-join класс; активные клиенты зависаний класса «connected hang» не показали сверх серверных stall-ов.
- **Отдельные FAIL-классы (не предмет checksum, приёмка не подменяется):** server perf — synchronous M6 checkpoint (server frame p99 ≈ 495–508 ms, persistence p99 ≈ 212–218 ms) во всех 13 прогонах; у клиентов p99.9/frame-gap>100ms как следствие серверных stall-ов. Это целевой P1-B Work Order; пороги не менялись, улучшение FPS не заявляется.

## Вывод

RED→GREEN воспроизведён независимо; функциональный checksum-дефект закрыт на `14965cc7`/`1104e989` без ослабления валидации. Вердикт VERIFIED ограничен checksum/M6-корректностью: server p99, durable persistence latency и Project Control gate остаются отдельными обязательными gates (P1-B).
