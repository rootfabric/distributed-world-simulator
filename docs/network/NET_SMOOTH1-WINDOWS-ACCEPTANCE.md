# NET-SMOOTH1 R1 — Windows-приёмочный отчёт (GUI_LOCAL_CANDIDATE, FAIL)

Статус: **FAIL / GUI_LOCAL_CANDIDATE**. Это implementer-side evidence, не independent
VERIFIED и не основание для merge. Main и PR #748 не изменялись.

## Идентичность прогона

- Ветка: `repair/net-smooth1-char2-r1`
- Публикация bundle: exact HEAD `eece0b609fa9f673b8d427c7aadb24e060a063ff`,
  tree `07170be1b198138399e4b3cddefd54b9113731c0`, SHA256 bundle
  `e1f1a3c9…586690d` — совпали, non-force push, remote SHA сверён.
- Фикс регрессии HOLD: коммит `29c75cd7f49084a041690bc7ec92efdbebb49e05`
  (см. «Регрессия и фикс» ниже). Все GUI/негативные прогоны выполнены на этом HEAD,
  tree `6e1ccb277bec21cc959e176891aeb915b2e100c2`, `tracked_dirty: false`.
- Godot: `4.7.1.stable.double.custom_build.a13da4feb`,
  SHA256 `3633c3e609c8ce2f9bae334a9c7e75c7f974de3af0415ab4a8050a625a15a7a5`.
- Python 3.11.8, Windows 10 (19045), 20 CPU. Quaternius: real provider,
  asset manifest SHA256 `d0abf665…d2ce427d` (123 файла). Fallback в GUI не обнаружен,
  capsule отсутствует (тесты презентации PASS).

## 1. Тесты контрактов и процессов

- Analyzer self-tests: **11/11 OK** (`python -m unittest …test_net_smooth1_analyzer.py`).
- Focused+process gate, прогон r1 (HEAD `eece0b6`): 15/17 PASS, 2 FAIL
  (см. ниже). Прогон r2 (HEAD `29c75cd`): **16/17 PASS**, остаётся 1 FAIL
  (`test_m6_dedicated_recovery_processes`). Логи: `artifacts/net-smooth1/windows-focused`,
  `…windows-focused-r2`.

### Регрессия и фикс (repair-введённая)

- Симптом: `test_char2_network_avatar_client_presentation` — assertion
  «remote run animation follows network velocity» (28/28→1 fail), детерминированно.
- Бисекция: на базе CHAR2 `f861de654` тест PASS; при откате только
  `scripts/network/interpolation/remote_snapshot_interpolator.gd` к базе на
  repair-ветке — PASS; с repair-версией — FAIL. Причина: bounded HOLD
  (`HOLD_EXTRAPOLATION_LIMIT`) обнулял `details.velocity`, из-за чего
  анимационная семантика remote-аватара выпадала из run/walk при удержании
  на горизонте экстраполяции.
- Фикс `29c75cd`: позиция остаётся зажатой на горизонте (контракт
  `test_net_smooth1_hold_continuity` не нарушен: 72/72), velocity следует
  последней авторитарной выборке. Проверено: HOLD 72/72, presentation 28/28,
  NX5 6104 assertions PASS, NX5 integration 49 PASS.

### Pre-existing FAIL (не регрессия repair)

- `test_m6_dedicated_recovery_processes`: 128 assertions, 1 failure —
  «A observed dedicated crash» (клиент A не зафиксировал инжектированный краш
  первого dedicated-сервера; замена сервера и восстановление геймплея — PASS).
- Воспроизведён identically на базе CHAR2 `f861de654` (см. worktree
  `worktrees/char2-base-check`, лог `%TEMP%\char2base-m6proc.log`).
  Требует отдельного repair вне NET-SMOOTH1.

## 2. Реальные GUI-прогоны (Quaternius, 2 клиента, LIVE2 bridge)

Сценарий: camera toggle, движение A/B/совместно, стрейф, повороты, бег,
stop/start, reconnect B вне performance-окна. Во всех прогонах
`functional_scenario: PASS`, `process_exit_codes {a:0,b:0,server:0}`,
`backwards_holds: 0`, remote_distance ≈ 463–466 м на каждого клиента,
reconcile p50 0.195 мс / max 1.9 мс, correction max ≤1 м, replayed ticks max 21–22.
Пороги: frame p99 ≤25 мс, p99.9 ≤50 мс, max ≤100 мс, server ≥59 Гц. Пороги не менялись.

### Async checkpoint mode (120 c + warmup 30 c)

| Роль | p50 | p95 | p99 | p99.9 | max | Verdict |
|---|---|---|---|---|---|---|
| server frame_ms | — | — | 135.9 | 205.8 | 331.2 | FAIL (loop gaps, persistence>50ms) |
| client A frame_ms | 15.5 | 28.4 | 31.4 | 36.6 | 48.1 | FAIL (p99>25) |
| client B frame_ms | 15.5 | 28.1 | 31.4 | 37.8 | 81.6 | FAIL (p99>25) |

### Sync checkpoint mode (3 повтора, 120 c + warmup 30 c)

| Прогон | server frame p99/p999/max | A p99/max | B p99/max | Доп. FAIL |
|---|---|---|---|---|
| sync-r1 | 287.9 / 395.6 / 476.4 | 31.3 / 40.7 | 31.3 / 37.3 | simulation <59Hz |
| sync-r2 | 281.6 / 350.1 / 375.9 | 30.9 / 36.3 | 31.2 / 143.7 | simulation <59Hz |
| sync-r3 | 283.2 / 368.8 / 638.6 | 31.2 / 207.2 | 30.9 / 135.1 | simulation <59Hz |

Сравнение sync/async: серверный хвост у sync хуже в ~2 раза (p99 281–288 мс против
136 мс) и sync единственный нарушает 59 Гц симуляции — синхронная запись
checkpoint'ов на главном потоке стоит дороже, чем асинхронный writer. Клиентские
p99 практически одинаковы (30.9–31.8) — клиентский хвост определяется не режимом
checkpoint'а, а обработкой movement-снапшотов (см. локализацию).

### Отрицательные контроли (250 мс инжекция)

- `-InjectStallRole server`: вердикт **FAIL (exit 1)** — детектор сработал
  (`server loop gap >100ms`, `main-thread persistence >50ms`); в
  `server/trace.jsonl` есть явное событие `{"kind":"injected_stall","duration_ms":250}`.
- `-InjectStallRole a`: вердикт **FAIL (exit 1)**; событие `injected_stall`
  в `a/trace.jsonl`; `frame gap >100ms` у клиента A. Оба контролируемых запуска
  показали именно FAIL, не INCONCLUSIVE — детектор жив.

## 3. Локализация микрофризов (точная, пороги не тронуты)

**Сервер.** loop'ы с process_ms>20 мс: 2113 за 120 с (каждые ~3 тика). Три механизма:
1. Публикация movement-снапшота каждые 3 тика (`NX3_MOVEMENT_SNAPSHOT_INTERVAL_TICKS=3`,
   `m3_dedicated_server_runtime_p2.gd:46`): `_maybe_publish_movement_snapshot`
   (:772–804) делает `create_snapshot()` + `CompactGameplaySnapshot.encode` +
   глубокие `duplicate(true)` (:778–785 и в `_send_on_channel` :1150) —
   snapshot_ms p50 24–30 мс на регулярной основе.
2. Синхронный command-checkpoint в пути `PLAYER_INPUT_BATCH → _handle_move →
   _persist_command_result` (:1271–1309) → `_persist_checkpoint` (:1312–1334):
   спин `wait_completed()` (`async_checkpoint_writer.gd:75–83`, worker p50 178 мс)
   плюс синхронные canonicalize+SHA-256+JSON+write на главном потоке. Ровно 76
   `checkpoint_complete` = 76 спайков message_ms 108–190 мс; период ~1.6 c
   (интервал 1500 мс) — «два stall'а на поколение».
3. `capture_ms` в трейсе — «липкое» значение последнего capture'а (:342, :1475),
   артефакт логирования, не стоимость каждого тика.

**Клиенты.** Фризы событийные, не GPU: p50 15.5 мс (60 fps), но 99.0–99.2 % кадров
>25 мс наступают в пределах 60 мс после `snapshot_received` (17.8 снапшотов/с —
каждый ~3-й кадр стоит 26–31 мс: client_loop 7–18 мс поверх базы 16.7 мс).
`engine_process_ms` одинаков в обычных и больших кадрах. Единичные хвосты
(81.6 мс у B, 143.7–207.2 мс в sync-прогонах) — лакуны планирования при
конкуренции 3 процессов Godot и воркер-потока writer'а за CPU/disk.

**Вывод о достижимости:** p99 ≤25 мс на этой машине при текущей архитектуре
недостижим без правок кода: ~30 % кадров — снапшотные с ценой 26–31 мс.

**Рекомендации (без изменения порогов):**
1. Убрать полный sync-checkpoint из пути команды: durable-before-ACK через
   journal/outbox, полный checkpoint — редко и асинхронно.
2. Убрать `duplicate(true)` в горячем пути снапшота (:785, :1150) — кодировать
   в bytes один раз и переиспользовать между пирами.
3. Кэшировать/инкрементализировать `_service.create_snapshot()` (вызывается 3×
   на commit: :1292–1293 и публикация).
4. На клиенте разнести применение снапшота на 2 кадра или обрабатывать вне кадра.
5. Пониженный приоритет воркер-потока writer'а; обнулять `capture_ms` после лога.

## 4. Непокрытое (не отмечать PASS)

4-часовой LOCAL-прогон, `seam-stress`, WAN matrix, late join третьего клиента,
crash-in-async-write fault matrix, независимый A/B стоимости инструментализации —
не выполнялись/не автоматизированы. Сообщение docs/network/NET_SMOOTH1_WINDOWS_RU.md
о предварительном 4-часовом прогоне после устранения FAIL: текущий блокер —
клиентский p99 (см. выше) и pre-existing m6 process FAIL.

## 5. Вердикт

- Focused gate: FAIL (1 pre-existing process test, не repair).
- GUI async и все 3 sync прогона: FAIL по frame p99 (клиенты ~31 мс > 25 мс;
  сервер: sync хуже async, async всё равно >100 мс p99).
- Отрицательные контроли: детектор подтверждён (FAIL при инжекции, событие в трейсе).
- **Вердикт: FAIL / GUI_LOCAL_CANDIDATE. Merge не производить.** Требуется
  отдельный repair по рекомендациям раздела 3 и отдельное решение по
  pre-existing `test_m6_dedicated_recovery_processes`.

Артефакты: `artifacts/net-smooth1/windows-focused{,-r2}`, `windows-gui-async`,
`windows-gui-sync-r1..r3`, `windows-negative-server-stall`,
`windows-negative-client-stall` (manifest.json с HEAD/TREE/Godot SHA, traces,
phases, captures, отчёты; скрипт корреляций `windows-gui-async/analyze_clients.py`).
