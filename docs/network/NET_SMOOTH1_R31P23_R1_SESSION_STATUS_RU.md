# Отчёт: статус работы по NET-SMOOTH1 P2.3 R1 (PR #825)

Дата: 2026-10-23. Проверка выполнена по двум независимым каналам: локальная файловая система `C:\distributed-world-simulator` и GitHub (API repo rootfabric/distributed-world-simulator). Обновление от 2026-10-23 (позднее): сырые Windows evidence найдены и верифицированы в `C:\warehouseconstructionbackend\dws-artifacts\` — см. раздел «Локальные evidence»; исходное утверждение об их отсутствии опровергнуто.

## Контекст

В сессии другого проекта была выполнена работа по текущему проекту distributed-world-simulator: реализация и Windows-верификация «NET-SMOOTH1 P2.3 R1 — Deferred Checkpoint Debug» (PR #825). Заявленный итог той сессии: `P2.3 R1 VERIFIED / NATIVE_GUI_DONE / PERF_FAIL / READY_FOR_MERGE=false`, артефакты «локально: EVIDENCE_P23R1_WINDOWS.md, OFF-run, ON-run, FIFO-receipt, сравнение».

## Итог проверки: что реально сделано ✅

Работа действительно выполнена и опубликована на GitHub — все заявленные результаты подтверждены в PR #825.

| Пункт | Подтверждение |
|---|---|
| PR #825 создан (draft, 18 коммитов, 10 файлов, +1156/−4) | ✅ Open, draft, не слит; base = ветка PR #823 |
| Все ожидаемые файлы в PR (gd-тест, 3 python-теста, WO-док, workflow, server runtime, analyzer, runner, validator) | ✅ Подтверждено через pulls/825/files |
| Этап A — Native Exact + Source | ✅ PASS: cold import OK; `test_net_smooth1_r31p23r1_deferred_checkpoint_debug.gd` 32/32; все Python-тесты PASS; focused suite 32/32 |
| Этап B — парные 60 c GUI OFF/ON (HEAD 9d6f00fe) | ✅ Выполнены: функционально PASS, перф — FAIL в обеих руках |
| Этап C — FIFO-аудит | ✅ PASS: 50 в очереди / 50 напечатано, 0 потерь, 0 переполнений; `P23R1_DEBUG_AUDIT_PASS_NOT_PERF_PASS` |
| Этап D — решение | ✅ PERF_FAIL сохранён; 3×120 c не назначались (нет перспектив PASS); опубликовано предложение P2.3 R2 (outbound_flush) |
| Публикация результатов | ✅ Комментарий в PR #825 от rootfabric, 2026-10-23T05:35:33Z, со всеми числами |

Ключевые числа из опубликованного отчёта (server):
- p99: OFF 27,285 мс / ON 28,372 мс (цель ≤25 мс — не достигнута); p99.9 ON 65,779 мс.
- Механизм R1 работает: `debug_event_ms` p50 2,931 → 0,024 мс; отложенная печать p50/max 2,76/11,64 мс.
- Доминирующий остаток хвоста — `outbound_flush`: до 46,8 мс в кадре, суммарно ~5,4–5,5 с за 60-с прогон.
- `PAYLOAD_CHECKSUM_MISMATCH`: 0 вхождений в обеих руках → в issue #815 ничего нового.

## Что НЕ сделано / не подтверждено ❌

1. ~~Локальные артефакты отсутствуют~~ **ОПРОВЕРГНУТО — см. раздел «Локальные evidence» ниже.** Сырые артефакты найдены 2026-10-23 в `C:\warehouseconstructionbackend\dws-artifacts\` (другая рабочая директория, не `C:\distributed-world-simulator`, в границах которой вёлся исходный поиск). Идентичность подтверждена: manifest обеих рук записи содержит `head = 9d6f00feb4c846d9e9a299efbb0f2b9a84477000` (= PRODUCT_HEAD PR #825); числа в `report.json`/`summary.json` совпадают с опубликованным комментарием PR #825; `debug_fifo_receipt.json` содержит SHA256 трейса и runtime-лога, совпадающие с фактически пересчитанными хешами файлов.
2. **Roadmap #807 не содержит детального предложения P2.3 R2.** Последний комментарий (2026-10-23T04:59:56Z) лишь констатирует «outbound_flush needs separate R2 work»; полное R2-предложение опубликовано только в комментарии PR #825. Перенос в #807 не выполнен.
3. **PR #825 не слит** — draft, READY_FOR_MERGE=false (это ожидаемо: PERF_FAIL).
4. **Цель p99 ≤ 25 мс не достигнута** — R1 механически корректен, но узкое место сместилось в `outbound_flush`; само исправление R1 остаётся «кандидатом без подтверждённого эффекта» до R2.
5. **Issue #815 (PAYLOAD_CHECKSUM_MISMATCH) остаётся открытой** — root cause неизвестен; в R1-прогонах воспроизведений не было, но дефект не закрыт.

## Локальные evidence (обновление 2026-10-23)

Корень: `C:\warehouseconstructionbackend\dws-artifacts\`. Все сырые файлы сохранены, не изменялись; SHA256 пересчитаны 2026-10-23 и совпадают с внутренними перекрёстными ссылками receipts.

### b-off-20261023-152836 (GUI OFF, 60 с, head 9d6f00fe)

| Файл | SHA256 | Размер |
|---|---|---|
| `run\manifest.json` | `460fd0fb12172ec59c5366bb7edd1d11a8cdf2e31e3cfe589d86fcdefe42edb0` | 6287 B |
| `run\report.json` | `e57364bd71559d679508bbea725d4f6784251e9239b18f113db1733ea5729be5` | 19852 B |
| `run\server\trace.jsonl` | `4442b7c3ff0e1ae7e54fe13a8987cd49a1333ce4215616f6ffad9d4aa7bc13e6` | 6 885 430 B |
| `run\server\runtime.log` | `9d489e04b44aaadaf6c352c50ec74e8d103e0898ed2d74e59cb71c2a425f0bb7` | 45 290 B |
| `run\a\trace.jsonl` | `7bc1d7409d16597f2d945bcf8b191239eef7806c70c894ebc586a7edc41aaad6` | 3 642 701 B |
| `run\b\trace.jsonl` | `60c779bc06c48e7a7befa2019f2f66ff928bbca59bc6149e0f45f001c7d4d35c` | 3 614 134 B |
| `job_receipt.json` | `bd2cc59d88dfd7a2ed715184551041077bf11d3cdf1553f825d73fbb30ec5c09` | 2011 B |

Примечание: `r1_stages.json` и `debug_fifo_receipt.json` в OFF-руке отсутствуют ожидаемо — флаг `--r31p23r1-defer-checkpoint-debug` не передавался (см. `job_receipt.json`, `command_requested`).

### b-on-20261023-153104 (GUI ON, 60 с, head 9d6f00fe)

| Файл | SHA256 | Размер |
|---|---|---|
| `run\manifest.json` | `d43bb7ce8037d9a7f691b6e8266a35f44bd8689f40db7da9cd73f1b0d174362c` | 6269 B |
| `run\report.json` | `0a8d889f4ec4350ad53217d531f6ef770186ac3fe69c15a7fe64160948e5415d` | 24 118 B |
| `run\r1_stages.json` | `3ad40e87c8b8553fd534537b5c98dc1512a44a71ea990871de9f80c934ccdc13` | 120 681 B |
| `run\debug_fifo_receipt.json` | `b0ea0587dec709665cf5820b8c9041cfe726a01856e0f969610dd9c6f008ae27` | 966 B |
| `run\server\trace.jsonl` | `d55e1dd4ef05a206d6ea2fb84e7d02e8b29acd3ccf9a0b4e84f0d11bc0e8ace3` | 6 784 181 B |
| `run\server\runtime.log` | `075961f547c10397c40ea5fbe326d5cb8ed2003deb698b6d843acc1c5697afe4` | 44 531 B |
| `run\a\trace.jsonl` | `fc9409b71ac5eb2f5ad99bfbef7d172b135f756858c1db315a645448eab8888f` | 3 647 113 B |
| `run\b\trace.jsonl` | `c27162d00cc1ca0490b96a428554d24e608788f0297d75898ba70cb483db4c34` | 3 598 398 B |
| `job_receipt.json` | `d84499f0a76e4f4c405c51ba2aa289708da2b533c4b46874ff6e772112093256` | 2054 B |

Перекрёстная проверка целостности: `debug_fifo_receipt.json` (run_id `2d6f41da7f2f4819`, main_godot_pid 21700) содержит `trace_sha256 = d55e1dd4…` и `runtime_log_sha256 = 075961f5…` — оба совпадают с фактически пересчитанными SHA256 файлов ON-руки. Verdict: `P23R1_DEBUG_AUDIT_PASS_NOT_PERF_PASS` (50 queued / 50 printed / 0 overflow).

### Сравнение и вспомогательные прогоны

| Файл | SHA256 |
|---|---|
| `compare\summary.json` | `75f050a90458b573487a5ff029589ad3dee9cbf1ca6767011ee7d86a847ab3f2` |
| `compare\off_stats.json` | `da5bcef5404231eac6da3e14354e52e5961ffbc1941a49e29fb687b2f155fdbd` |
| `compare\on_stats.json` | `be72959d76595225fa67886b5c3890821b78d1db47c7441b622470bba6937ed3` |
| `r1-focused\focused.json` | `42ee38dbaa73f63ab740d6fad79e041297cfc91c8c71df5c9b17762d9057f8f6` |
| `r1-focused\manifest.json` | `a5e738d1af91457a7878937e39bffc384c404d04c6d06a290ecfbef67f1d0945` |
| `py-tests\r31p23r1_debug_fifo_audit.out.log` | `0532d8616efd8f1d9827157847c0900ca0a6befadff7915d54ba6c626aa98d71` |
| `py-tests\r31p23_completion_source.out.log` | `41b83878dd0c0b4ec1f16e4c1390c0c3e73ecfd8d6cb6d359812aa3433f0bf30` |
| `py-tests\r31p23r1_deferred_debug_source.out.log` | `e475690b561dbf3972a0e58db507045a705183e129be00d17b3d0a9bc5d2d667` |
| `py-tests\r31p22_source_contracts.out.log` | `db89fabcc057a386e0b98f438b13a1a161c4708bd29cacd13584e86b068eaa7e` |

`r1-focused\focused.json`: 32/32 gd-тестов PASS, `head = 9d6f00fe…`, `tracked_dirty = false`, Godot 4.7.1 stable double. Файл `EVIDENCE_P23R1_WINDOWS.md` в проверенных каталогах по-прежнему не найден — сводный evidence-док существует только в виде комментария PR #825; все заявленные сырые артефакты (трейсы, receipts, сравнение) найдены и целы.

## Замечания по процессу той сессии

- Заявление «glm-flash недоступен, override модели роняет агента» — особенность харнесса той сессии; на результат не повлияло.
- Каталоги с датами 22–23.10 в этой рабочей директории (`a146-r321-win-verify-r1`, `work\net-smooth-r31bp20-independent-20261022`, `artifacts\fabric-r562-r12/r13`) относятся к другим потокам работ (fabric R562, a146, r31bp20) — к P2.3 R1 отношения не имеют.

## Рекомендуемые следующие шаги

1. ~~Восстановить/перенести сырые артефакты P2.3 R1~~ Выполнено 2026-10-23: сырые артефакты найдены в `C:\warehouseconstructionbackend\dws-artifacts\` (см. раздел «Локальные evidence»), SHA256 зафиксированы выше. Рекомендуется зафиксировать их долговечное размещение (backup/registry), чтобы доказательства не зависели от одной рабочей директории.
2. Перенести детальное предложение P2.3 R2 (outbound_flush) из комментария PR #825 в roadmap #807.
3. Готовить P2.3 R2 Work Order: сначала изолированный falsifier-инструментарий `outbound_flush` (COMPACT-сериализация vs socket-send vs batching), запрет изменения ENet и порядка сообщений до независимого подтверждения.

## Статус-строка

`P2.3 R1: WORK DONE & PUBLISHED (GitHub) / LOCAL EVIDENCE FOUND & HASH-VERIFIED (C:\warehouseconstructionbackend\dws-artifacts, 2026-10-23) / PERF_FAIL / #807 R2-PROPOSAL NOT MIGRATED / READY_FOR_MERGE=false`

Ссылки: [PR #825](https://github.com/rootfabric/distributed-world-simulator/pull/825) · [Roadmap #807](https://github.com/rootfabric/distributed-world-simulator/issues/807) · [Issue #815](https://github.com/rootfabric/distributed-world-simulator/issues/815)
