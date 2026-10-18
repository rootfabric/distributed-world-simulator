# NET-SMOOTH1 R3C.4 R2 — доказательная сводка (opt-in server worker-envelope periodic capture)

Дата: 2026-10-19 · Исполнитель: implementer session (Lead) · Статус: **EXACT_PASS / PERF_FAIL — не для merge по кадровому критерию**

## Точный предмет

- Родитель: `ced03db64eae3adaab270044574c0f8b96c590c6` (R3C.4 R1 evidence, PASS_WITH_FINDINGS / PERF_FAIL).
- Кандидат: `fc4e7d690a8f2c65102cbe13a8f12f2ac6cc68b5` (tree `d73cd2b3ced6185b1dfddecaafff42c29fbe3347`),
  ветка `feature/net-smooth1-r3c4r2-worker-envelope`. R1-другая-ветка (#786) не затрагивалась; auto-merge
  дивергентных R1-реализаций не выполнялся.
- Godot: `4.7.1.stable.double.custom_build.a13da4feb`, SHA256 консольного double-бинарника
  `3633c3e609c8ce2f9bae334a9c7e75c7f974de3af0415ab4a8050a625a15a7a5` — совпадает с pinned Windows double SHA
  во всех 9 прогонах (`manifest.json.identity.godot_sha256`). Linux double SHA `bfa7ce63…d7d7` в этой сессии
  не воспроизводился (Linux-машины недоступны).
- Изменения: server-only opt-in `DWS_NET_R3C4R2_WORKER_ENVELOPE=1` / `--r3c4r2-worker-envelope`,
  требующий R1 (`--r3c4-periodic-frame-pacing`); R2 без R1 — fail-closed `R3C4R2_REQUIRES_PERIODIC_FRAME_PACING`,
  невалидный режим — `R3C4R2_INVALID_WORKER_ENVELOPE_MODE`. Legacy-путь default OFF.
- Точная семантика R2: на авторитетном кадре вместе отсоединяются ОДИН detached
  `service.export_durable_state()` DTO и ОДИН `_replay_outbox.to_dict()`; нормализация M6-конверта —
  чистая статическая функция `M6AuthorityAdapter.normalize_durable_state()` (общая с legacy-адаптером);
  существующий worker по-прежнему делает deep-copy обоих деревьев ДО wakeup и строит конверт + SHA256 через
  неизменённые `Checkpoint.create` и `repository.save_atomic`. Дорогой DTO-export остаётся на main-потоке;
  multi-frame source export НЕ заявляется.

## Локальная валидация (Windows, до GUI)

- Новый native-фальсификатор `tests/runtime/test_net_smooth1_r3c4r2_worker_envelope.gd`:
  PASS, 69 assertions, чистый выход без ERROR/утечек (wrapped envelope == legacy envelope, словарь и
  финальный disk-checksum; post-submit мутация вызывающего не меняет диск; invalid DTO отклоняется без
  записи; default-off; generation+ACK-parity с сохранением R1 pacing; disk restore неизменённым валидатором).
- Source-контракт `tests/tools/test_net_smooth1_r3c4r2_worker_envelope_source.py`: 7/7 PASS.
- Полный focused exact-матрица `run_net_smooth1.py --mode focused` (31 тест, включая R1/M6/ITEM/reconnect/
  CHAR/Earth-ретеншн и новый R2-фальсификатор): **31/31 PASS**, exit 0
  (`artifacts/net-smooth1/r3c4r2-focused-exact`).

## Реальные Windows GUI прогоны (DESKTOP-QNAGSTI, 120s measure, OpenGL3 900x600, VSync off, max 60fps)

Все прогоны: scenario `r31-reconnect-roundtrip`, полный 120-секундный измеряемый интервал, HEAD+TREE в
каждом `manifest.json`, `tracked_dirty=false`, общие флаги `--r3c-async-admission --r3c2-avatar-prewarm
--r3c2-server-phased --r3c3-staged-earth --r3c21-frame-paced-presentation --r3c4-periodic-frame-pacing`;
ON добавляет `--r3c4r2-worker-envelope` (только серверу). Анализ — normative
`tools/net_smooth1/analyze_net_smooth1.py` без изменений.

| Прогон | Режим | server frame p99 | p99.9 | max | functional | вердикт |
|---|---|---|---|---|---|---|
| gui-off-1 | OFF (R1 on / R2 off) | 39.74 | 49.54 | 76.53 | PASS | FAIL (perf) |
| gui-off-2 | OFF | 43.12 | 55.81 | 63.79 | PASS | FAIL (perf) |
| gui-off-3 | OFF | 39.47 | 50.74 | 61.07 | PASS | FAIL (perf) |
| gui-on-1-retry | ON | 39.81 | 52.69 | 61.15 | PASS | FAIL (perf) |
| gui-on-2 | ON | 41.31 | 49.46 | 62.26 | PASS | FAIL (perf) |
| gui-on-3 | ON | 40.45 | 48.79 | 59.67 | PASS | FAIL (perf) |

Инфраструктурные заметки: первый `gui-on-1` — INCONCLUSIVE (breakpoint_mcp не занял :9080 после
преждевременно завершённого батча), заменён чистым `gui-on-1-retry`; до установки Quaternius-пака один
прогон отклонён Quaternius-gate (`r3c4r2-gui-off-1-missing-assets`), после установки 220+2 texture
(`T_Eye_Normal_png.png`, `T_Hair_1_Normal_png.png` — битые URI в gltf) все кандидаты проходили gate.

### Сравнение стадий захвата/записи (server trace.jsonl, measure-window)

| Метрика | OFF p50 (3 прогона) | ON p50 (3 прогона) |
|---|---|---|
| checkpoint_capture.quiesce_ms | 0.01 | 0.01 |
| checkpoint_capture.authority_ms | 32.8 / 38.3 / 33.9 | 29.5 / 33.9 / 34.8 |
| r3c4r2_durable_dto_ms (только ON) | — | 8.6 / 11.8 / 11.9 |
| checkpoint_complete.build_ms | 9.1 / 10.4 / 9.4 | 7.6 / 9.3 / 9.4 |
| checkpoint_complete.write_ms | 85.3 / 104.6 / 90.2 | 85.3 / 88.0 / 90.0 |
| checkpoint_complete.worker_ms | 94.8 / 116.5 / 99.2 | 90.8 / 97.4 / 99.5 |

Вывод по стадиям: disk-пайплайн worker'а (build+write) OFF и ON совпадает в пределах шума — R2 не меняет
стоимость записи; захват на авторитетном кадре (~33–38ms DTO+нормализация, единый кадр) остаётся
доминирующим вкладом в server frame p99 и по построению R2 его не снижает.

## Функциональные инварианты

- r31 roundtrip/reconnect, replay/ACK loss, checksum, dropped trace, recovery: `functional_scenario=PASS`
  во всех 9 завершённых прогонах; единственные отказы — кадровые пороги и
  `main-thread persistence >50ms` (известная R1-находка, R2 её не устраняет).
- 3× `--scenario r3-slow-item --slow-item-writer-ms 1800` (ON): durable_workload PASS в каждом
  (≥24 durable-коммита, duplicate operation_id — идемпотентный replay, generation ordering,
  durable-before-ACK); кадровые FAIL — ожидаемая нагрузка тестовой инжекции, не регресс семантики
  (`r3c4r2-slowitem-on-1/2/3`).

## Вердикт и следующий шаг

- **PERF_FAIL**: server frame p99 40.4–41.3ms > 25ms во всех ON-прогонах — критерий слияния не выполнен,
  merge НЕ выполняется (согласно Work Order). Экзактность R2 (byte-equal конверт/диск, fail-closed,
  генерации/ACK) доказана локально и в GUI-прогонах (0 checksum/replay/ACK violations, 0 dropped trace).
- Кадровое p99 на авторитетном кадре определяется одно-кадровым DTO-export+нормализацией (~33–38ms).
  Следующая ревизия (true multi-frame source DTO capture) требует иммутабельной/версионированной
  сервисной проекции с mutation fence; читать живое состояние через несколько тиков без fence запрещено.
- Артефакты: `artifacts/net-smooth1/r3c4r2-focused-exact`, `r3c4r2-gui-off-1..3`,
  `r3c4r2-gui-on-1-retry|2|3`, `r3c4r2-slowitem-on-1..3`, `r3c4r2-gui-batch-status*`.
