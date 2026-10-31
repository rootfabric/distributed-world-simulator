# NET-SMOOTH1 R3C.4 R1 — доказательная сводка (bounded periodic checkpoint frame headroom)

Дата: 2026-10-18 · Исполнитель: implementer session (Lead) · Статус: **PASS_WITH_FINDINGS / PERF_FAIL**

## Точный предмет

- База: `2b0e4848f498d0163ce81785073a9624649d14b8` (PR #785, R31 NARROW_VERIFIED).
- Кандидат: `4fb20a38949f8c5aa3140463f64089e7a816fb50` (tree `eb7cee8550309e44432769b147efe0efbc94bddc`),
  ветка публикации `feature/net-smooth1-r3c4-periodic-frame-headroom-r1-fresh`.
- Godot: `4.7.1.stable.double.custom_build.a13da4feb`, SHA256 `3633c3e6…a7a5` (один и тот же для всех прогонов,
  зафиксирован в каждом `manifest.json`).
- Изменения: только server-only opt-in frame pacing (`DWS_NET_R3C4_PERIODIC_FRAME_PACING=1` /
  `--r3c4-periodic-frame-pacing`), невалидный режим — fail-closed `R3C4_INVALID_PACING_MODE`.
  M6, схема, single-writer pipeline, durable-before-ACK — без изменений (source-контракт +
  ретеншн-сюиты зелёные).

## Локальная валидация (Windows, до GUI)

- Новый native-фальсификатор `tests/runtime/test_net_smooth1_r3c4_periodic_frame_headroom.gd`:
  PASS, 39 assertions (default-off parity, deferred heavy frame, low-work submit, strict completion
  generation, forced bounded capture, disk restore, shutdown, invalid mode rejection).
- Source/fault-mutant контракт `tests/tools/test_net_smooth1_r3c4_periodic_frame_headroom_source.py`:
  7/7 PASS; полный `tests/tools`: 116 passed.
- Ретеншн: async_checkpoint (38), r3c2 phased (45), slow_item_movement (312), p1b periodic (28),
  queued_join (22), async_leave (28), committed_view (35), p1b item canary (47), r41 gate (66),
  M6 recovery contracts (126) — все PASS, без SCRIPT ERROR.

## Реальные Windows GUI прогоны (120s measure window, OpenGL3 900x600, VSync off, 2 GUI-клиента)

Все прогоны — полный 120-секундный измеряемый интервал после `r31` функционального roundtrip;
HEAD+TREE каждой стороны зафиксированы в `manifest.json`, `tracked_dirty=false`.

| Прогон | Режим | server frame p99 | p99.9 | max | вердикт analyzer |
|---|---|---|---|---|---|
| baseline-1 | OFF | 41.25 | 57.15 | 61.42 | FAIL |
| baseline-2 | OFF | 41.16 | 55.03 | 95.49 | FAIL |
| baseline-3 | OFF | 39.80 | 55.33 | 65.70 | FAIL |
| enabled-3 | ON | 38.02 | 44.90 | 47.80 | FAIL |
| enabled-4 | ON | 38.50 | 44.13 | 46.12 | FAIL |
| enabled-5 | ON | 39.57 | 45.91 | 52.63 | FAIL |

Прочие прогоны: `enabled-1`, `enabled-2` — INCONCLUSIVE по инфраструктуре
(в fresh-worktree отсутствовал локальный (untracked) Quaternius-пак → FALLBACK-аватар;
после копирования ассетов и реимпорта все последующие кандидаты проходили Quaternius-gate).

### Функциональные инварианты

- r31 roundtrip, reconnect, replay/ACK loss, dropped trace, checksum, recovery: PASS во всех
  9 завершённых прогонах (`functional_scenario=PASS`); единственные отказы — пороги кадров.
- 3× `--scenario r3-slow-item --slow-item-writer-ms 1800` (флаг ON): durable_workload PASS в каждом
  (24 durable-коммита, дубликат operation_id — идемпотентный replay, B-reconnect epoch advance);
  кадровые пороги FAIL — ожидаемая нагрузка от инжекции writer-задержки, не регресс семантики.

## Поведение pacing'а (server trace, measure-window)

- Кандидат: ~86–89 событий `r3c4_periodic_frame_deferred` за прогон, каждый dispatch получил
  `r3c4_periodic_capture_slot`; **forced-захватов не потребовалось**, наблюдаемая задержка dispatch
  ≤ 1 кадра (≈0–16ms), т.е. существенно лучше границы 64ms.
- Число/порядок durable-поколений: baseline 96 / кандидат 95 за окно (строго монотонные generation,
  пропусков и дублей нет; разница — один хвостовой интервал каденции 1500ms).
- Baseline: 0 deferral-событий (мод по умолчанию не тронут).

## Находка (PERF_FAIL)

Frame separation дала устойчивое улучшение хвоста (p999 55–57 → 44–46ms, max 95 → ~48ms),
но **server frame p99 остался 38–39.6ms против порога 25ms**. Значит стек кадра тяжёлый не только
в момент совпадения snapshot+checkpoint: p99 формируется иными постоянными стадиями
(snapshot encode/broadcast ~8ms p99, MESSAGE, postcommit stage). По критериям WO:

- Вердикт R1: **PASS_WITH_FINDINGS / PERF_FAIL** — кандидата не сливать как «принятую производительность»;
  поведение по умолчанию не изменено.
- Продолжение: отдельный **R3C.4 R2** — разнести по кадрам дорогой immutable
  `export_recovery_state()`/checksum capture (аналог R3C2 frozen view для периодического M6-захвата),
  не ослабляя длительность окна, каденцию 20Hz/1500ms, M6 и прочие инварианты.
  Отдельный synchronous command drain (970ms) — вне этого WO, независимый M6 Work Order.

## Дубликат ветки (для ревью)

Удалённая ветка `feature/net-smooth1-r3c4-periodic-frame-headroom-r1` (`0a2e3132f`, коммиты
`dc6d965e6`+`0a2e3132f` от той же базы `2b0e4848f`) уже существовала — параллельная реализация того же
R1. Force-push запрещён политикой; своя реализация опубликована как
`feature/net-smooth1-r3c4-periodic-frame-headroom-r1-fresh` (`4fb20a389`). Выбор канонической R1 —
решение независимого ревью на основании данной сводки и Remote-версии.

## Артефакты

- Прогоны: `C:\dws-r3c4-r1-{baseline-1..3, enabled-3..5, slowitem-1..3}` (`report.json`, `manifest.json`,
  `server/trace.jsonl`, `durable-commands.json`, `r31-roundtrip.json`).
- Анализ: `artifacts/net-smooth1/r3c4_trace_summary.py`, `artifacts/net-smooth1/r3c4_report_summary.py`.
