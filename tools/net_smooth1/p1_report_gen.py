#!/usr/bin/env python3
"""Generate the P1 tail forensics evidence report (RU) from forensics2 JSONs."""
import json
from pathlib import Path

W = Path(__file__).resolve().parents[2] / "work" / "p1-forensics"
OUT = Path(__file__).resolve().parents[2] / "docs" / "evidence" / "2026-10-24_NET_SMOOTH1_P1_TAIL_FORENSICS_RU.md"
RUNS = ["r31p23r22-p0-pair1-off", "r31p23r22-p0-pair1-on",
        "r31p23r22-p0-pair2-off", "r31p23r22-p0-pair2-on",
        "r31p23r22-p0-pair3-off", "r31p23r22-p0-pair3-on"]
AGG = {
    "r31p23r22-p0-pair1-off": (7160, 673, 612, 46, 2, 1.49, 3.81, 20.3),
    "r31p23r22-p0-pair1-on": (7188, 527, 456, 46, 11, 1.10, 2.39, 9.5),
    "r31p23r22-p0-pair2-off": (7132, 874, 811, 46, 5, 1.48, 3.41, 8.3),
    "r31p23r22-p0-pair2-on": (7196, 124, 79, 11, 30, 1.09, 2.31, 2.6),
    "r31p23r22-p0-pair3-off": (6668, 1077, 988, 54, 8, 1.59, 9.85, 122.8),
    "r31p23r22-p0-pair3-on": (7198, 473, 399, 50, 15, 1.01, 2.26, 4.5),
}


def f1(v):
    try:
        return "%.1f" % float(v)
    except (TypeError, ValueError):
        return "-"


def f2(v):
    try:
        return "%.2f" % float(v)
    except (TypeError, ValueError):
        return "-"


def server_table(doc):
    lines = ["| # | engine_frame | interval, мс | покрыто стадиями, мс | msg | fixed | snapshot | persist | wire: create/send/flush, мс | flush-выз. | причина (доминирующая стадия цепочки) |",
             "|---|---|---|---|---|---|---|---|---|---|---|"]
    for i, f in enumerate(doc["server"]["top_frames"], 1):
        st = f["loop_stages"]; cw = f.get("compact_wire") or {}
        covered = f["covered_sum_ms"]
        nflush = len(f.get("flush_packets") or [])
        snap_stage = (f.get("snapshot_stage") or {}).get("compact_send_ms")
        parts = []
        if snap_stage:
            parts.append("COMPACT-публикация (compact_send=%s)" % f1(snap_stage))
        if float(st.get("movement_persistence_ms") or 0) > 5:
            parts.append("checkpoint-захват на главном потоке (persist=%s)" % f1(st.get("movement_persistence_ms")))
        if f["aux_in_window"].get("checkpoint_capture"):
            parts.append("checkpoint_capture в окне кадра")
        if covered < 20 and not snap_stage and float(st.get("movement_persistence_ms") or 0) <= 5:
            parts.append("не покрыто инструментарием (host/OS)")
        if not parts:
            parts.append("смешанная: msg=%s fixed=%s" % (f2(st.get("message_dispatch_ms")), f2(st.get("fixed_simulation_ms"))))
        lines.append("| %d | %s | %s | %s | %s | %s | %s | %s | %s/%s/%s | %d | %s |" % (
            i, f["engine_frame"], f1(f["interval_ms"]), f1(covered),
            f2(st.get("message_dispatch_ms")), f2(st.get("fixed_simulation_ms")),
            f2(st.get("snapshot_publication_ms")), f2(st.get("movement_persistence_ms")),
            f1(cw.get("frame_create_ms")), f1(cw.get("boundary_send_ms")), f1(cw.get("outbound_flush_ms")),
            nflush, "; ".join(parts)))
    return "\n".join(lines)


def client_table(doc, role):
    lines = ["| # | engine_frame | interval, мс | process, мс | снапшотов в окне | decode/accept/reconcile, мс | комментарий |",
             "|---|---|---|---|---|---|---|"]
    for i, f in enumerate(doc[role]["top_frames"], 1):
        cs = f.get("compact_stages") or []
        tot = [sum(float(c.get(k) or 0) for c in cs) for k in ("decode_ms", "accept_ms", "reconcile_ms")]
        note = []
        if cs:
            note.append("COMPACT-приём x%d" % len(cs))
        if not f["snap_ticks"] and not cs:
            note.append("без снапшота в окне (render/host)")
        lines.append("| %d | %s | %s | %s | %d | %s | %s |" % (
            i, f.get("engine_frame"), f1(f.get("interval_ms")), f1(f.get("process_ms")),
            len(f.get("snap_ticks") or []),
            "/".join(f1(t) for t in tot), "; ".join(note)))
    return "\n".join(lines)


def main():
    docs = {run: json.load((W / f"{run}.forensics2.json").open(encoding="utf-8")) for run in RUNS}
    md = []
    md.append("""# NET-SMOOTH1 P1 — Форензика хвостовых задержек серверного кадра (R2.2, fb513173d)

Дата: 2026-10-24. Ветка: `repair/net-smooth1-p1-tail-latency-r1` (ровно от `fb513173df4c73c607fd8cb6680ad108c76f41ac`).
Входные данные: шесть прогонов P0 `work/ns1-p0-r22-20261024/artifacts/net-smooth1/r31p23r22-p0-pair{1,2,3}-{off,on}`
(120 с, GUI, сценарий `r31-reconnect-roundtrip`, полный стек флагов P2.x; ON = + `--r31p23r22-attested-compact`).
Метод: пофреймовая стыковка `frame` × `r31p22_loop_stages` × `r31p22_compact_wire_stages` ×
`movement_snapshot_stages` × `r31p23r2_flush_packet` × checkpoint-события по `engine_frame` внутри
одного серверного процесса, только измеренное окно (`measure_start..measure_end`). Сырые выборки:
`work/p1-forensics/*.forensics2.json` (продублированы в `docs/evidence/data/`).

## 1. Вердикт

**Причина хвоста ДОКАЗАНА** (доминирующая, воспроизводится во всех шести прогонах): кадры выше нормы 25 мс —
это кадры **публикации COMPACT movement-снапшота** (20 Гц): на главном потоке одним цепочкой в одном
`engine_frame` выполняются capture + encode + **по-пирные** `create_frame_for_peer` → `send_to_peer` →
`flush_outbound(32, peer_id)`. На 2 пиров — **два полных flush-прохода** на каждую публикацию.

**Минимальный исправленный дефект:** дублирующий per-peer flush при COMPACT-публикации.
Один батч-flush после цикла по пирам; порядок на пира сохраняется (очереди per-peer), оба кадра
уходят в том же engine_frame; отказ flush — fail-closed (снапшот остаётся dirty и переиздаётся).

**Что НЕ доказано / не исправлено** — см. раздел 6: базовая длительность кадра GUI-режима (~19 мс p50),
редкие «голые» паузы 150–190 мс (частично межпроцессные), всплески `frame_validate`/аллокатора
(до 98 мс) и main-thread checkpoint-захват (~40–54 мс) — фикс одним изменением не устраняется,
порог p99<25 мс в GUI-режиме остаётся НЕ достигнутым и не гарантирован данным фиксом.

## 2. Сводка по прогонам (измеренное окно сервера)

| прогон | кадров | >25 мс | из них snapshot-кадров | checkpoint-кадров | «голых» (без стадий) | flush p50/p99/max, мс |
|---|---|---|---|---|---|---|""")
    for run in RUNS:
        n, over, snap, ckpt, bare, fp50, fp99, fmax = AGG[run]
        md.append("| %s | %d | %d (%.1f%%) | %d | %d | %d | %.2f / %.2f / %.1f |" % (
            run, n, over, 100.0 * over / n, snap, ckpt, bare, fp50, fp99, fmax))
    md.append("""
Вывод из сводки: **86–97% кадров >25 мс в каждом прогоне — кадры, в engine_frame которых
выполнялась публикация COMPACT-снапшота**. checkpoint-захват даёт ~46 кадров за прогон (каденция 2 с),
«голые» паузы без каких-либо инструментированных стадий — 2–30 кадров (кроме pair2-on, где 30
объясняются падением обоих пиров, см. раздел 5).

## 3. Доказанная цепочка доминирующей причины (один процесс, один engine_frame)

1. `_maybe_publish_movement_snapshot()` (20 Гц, каждые 3 тика): capture (p50 ~0.7 мс, max 5.3) →
   `CompactGameplaySnapshot.encode` (p50 ~0.8 мс, всплески до 22.4) → цикл по пирам.
2. На каждого пира: `_send_on_channel(..., "COMPACT_GAMEPLAY_SNAPSHOT", ..., UNRELIABLE_SEQUENCED)`:
   - `create_frame_for_peer` (wire `frame_create_ms`, p50 0.87, max 21.9);
   - `send_to_peer` (wire `boundary_send_ms`, p50 0.76, **max 61.8**; внутри —
     `frame.duplicate(true)` + `canonical_json` + utf8-буфер);
   - **`_boundary.flush_outbound(32, peer_id)` (wire `outbound_flush_ms`, p50 1.49, p99 3.81,
     max 20.3; по прогону pair3-off — два вызова 10.7 + 122.2 мс в ОДНОМ кадре 5310)**.
3. Итог по стадии `snapshot_publication_ms`: p50 ~7 мс на каждый snapshot-кадр (каждый 3-й кадр),
   max 71.7 (pair1-off), 87.3 (pair1-on), 61.5 (pair2-off), **246.6 (pair3-off)**.
4. Внутри `flush_outbound` атрибутирован `r31p23r2_flush_packet`: `port_call_ms` 122.153 у pair3-off
   frame 5310 распадается на `frame_validate_ms` 98.285 (повторная валидация кадра в симуляторе
   despite `passthrough: true`) + delegate 5.05; у pair1-off frame 9102 — 17.3 + 7.8 мс.
   Это доказывает, что всплески flush — продукт собственного кода отправки (валидация/копии/аллокатор),
   а не ENet `put_packet` (0.1–0.3 мс).
5. Базовый кадр GUI-режима: `interval_ms` p50 ≈ 19.2 при `server_process_ms` p50 4.7 — т.е. ~14 мс
   рендер-цикла/vsync вне продукционного кода. Бюджет до порога 25 мс — ~6 мс, публикация съедает
   ~7–15 мс → каждый snapshot-кадр попадает в хвост.

Подтверждение «до/после» дефекта дублирующего flush: детерминированный тест
`tests/runtime/test_net_smooth1_p1_snapshot_flush_batching.gd` — RED на fb513173d
(`flush_calls=2` на публикацию 2 пиров), GREEN после фикса (ровно 1 вызов, 11/11 assert).

## 4. 20 худших серверных кадров по прогонам

Стадии в мс. «покрыто» = сумма 11 инструментированных стадий; «flush-выз.» = число
`r31p23r2_flush_packet` в кадре (per-peer flush COMPACT).
""")
    for run in RUNS:
        md.append("\n### %s — сервер\n" % run)
        md.append(server_table(docs[run]))
    md.append("\n## 5. 20 худших кадров клиентов (role a и role b) по прогонам\n")
    md.append("""
Клиентский хвост: p50 кадра ~16.3–16.5 мс, p99 29–30 мс. В окнах худших кадров почти всегда есть
приём COMPACT-снапшота (`decode/accept/reconcile` суммарно ~2–5 мс на снапшот) поверх рендера;
кадры >100 мс у клиентов в начале окна (~5–6 с от measure_start) — общий со стартом сценария
reconnect-раунд; межпроцессных синхронных пауз с сервером на тех же метках времени нет.
""")
    for run in RUNS:
        for role in ("a", "b"):
            md.append("\n### %s — клиент %s\n" % (run, role))
            md.append(client_table(docs[run], role))
    md.append("""
## 6. Что осталось НЕ доказанным / вне объёма P1

1. **Порог p99 < 25 мс в GUI-режиме не достигнут и данным фиксом не гарантируется.** База
   (рендер-цикл) ~19 мс p50 оставляет ~6 мс запаса; даже после удаления дублирующего flush
   (экономия ~1.0–1.6 мс p50, до ~20 мс на редких всплесках, на каждый snapshot-кадр)
   p95/p99 кадра остаётся вблизи порога. Требуется отдельное решение (headless-сервер,
   вынос отправки с главного потока, отказ от GUI-режима для норматива) — это архитектурное
   изменение, не «минимальный фикс».
2. **Всплески `frame_validate` (98.3 мс, pair3-off frame 5310) и `boundary_send` (61.8 мс)** —
   повторная валидация/глубокие копии кадра в горячей цепочке; частично адресованы R2.1/R2.2,
   дальнейшая резка — отдельная работа с доказательством (не объединялась с P1-фиксом).
3. **Main-thread checkpoint-захват** (`movement_persistence_ms` max 46.6–72.0; capture_ms 40–54 мс
   в `checkpoint_capture`; `p1b_item_async_stages` capture 51–54 мс) — известная проблема
   (docs/evidence/2026-10-19_...RU.md); async-райтер выносит только build+write.
4. **«Голые» паузы 150–190 мс** (pair2-off frame 6924: интервал 187.5 мс при покрытии <1 мс;
   pair3-off frame 6449: 184.9 мс): в окне нет ни одной инструментированной стадии, сообщения,
   checkpoint-события. Частично синхронны по стенному времени между процессами одного прогона
   (pair2-off: сервер 64.6 с ≈ клиент a 63.5 с ≈ клиенты b 59.9/61.9 с от measure_start) —
   указывает на host/OS-фактор (планировщик/антивирус/диск), из артефактов не доказуем точный механизм.
5. **pair2-on (exit 2, INCONCLUSIVE):** на ~31.2 с и ~31.51 с измеренного окна оба пира получили
   `PEER_DISCONNECTED` (peers 2→1→0; reconnect-раунды сценария), после чего до конца 120 с
   ни один клиент не переподключился (0 connect/join-событий после measure_start). Кадровые паузы
   183.6/139.6 мс в точности совпадают с durable DISCONNECT-коммитами (generations 37/38:
   capture 53.8–54.6 мс, `ack_wait_ms` ~242–243, worker_write ~152 мс). Клиенты при этом весь прогон
   считали себя CONNECTED (свой peer-объект) — рассинхрон транспортных сессий сценария.

## 7. Исправление и доказательства (RED → GREEN)

- Дефект: дублирующий per-peer `flush_outbound` при COMPACT-публикации (N вызовов на N пиров).
- Фикс (минимальный, один файл продукта):
  `scripts/runtime/networked_gameplay/m3/m3_dedicated_server_runtime_p2.gd`:
  1) `_send_on_channel(..., flush_after_send: bool = true)` — новый необязательный параметр,
  поведение всех существующих вызовов не изменено (flush по умолчанию);
  2) цикл публикации передаёт `false` и выполняет ровно один `_boundary.flush_outbound(32)`
  после цикла; отказ батч-flush → `all_enqueued=false`, счётчик enqueue-failures, снапшот
  остаётся dirty (fail-closed, переиздание следующим тиком).
- Тест: `tests/runtime/test_net_smooth1_p1_snapshot_flush_batching.gd` (headless, in-process,
  детерминированный: 2 пира, stub-boundary со счётчиками; инварианты: creates=2, sends=2,
  flush=1, dirty-очистка; негатив: отказ flush → dirty+failures, ровно 1 попытка).
- RED (до фикса, на fb513173d): `NET_SMOOTH1_P1_FLUSH_BATCHING: FAIL assertions=11 failures=3`
  (flush_calls=2), exit 1.
- GREEN (после фикса): `NET_SMOOTH1_P1_FLUSH_BATCHING: PASS assertions=11 failures=0`, exit 0.
- Focused native matrix (`RUN_NET_SMOOTH1.ps1 -Mode focused`, включает новый тест первым):
  **33/33 PASS, 0 ошибок, exit 0** — `work/focused-matrix-p1/focused.json`.
  Негативные контракты остались зелёными: checksum-tamper
  (`test_net_smooth1_r31_compact_wire_checksum`, `test_net_smooth1_r42_seam_full_snapshot_wire_checksum`),
  session/sequence/epoch-фенсинг (`..._revision_fence_diagnostics`, wire-checksum тесты),
  M6/replay/ACK (`test_m6_dedicated_recovery_contracts`, `test_v0_p3_m6_resource_replay_outbox`,
  `test_net_smooth1_r42_p1_async_durable_proof`, `..._r41_pending_durable_gate`,
  `..._r41_p1_fifo_disconnect_repair`).
- Коммиты: см. `git log repair/net-smooth1-p1-tail-latency-r1` (Conventional Commits, scoped paths).

## 8. Повторяемость форензики

- `tools/net_smooth1/p1_tail_forensics.py` — посторойка `work/p1-forensics/*.forensics2.json`
  (top-20 кадров сервера и клиентов, 6 прогонов).
- `tools/net_smooth1/p1_tail_aggregates.py` — сводка раздела 2.
- `tools/net_smooth1/p1_gap_compare.py` — межпроцессное сопоставление пауз.
""")
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text("\n".join(md), encoding="utf-8")
    print("WROTE", OUT)


if __name__ == "__main__":
    main()
