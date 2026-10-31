# NET-SMOOTH1 R4.2-P0 — Windows exact evidence (revision forensics r1)

Дата: 2026-10-12 (Asia/Vladivostok). Машина: DESKTOP-QNAGSTI, Windows 10.0.19045, Python 3.11.8, 20 CPU.

## Точный предмет

```text
HEAD: 88f976412b4c887305bdb94247e37e6881788355
TREE: 935deb587fb41e6da35d7dce79637e2d1c2c8061
Статус на момент тестов: clean (детач на удалённом HEAD ветки repair/net-smooth1-r42-p0-revision-forensics-r1)
Godot: 4.7.1.stable.double.custom_build.a13da4feb
Godot SHA256: 3633C3E609C8CE2F9BAE334A9C7E75C7F974DE3AF0415AB4A8050A625A15A7A5
```

Worktree: `C:\distributed-world-simulator\worktrees\net-smooth1-r42-p0-revision-r1`. Cold `--import` exit 0.

## Результаты тестов

| Этап | Результат |
|---|---|
| M6 revision-fence falsifier `test_net_smooth1_r42_revision_fence_diagnostics.gd` | PASS, assertions=21, failures=0, exit 0 |
| Analyzer `tests/tools/test_net_smooth1_analyzer.py` | 20/20 OK |
| Focused suites (20 ordinary + 4 process) | 24/24 PASS, включая новый r42 falsifier |
| GUI `r31-reconnect-roundtrip` × 3 (120s + 30s warmup, 2 клиента Quaternius через верифицированный локальный `-AssetSource`, r31-verify источник, 224 файла, combined SHA256 `CFCB57329BE2F01D80D5CD30108607ABE889B4442F3B835EF80240F513CA2781`) | см. ниже |
| GUI `durable-commands` × 10 (120s + 30s warmup) | см. ниже |

Первую попытку roundtrip-1 без `-AssetSource` сохранено как `r42-p0-roundtrip-1-attempt1-noverify` (INCONCLUSIVE: `actual Quaternius required for GUI acceptance` — корректный fail-closed ассет-префлайт, не продукт-дефект).

### GUI roundtrip 1–3

- server: FAIL **только по перф-порогам** (frame p99 ≈ 95 мс > 25; p99.9 > 50; gap > 100 мс; main-thread persistence > 50 мс) — известный ожидаемый R4.2-P0 performance FAIL (синхронный M6 persist); server_hz ≈ 59.9.
- Клиент a: PASS ×3 (frame p99 ≈ 23.6 мс, p99.9 ≈ 31 мс).
- Клиент b: FAIL ×3 — один frame gap ≈ 3.4 c в окне scripted reconnect + `client not continuously connected in measured phase`. В логах reconnect: `network.reconnect` → повторный `joined=true`. Классификация: функциональный reconnect завершается, но measurement-окно reconnect-х Hitch не покрывается порогами непрерывности; r31 baseline заявлял 3/3 PASS — расхождение требует отдельного разбора, не приписывается checksum repair.
- Checksum rejects: 0 во всех 3 roundtrip-прогонах (0 compact/full/payload).

### Durable 1–10 под нагрузкой

- `durable_stage_failures = 0` во всех 10 прогонах; **`SAME_REVISION_AUTHORITATIVE_MUTATION`: 0; `PERSISTENCE_FATAL`: 0**; first_changed_path не потребовался.
- checkpoint generations за 120 c: 24–26; `persist_atomic_ms` p50: 492–617 мс (известный ожидаемый тяжёлый путь, p99 ≈ 975 мс в D1); `wait_async_ms` p99 ≈ 0.
- Вердикты: D1, D3–D6, D8 = FAIL (все — perf-axis: server frame/gap/persistence, клиенты под CPU-конкуренцией); D2, D7, D9, D10 = INCONCLUSIVE.
- **Blocking functional finding:** во всех 4 INCONCLUSIVE клиент b на reconnect-join получает `MULTIPLAYER_SNAPSHOT_CHECKSUM_MISMATCH` (`simulator_app.gd:1984` ← `_handle_join_ack` → `_replica.accept_snapshot` → `player_state_snapshot.gd:67`), t ≈ 166.6–168.1 c. Воспроизводимость 4/10 под нагрузкой. Server-side join-снапшот (`m3_dedicated_server_runtime_p2.gd:532`, `_service.join(...)`) хешируется до отправки; клиент валидирует после JSON-транспорта. Первопричина **не доказана** в этой кампании.

## Классификация (п. 6 Work Order)

1. **Startup timeouts.** В этой кампании классических readiness-timeout'ов старта нет. Orchestrator классифицировал 4 прогона как `b readiness timeout`, но фактическая причина — отказ join-а по checksum (см. выше), т.е. это frame-layer класс, а не стартовое планирование.
2. **Frame-layer checksum errors.** Воспроизводимый дефект: reconnect-join `MULTIPLAYER_SNAPSHOT_CHECKSUM_MISMATCH`, подтверждён минимум в 5/10 durable-прогонов: b-клиент durable-2/7/9/10 (отказ join, t ≈ 166.6–168.1 c) **и** client a в durable-5 (`last_error_code` в periodic-details, прогон классифицирован FAIL, а не INCONCLUSIVE). Таким образом класс не ограничивается клиентом b и reconnect-join — учесть в repair Work Order. Проверена и **опровергнута** гипотеза ULP-осцилляции `_wire_number` (probe `artifacts/net-smooth1/r42-p0-import/wire_oscillation_probe.gd`: 0/400000 не сходящихся double; случайные float в диапазоне ±2000 сходятся ≤1 итерации). Требуется инструментирование точки отказа (capture payload при `validate` на клиенте и при `create` на сервере) — это отдельный узкий repair Work Order. Блокирует VERIFIED.
3. **Project Control `CANDIDATE_MAIN_DRIFT`.** origin/main = `e98a489b591bb29025ffb69a6dbbf1c87b3b1542`; merge-base с веткой = `53567c0b98d032260dfe81df4bd43a131e32da54`; ветка опережает merge-base на 102 коммита, main ушёл вперёд на 40 — кандидат **не** актуален к main, merge без catch-up/rebase невозможен. Классифицируется как ожидаемый drift long-lived repair-ветки, не как дефект кода.

## Вывод о M6

- Строгий revision fence сохранён: gate `SAME_REVISION_AUTHORITATIVE_MUTATION` в `authoritative_checkpoint.gd` не ослаблен; новых путей его срабатывания в 10 durable-прогонах под нагрузкой **не выявлено**.
- Новый falsifier доказывает диагностическую пригодность `first_changed_path` (schema-path, без payload) на контроле класса.
- Production M3 ACK gate, M6 writer, on-wire checksum, replay не изменялись в этой сессии (HEAD = заявленный docs-коммит).

## Производительность (без ослабления порогов)

Пороги client frame p99 ≤25 мс / p99.9 ≤50 мс / no >100 мс gap / server ≥59 Гц / no >50 мс main-thread persistence сохранены без изменений. Подтверждён ожидаемый perf FAIL: синхронный M6 persist даёт server frame p99 ≈ 95 мс (roundtrip) и persist_atomic p50 ≈ 0.5–0.6 c (durable). **Нулевое заявление об улучшении p99.** R4.2-P1 (bounded single-writer async durable path) остаётся обязательным этапом устранения.

## SHA256 evidence

```text
focused/*:  BCE64C0C5547B939C311288CDED27294474B6D9EE8E1C8433BE65B874F8BFB4A
falsifier.log: DDFFC84E97BAA76C15B47EB360ACCAEF2B75E500DE37F9F12F1315ED86D52208
analyzer.log:  E8CEEC9C5BB95FA542F07C068140898A3C2B86E43DEEF11EF19DFD68B4BA30C6
roundtrip-1: BC35E62797213043374120703B0B4DCD479EDA63B8237BD5222D3AD84B439E0A
roundtrip-2: 2849410078F1E9C5DCB81233DE8E2CAF47FF977A24094866525C8438B28CDC8D
roundtrip-3: 4DC02E2BF7997385631AB834F90B8E5EA415405DAB50DEBCF4334D5F99C09E9E
durable-1:  2B02A0C3246A43042D54E2818F8B500E1D9C5B0EEF4C0E47A60086E236D9D83A
durable-2:  9D8605BDC17A7A7ACEA82F30DC0DFF0CCF8AD9434979AF21EA2CD72FE95B827E
durable-3:  3DED57FD0E50D879F677A404B9CD9FC45CC6458341209CBE3321FBC0B3C6D0D6
durable-4:  1B5E804FE268A70DEA94163C60CE0598FB0B9893E4CA47F06C18ED79531ABE0C
durable-5:  0779AD80E9B34F1A86BCA59ABD0239998F092FF57FF67FED078B301E9EFB51D7
durable-6:  272E2EAFAD9988C9CFA83A23D7F0DBF6906790C6F90EADB8AC3571D0CC2AC333
durable-7:  1F3B6E8BEB6BE78693D01D19FDD346DB2264BAA04796091A006E7E9EB6F942E4
durable-8:  3A4073F7FF0DDEDEB0A1E7E18E3D85146F175914AB44B7893BD0505243176772
durable-9:  14BD7A53C5950C02863658BEF73005523F03255ADC883FD784561F362BCD3B0C
durable-10: D4E6FE45AE7AEB14AF018AC3FA52219EE442CC149B8EADFD6B7167DDC62B124B
```

## Готовность к R4.2-P1

Готовность условная. Перф-этап P1 может стартовать (цель и пороги определены, evidence полный), но перед/параллельно с ним обязателен узкий repair-Work Order на reconnect-join checksum defect (инструментирование payload + конкретный владелец), так как этот класс блокирует любой VERIFIED на GUI-сценариях с reconnect. Merge PR #758 — по-прежнему human gate; самопринятие запрещено.

## Передача независимому Reviewer/Verifier

Рекомендуется fresh exact-head review/verifier на итоговом HEAD этой ветки после публикации evidence-коммита, а также отдельный Linux Reviewer по желанию Director. Все сырые логи сохранены в `artifacts/net-smooth1/r42-p0-*` (не удалять; `report.json` каждого прогона захеширован выше).
