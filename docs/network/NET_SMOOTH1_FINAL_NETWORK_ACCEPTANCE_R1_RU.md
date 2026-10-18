# NET-SMOOTH1 FINAL NETWORK ACCEPTANCE — R1 (Windows DESKTOP-QNAGSTI)

Дата: 2026-10-18. Godot: `4.7.1.stable.double.custom_build.a13da4feb`
(SHA256 `3633c3e609c8ce2f9bae334a9c7e75c7f974de3af0415ab4a8050a625a15a7a5`).

## Заголовки

- BASE_HEAD (frozen candidate, PR #780): `38121527a0ff8937732f64ec915e3206795a19e7`
- TESTED_HEAD (repair): `8d3acec62a2ab6331b6ef4a5157eae252df94cd5` (harness fix),
  `20e9283c98449f07744a2f7f9aa1bb9446c60af3` (+docs-only WO durable). Tree
  (code-идентичный): `18f9173c0b138332e86534278a21ff5149365c3b`.
- MAIN_HEAD (live fetch 2026-10-18): `0d1173303fb6b84e6aa046423ab7c49600176492`
  (новее, чем `f369858c…` из более раннего контекста).

## Задача A — reconnect continuity (диагностика + harness repair)

Диагноз: `client not continuously connected in measured phase` — артефакт
границ измерения сценария, НЕ сетевой разрыв. Трасса `local-r3`: B покидает
CONNECTED на 145.72 s по команде `network.reconnect` самого сценария, внутри
окна measure_start..measure_end (146.83 s); повторное CONNECTED через ~250 мс,
новая transport-сессия, ownership epoch растёт, движение/аватары/snapshots
продолжаются. Таймаутов, checksum mismatch, потерь ACK нет.

Исправление (только `tools/net_smooth1/run_net_smooth1.py`, fail-closed
анализатор и пороги не тронуты): measure.end до планового reconnect (+ожидание
1.2 s > периода опроса проб 200 мс); для r31 — measure.start только после
функциональных r31-этапов.

Результаты (3 независимых GUI-прогона по 120 s, все флаги R3C/R3C2/R3C3/R3C21):

| Прогон | Reconnect continuity (функциональный) | GUI performance (нормативный) |
|---|---|---|
| local-v3-r1 | PASS | FAIL (frame p99: a 25.1, b 25.3, server 35.9) |
| local-v3-r2 | PASS | FAIL (p99 24.9/24.8/36.2; a,b PASS) |
| local-v3-r3 | PASS | FAIL (p99 27.1/26.7/38.3; p999 54.8) |

- r31-reconnect-roundtrip ×3: функциональный PASS 3/3 — A: primary→secondary
  (epoch 1→2, crossings=1, движение под secondary authority), B reconnect
  в чужом remote без возврата A (epoch B 1→2, A region/epoch не изменились),
  A возврат в primary (roundtrips=1, epoch 3). Continuity в измерительном окне
  PASS 3/3.
- Reconnect B вне окна в local ×3: успех, epoch растёт, avatar/snapshots живы.

Нормативный GUI performance: честный FAIL по p99 (клиент 24.8–27.1 против
порога 25; сервер 35.9–38.3) — воспроизводится и на предыдущей принятой
evidence (`work/net-smooth-r3c3-r2-20261016-153700/.../r3c3-r2-gui`: server
p99 39.07) и на baseline-прогоне до fixed HEAD. Это env-headroom машины
(3 GUI-процесса double-сборки), не регрессия исправления. p99.9/max/frame-gap
в r31/local в норме либо на грани; server tick 59.99–60.01 Гц.

## Задача B — server durable drain stalls (root cause)

Причинная цепочка (код + трассы, `durable_checkpoint_stages`/`server_loop`):

1. Durable-before-ACK для ITEM-команд требует полный checkpoint до ACK;
   `LEGACY_COMMAND_SYNC` выполняет его **синхронно в главном потоке**
   (`m3_dedicated_server_runtime_p2.gd:2480-2611` →
   `authoritative_recovery_coordinator.gd:50` → `repository.save_atomic`).
2. Замеры (4 запуска r3c3-r2-gui): `persist_atomic_ms` p50 ≈ 32,
   единично **171/287/181/172 мс** при `wait_async_ms = 0` — диск доминирует,
   drain writer ни при чём.
3. durable-commands GUI-прогон (24 коммита, replay idempotent):
   `persist_atomic_ms` max **970.8 мс** без инъекций; ITEM capture на главном
   потоке до 245 мс; `message_ms` до 206 мс при JOIN после reconnect.
4. r31: `capture_ms`/`persistence_ms` 32–52 мс каждый кадр в окне
   (перенос ownership между регионами) → единичные `main-thread persistence
   >50ms`.

Вывод: главный поток сервера ожидает дисковый I/O и синхронный capture в
durable-пути; M6/durable-before-ACK не нарушены (0 PERSISTENCE_FATAL, 0
replay/ACK violations во всех прогонах). Неблокирующий вариант и обязательные
тесты (crash/restart, replay ordering, ACK escrow, отмена, старая generation)
— в `docs/control/NET_SMOOTH1_DURABLE_STALL_WORK_ORDER_R1_RU.md`. Внедрение
в этот PR запрещено.

## Задача C — Project Control

`CANDIDATE_MAIN_DRIFT` — не сетевой дефект. Наблюдение источника:
`coordination.observed_main` канонического registry (`3d7672c…`) vs живой
main (`0d1173303…`). На чистом main tip candidate-проверка проходит
(топология); на long-lived ветках — ожидаемый drift базы. Узкая правка поля
невозможна по контракту (проверено: `REGISTRY_GENERATION_ADVANCE_REQUIRED`,
binding `83 != 82`, `MVP_CANONICAL_EPOCH_WORK_ORDER_MISMATCH`); требуется
штатная ротация generation владельцем main. Work Order:
`docs/control/CANDIDATE_MAIN_DRIFT_RESOLUTION_WO_R1_RU.md` (PR #783).
Gate не подавлялся, проверки не отключались.

## Обязательные регрессии

- Focused suite (Windows, exact source): **31/31 PASS** — включает
  recovery contracts, replay/outbox, wire checksum, FIFO/disconnect,
  pending durable gate, reconnect, avatar presentation.
- Source Contracts (tests/tools): **80 тестов OK** локально; в CI
  `source-contracts => success` (run 39087435988).
- 3× r3-slow-item (writer 1800 мс): 24/24 durable коммита, duplicate
  replay idempotent, reconnect B успешен, 0 PERSISTENCE_FATAL; нормативные
  пороги под инъекцией ожидаемо нарушены (tick 56.2 Гц, rejections при
  занятом writer) — fault-injection сценарий.
- Restart/recovery, checksum, FIFO, replay, durable-before-ACK: покрыты
  focused-тестами и durable-commands прогоном.
- Windows/Linux Godot Exact + Source Contracts: workflow
  `NET-SMOOTH1 R4.2 R3C3 R2.1 Client Frame Exact`, run 39087435988 на
  repair-ветке (source-contracts success; windows/linux — self-hosted
  runners, ожидают освобождения; предыдущий эквивалентный run 39084453789
  на BASE_HEAD — все три job success).

## Evidence

- Прогоны и SHA256: `C:\distributed-world-simulator\ns1-final-runs\SHA256SUMS.txt`
  (report/manifest каждого прогона, run_id, HEAD/TREE, godot_version).
- PR: #782 (harness measure window + durable WO docs), #783 (Project Control WO).
- Baseline reproduction: `local-r3` (до fixed HEAD) — та же ошибка continuity,
  подтверждает harness-природу.
