# NET-SMOOTH1 R4.2 — Windows exact evidence: USER1 seam full snapshot checksum repair

**Work Order:** `NET-SMOOTH1-R42-CHECKSUM-R1` / `NET_SMOOTH1_R42_SEAM_FULL_CHECKSUM_REPAIR_RU.md`.
**Verified HEAD:** `14965cc745b89c07faafefe211b835c3c2955313`, TREE `969fa6bc383197291b881ffece58136db773114e`.
**Machine:** DESKTOP-QNAGSTI, Windows 10 Pro, PowerShell 7.
**Godot:** `4.7.1.stable.double.custom_build.a13da4feb`, SHA256 `3633C3E609C8CE2F9BAE334A9C7E75C7F974DE3AF0415AB4A8050A625A15A7A5` — подтверждён перед запусками.

## RED → GREEN

| Шаг | Worktree | Результат |
| --- | --- | --- |
| Cold import HEAD | `worktrees\net-smooth1-r42-p0-checksum-repair-r1` | exit 0 (`artifacts\net-smooth1\r42-checksum-import\import.log`) |
| Regression на HEAD | `test_net_smooth1_r42_seam_full_snapshot_wire_checksum.gd` | `PASS assertions=18 failures=0` (exit 0) — **GREEN** |
| Regression на base `7ef9b80671d4ae8aa53680a0e72854e2db1a01c3` | `worktrees\net-smooth1-r42-p0-checksum-base` (тест добавлен как untracked probe) | `FAIL assertions=18 failures=2`: `remote full snapshot checksum survives real Protocol Frame V2`, `real B reconnect JOIN_ACK snapshot stays checksum-valid on wire` (exit 1) — **RED подтверждён** |

Base RED падает ровно на двух wire-checksum утверждениях — дефект воспроизведён против старого raw seam-кода, новый тест его ловит.

## Unit / focused

- `python -m unittest discover -s tests/tools -p test_net_smooth1_analyzer.py` — **20/20 OK**.
- `python -m unittest discover -s tests/tools -p test_net_smooth1_full_snapshot_probe.py` — **5/5 OK**.
- `RUN_NET_SMOOTH1.ps1 -Mode focused -IncludeProcessTests` — **25/25 PASS**, включая новую regression, r31 compact/full falsifiers, F1/F2, M6 FIFO/fatal (`artifacts\net-smooth1\r42-checksum-focused\focused.json`).

## GUI exact runs (`DWS_NET_FULL_CHECKSUM_PROBE=1`)

Сценарии: `r31-reconnect-roundtrip` ×3, `durable-commands` ×10, DurationSeconds 120, WarmupSeconds 30. Forensic-отчёты `report_full_snapshot_probe.py` (`full-wire-probe-report.json` в каждом run).

| Run | run_id | Verdict | Forensic | Durable stage failures |
| --- | --- | --- | --- | --- |
| roundtrip-1 | 99330b994a414274 | a=PASS, b=FAIL, server=FAIL | SHA_MATCH_ONLY | 0 |
| roundtrip-2 | a0532a2487614e72 | a=PASS, b=FAIL, server=FAIL | SHA_MATCH_ONLY | 0 |
| roundtrip-3 | bd229e9e24b24676 | a=PASS, b=FAIL, server=FAIL | SHA_MATCH_ONLY | 0 |
| durable-1 | 24d5d1c8d07040d7 | server/a/b FAIL | SHA_MATCH_ONLY | 0 |
| durable-2 | ff9a2a25f2974295 | server/a/b FAIL | SHA_MATCH_ONLY | 0 |
| durable-3 | 330d736525bc4375 | INCONCLUSIVE | INCONCLUSIVE (B probe trace отсутствует) | 0 |
| durable-4 | 5947069feac04816 | server/a/b FAIL | SHA_MATCH_ONLY | 0 |
| durable-5 | 8d4da2f2e4164051 | server/a/b FAIL | SHA_MATCH_ONLY | 0 |
| durable-6 | 4aa429d7d5e444fd | server/a/b FAIL | SHA_MATCH_ONLY | 0 |
| durable-7 | a1a0942b8d6641b3 | server/a/b FAIL | SHA_MATCH_ONLY | 0 |
| durable-8 | 28f6875496214091 | server/a/b FAIL | SHA_MATCH_ONLY | 0 |
| durable-9 | e2059ccb69014adb | server/a/b FAIL | SHA_MATCH_ONLY | 0 |
| durable-10 | 81a7dc602f7e43c8 | server/a/b FAIL | SHA_MATCH_ONLY | 0 |

**Ключевой результат:** 12/13 прогонов `SHA_MATCH_ONLY` (`declared_sha256 == source_sha256 == after_json_sha256` по всем stage-пробам SERVER_JOIN_ACK / SERVER_GAMEPLAY_SNAPSHOT / CLIENT_JOIN_ACK / CLIENT_FULL), 1 прогон INCONCLUSIVE из-за отсутствия B-трассы. `MULTIPLAYER_SNAPSHOT_CHECKSUM_MISMATCH` в логах: **0 вхождений во всех 13 прогонах**. B reconnect full snapshot принимается с валидным checksum в каждом прогоне с B-пробой (9/10 durable, 3/3 roundtrip). Full snapshot у клиента A — без отказов.

## Отдельные FAIL-классы (не предмет этого WO)

Каждый FAIL сохранён как отдельная запись в per-run `report.json` / trace:

- **Server perf (GUI)**: frame p99 > 25 ms порога во всех прогонах — известный synchronous M6 checkpoint класс; вынесен в P1 async durable commit (PR #760). Этот repair не меняет и не улучшает p99.
- **B reconnect gap**: ~3.3 s frame gap на B при reconnect (`client not continuously connected in measured phase`) — ожидаемый класс reconnect-join, требует отдельного измерения согласно WO; не является checksum-отказом.
- **durable-3 INCONCLUSIVE**: B probe trace не завершён; отказ зафиксирован, данные прогона не засчитываются как PASS-доказательство.

## Вывод

RED на base `7ef9b806` и exact GREEN на HEAD `14965cc` воспроизведены на Windows exact. Воспроизводимый класс `MULTIPLAYER_SNAPSHOT_CHECKSUM_MISMATCH` (>=5/10 durable) устранён: 0 checksum-отказов в 13/13 GUI прогонах при валидных SHA-триангуляциях. Исправление узкое: shared `PlayerStateSnapshot.normalize_wire_players` + forensic SHA-пробы; schema / server cadence / M6 ACK / пороги не изменены. Никакой полный PASS продукта не объявляется: server p99, durable performance и Project Control gate остаются отдельными обязательными gates.
