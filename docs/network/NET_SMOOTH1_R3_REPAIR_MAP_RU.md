# NET-SMOOTH1 R3 — reliable product seam только при изменении, без 20Hz дублирования

## Основание и subject

- Родительский опубликованный HEAD: `669bf5f045cb967f65783dd93f6a6d9138cf094c` (R2 Windows evidence). Источник истины — удалённый Git HEAD, не локальные chat-описания.
- Ветка: `repair/net-smooth1-char2-r1` — последовательно поверх R2; `main` и CHAR2 PR #748 не менять.
- Windows R2 implementer evidence: `docs/network/NET_SMOOTH1_R2_WINDOWS_REPORT_RU.md`, verdict **FAIL / GUI_LOCAL_CANDIDATE**. Серверный `send_and_seam_ms` p50 20.5–22.4 мс, p99 33.9–42.1 мс; server loop p99 121–130 мс; GUI client frame p99 32.4–32.6 мс. Пороги прежние.
- Основная причина подтверждённого `send_and_seam` overhead: на **каждом** 3-м fixed tick сервер отправлял через `RESYNC/RELIABLE_ORDERED` состояние `PRODUCT_SEAM_STATE` каждому клиенту сразу после realtime compact snapshot. Это 13-полевое состояние региональной authority/seam координации **не содержит position/velocity** и во время обычного движения практически не меняется. Дорогая синхронная сериализация/валидация/отправка вызывается 20+ раз в секунду без новой информации.

## Узкий R3 repair

1. Кэш последнего **успешно поставленного в надёжную очередь** `PRODUCT_SEAM_STATE`, ключ peer+transport session+logical player. Сравнивается полный 13-полевой **detached** state, а не только счётчик crossing (нельзя потерять phase/authority/epoch изменения).
2. `PLAYER_JOINED` всегда посылает текущий reliable seam state, даже когда состояние совпадает с кэшем. Новый session identity или logical player также принудительно отправляет состояние.
3. При actual изменении authority/region/transfer/crossings state надёжный пакет посылается немедленно при следующем обычном снапшоте. Нет искусственного debounce, TTL или пропуска перехода через `UNRELIABLE_SEQUENCED`.
4. При ошибке постановки в очередь кэш **не обновляется**; следующий вызов повторяет отправку. При disconnect/leave/stop cache удаляется; меньше утечек идентичности.
5. Сохраняется прежняя 60Hz authority симуляция и каждые три тика (`50 ms`) `COMPACT_GAMEPLAY_SNAPSHOT`. Wire-schema, session sequence, checksum, `RESYNC/RELIABLE_ORDERED`, ACK/команда/persistence/replay не меняются.
6. В `movement_snapshot_stages` добавлены `compact_send_ms`, `seam_check_send_ms`, `seam_sent`, `seam_skipped_unchanged`; поле `send_and_seam_ms` остаётся для exact R2/R3 сравнения. Добавлены серверные counters в `get_report`.
7. Trace analyzer автоматически выдаёт per-stage p50/p95/p99/p99.9/max, delivered/skipped; R3 GUI-манифест **требует** snapshot-stage events и не выдаёт ложный PASS при отсутствии/битых данных.

Не выполнять «отложенную отправку в следующем кадре» без собственного latency/budget анализа: простое перемещение синхронных encode/hash/flush в следующий `_process` переносит микрофриз, а не устраняет его. В R3 устранено повторение ненужного reliable packet, а не нарушена гарантия доставки актуальной seam truth.

## Доказательства/falsifiers

- RED (точный R2 server script + R3 test): `tests/network/test_net_smooth1_seam_change_delivery.gd`, 86 assertions / **10 FAIL** на повторных одинаковых отправках.
- GREEN (R3 server script + тот же test): **86/86 PASS**.
- 20 очередных `MOVEMENT_NETWORK_TICK` A+B → 40 пропусков одинакового seam state, но по одному первоначальному доставленному `PRODUCT_SEAM_STATE` на клиента; два peer не получают чужое состояние.
- Авторитетный crossing до secondary region доставляется в reliable frame с валидными checksum/schema; повторное состояние подавляется; при failure кэш не продвигается; replay JOIN принудительно шлёт; смена session_id снова шлёт.
- Canonical Linux Godot 4.7.1 double cold import **PASS**; focused **15/15 PASS** (без процесса), Python analyzer selftests **16/16 PASS**. Это не Windows GUI, и не full Windows focus gate.

## R3 Windows acceptance / high-risk fences

- Запустить **точный HEAD** и тройной GUI LOCAL async, сравнить R2 p50/p95/p99/p99.9/max у `send_and_seam_ms`, отдельно `compact_send_ms`, `seam_check_send_ms`, `seam_sent/skipped`.
- `seam_skipped_unchanged` должен расти во время обычного движения; `seam_sent` должен покрывать JOIN/reconnect и каждый изменившийся authority state, без ненужного лавинообразного роста. Вариант seam-stress должен доказать фактический переход primary↔secondary и клиентское подтверждение; если переход не произошёл — **INCONCLUSIVE для seam-stress**, а не PASS.
- Повторить GUI avatar (Quaternius), два клиента, движение/remote run/idle/turn/camera, reconnect, bounded HOLD, `snapshot_received`, 250ms negative controls.
- Прогнать 19 focused suites, включая process (известный **pre-existing** `test_m6_dedicated_recovery_processes` красный на исходном CHAR2; отдельно классифицировать, не перекрашивать gate в PASS).
- Текущие бюджеты: client frame p99 ≤25 мс, p99.9 ≤50 мс, no >100ms stalls, сервер ≥59 Hz и no persistence >50ms. Не менять пороги, не объявлять полноценный PASS только за уменьшение `send_and_seam_ms`.
- **Открытые независимые slices:** sync durable command checkpoint (`message_ms` p99~118–120ms и persistence p99~63–66ms) требует crash-safe journal + fault matrix; клиентский frame tail — отдельный profiling render/event/CPU конкуренции. Не менять durable-before-ACK без доказательства безопасности; не делать merge без независимой проверки и решения владельца.

## Дополнительный Linux двухклиентский functional smoke (не Windows)

- Канонический Godot double, 24 с measured + 2 с warmup; настоящий server и два headless Earth-клиента через automation bridge, без графических Quaternius-assets.
- Все процессы завершились с `exit=0`, `manifest.completed=true`, `functional_scenario=PASS`, ошибок runtime/потери trace нет. Server/client trace содержат обязательные stage events (сервер n=481, A n=475, B n=474).
- На сервере `seam_skipped_unchanged=962`, `seam_sent=0` **в измеряемом окне** (JOIN произошёл до `measure.start`, поэтому это ожидаемо). `send_and_seam_ms` p50=6.129, p99=10.655; `compact_send_ms` p50=6.064, p99=10.494; `seam_check_send_ms` p50=0.056, p99=0.166 мс.
- Общий performance verdict всё ещё **FAIL / DIAGNOSTIC_ONLY** (server frame p99=62.465 мс, клиент A=69.004 мс, B=79.457 мс; persistence tail не закрыт). Это Linux CPU/headless, **нельзя сравнивать напрямую** с Windows R2 GPU GUI или объявлять performance PASS.
