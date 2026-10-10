# NET-SMOOTH1 R3 — Windows exact-head отчёт (реализация, не независимая верификация)

Статус: **реализаторский отчёт (GUI_LOCAL_CANDIDATE). НЕ VERIFIED. Независимая приёмка отдельна. Merge не выполнялся.**

## Точная идентичность субъекта

| Параметр | Значение |
|---|---|
| Branch | `repair/net-smooth1-char2-r1` |
| HEAD (тестируемый) | `e7b218b8961ca4e74dc1c1687054eedb49c7dbca` |
| TREE (тестируемый) | `1b05261211709f7ba23d7088a3db0347d052f2c7` |
| Godot | 4.7.1.stable.double.custom_build.a13da4feb, SHA256 `3633c3e609c8ce2f9bae334a9c7e75c7f974de3af0415ab4a8050a625a15a7a5` |
| Платформа | Windows-10-10.0.19045, Python 3.11.8, CPU 20 |
| tracked_dirty | false (только несущественные untracked `.uid`) |
| Дата прогонов | 2026-10-10/11, Asia/Vladivostok |

Артефакты: `artifacts/net-smooth1/r3-win-focused`, `r3-gui-final-1`, `r3-gui-clean-1..2` (чистая тройка), `r3-seam-stress` + `r3-seam-stress-try1..4`, `r3-negative-server`, `r3-negative-client-a`. `focused.json` фиксирует head/tree/godot_sha256 для каждого набора. Полные трейсы `trace.jsonl` по ролям (server/a/b) в каждом прогоне; скриншоты и `avatar-status.json` в `r3-gui-*/{a,b}/`.

**Замечание о среде.** Во время цикла параллельная внешняя миссия держала загрузку CPU 63–93 %. Из-за этого часть стартов ушла в INCONCLUSIVE: сервер становился готов на 2–9 с позже, чем в R2, и клиенты уходили в свой 15-секундный `M3_CLIENT_CONNECT_TIMEOUT` (стартовая гонка среды, не продукт; пороги/конфиг не менялись). Все INCONCLUSIVE-прогоны сохранены (`r3-gui-async-1..3`, `r3-gui-async-retry-1`, `r3-gui-final-3/4/6`, `r3-seam-stress-try*`); ниже используются только полностью завершённые прогоны. Отдельно помечен `r3-gui-final-2/5` (завершены, но под пиковой нагрузкой: 57.2–57.9 Гц) — в A/B не включены как «чистые».

## 1. Юнит и focused-тесты

- Анализатор: `python -m unittest discover -s tests/tools -p test_net_smooth1_analyzer.py` — **16/16 OK** (R2: 11/11; R3 добавил stage/seam-тесты анализатора).
- Focused: **19 наборов (15 обычных + 4 process) — 19/19 PASS, exit 0.**
- Новый `tests/network/test_net_smooth1_seam_change_delivery.gd` — **PASS, assertions=86, failures=0** (по логу `NET_SMOOTH1_SEAM_DELIVERY: PASS assertions=86`).
- `test_m6_dedicated_recovery_processes` — **PASS в R3** (в R2 классифицировался как pre-existing FAIL; на R3-head красных focused-наборов нет).

## 2. GUI-приёмка: чистая тройка по 120 c (warmup 30 c), два реальных Earth-клиента, Quaternius

Прогоны: `r3-gui-final-1`, `r3-gui-clean-1`, `r3-gui-clean-2`. Все: `manifest.completed=true`, `functional_scenario=PASS`, 0 ошибок рантайма, `server_disconnects=0`, reconnect_b — success, ownership epoch 1→2. Quaternius у обоих клиентов: `provider_id=avatar/quaternius`, `asset_mode=QUATERNIUS_RETARGET`, `ready=true`, `legacy_capsule_visible=false`. `backwards_holds=0` у всех ролей; HOLD-режимы (клиент a/b): INTERPOLATE 7085–7426, EXTRAPOLATE 1792–1997, HOLD 188–260, BUFFERING 1–30.

### Сервер (мс)

| Прогон | метрика | n | p50 | p95 | p99 | p99.9 | max | tick_hz |
|---|---|---|---|---|---|---|---|---|
| final-1 | frame_ms | 6198 | 13.981 | 41.278 | 125.564 | 189.418 | 382.777 | 59.30 |
| final-1 | server_ms (loop) | 6198 | 4.919 | 29.157 | 114.615 | 171.162 | 303.377 | |
| final-1 | message_ms | 6198 | 2.467 | 6.600 | 106.029 | 160.949 | 302.416 | |
| final-1 | persistence_ms | 6198 | 0.343 | 0.613 | 54.946 | 90.697 | 102.195 | |
| clean-1 | frame_ms | 6154 | 11.808 | 41.917 | 128.989 | 171.586 | 207.969 | 59.59 |
| clean-1 | server_ms (loop) | 6154 | 5.226 | 30.379 | 123.800 | 167.030 | 194.350 | |
| clean-1 | message_ms | 6154 | 2.669 | 7.047 | 118.365 | 160.476 | 172.143 | |
| clean-1 | persistence_ms | 6154 | 0.365 | 0.705 | 64.284 | 86.729 | 99.542 | |
| clean-2 | frame_ms | 6168 | 11.867 | 42.158 | 128.249 | 173.001 | 209.426 | 59.46 |
| clean-2 | server_ms (loop) | 6168 | 5.152 | 30.111 | 123.738 | 167.017 | 205.151 | |
| clean-2 | message_ms | 6168 | 2.739 | 6.971 | 119.203 | 158.690 | 185.087 | |
| clean-2 | persistence_ms | 6168 | 0.362 | 0.684 | 64.156 | 91.048 | 122.390 | |

Server tick Hz 59.30–59.59 — бюджет ≥59 Гц соблюдён.

### Клиент a (frame_ms, мс)

| Прогон | n | p50 | p95 | p99 | p99.9 | max |
|---|---|---|---|---|---|---|
| final-1 | 7176 | 15.628 | 27.993 | 30.855 | 35.847 | 291.884* |
| clean-1 | 7201 | 15.275 | 28.176 | 31.258 | 36.609 | 68.805 |
| clean-2 | 7211 | 15.366 | 28.040 | 31.148 | 34.846 | 38.864 |

### Клиент b (frame_ms, мс)

| Прогон | n | p50 | p95 | p99 | p99.9 | max |
|---|---|---|---|---|---|---|
| final-1 | 7173 | 15.489 | 27.846 | 30.964 | 35.359 | 332.047* |
| clean-1 | 7184 | 15.114 | 28.200 | 31.287 | 35.637 | 97.697 |
| clean-2 | 7209 | 15.092 | 28.167 | 31.502 | 36.410 | 74.943 |

\* единичный выброс в final-1 (внешняя конкуренция CPU); p99/p99.9 от него не зависят.

### Сравнение с R2 (пороги не менялись)

| Метрика | R2 (5bae3293) | R3 (e7b218b8), медиана чистой тройки | Δ |
|---|---|---|---|
| **`send_and_seam_ms` p50** | 20.51–22.36 | **13.56 / 14.65 / 14.74** | **−33…−36 %** |
| **`send_and_seam_ms` p99** | 33.85–42.05 | **23.58 / 25.51 / 26.32** | **−30…−39 %** |
| **Серверный loop p99** | 121.26–130.43 | **114.62 / 123.74 / 123.80** | −1…−7 мс (~−1…−6 %) |
| **Клиентский frame p99** | 32.38–32.61 | **30.86–31.50** | ≈ −1.1…−1.5 мс |
| Клиентский frame p99.9 | 36.35–37.65 | 34.85–36.61 | ≈ −1 мс |
| `message_ms` p99 | 118.28–118.28+ | 106.03–119.20 | без существенного изменения |
| `persistence_ms` p99 | 62.81–65.64 | 54.95–64.28 | без существенного изменения |
| Серверный frame p99 | 126.19–135.57 | 125.56–128.99 | без существенного изменения |

**Главный вопрос R3 подтверждён**: узкий seam-repair (подавление повторной 20 Гц отправки неизменённого `PRODUCT_SEAM_STATE`) снизил `send_and_seam_ms` p50 на ~6–8 мс и p99 на ~10–16 мс; `seam_check_send_ms` (новая стадия) стоит p50 ~0.13 мс, p99 0.35–0.44 мс. Но серверный loop p99 определяется теперь не seam-путём, а `message_ms` p99 ~106–119 мс и `persistence_ms` p99 ~55–64 мс — они не входили в скоуп R3 и остались на уровне R2.

**Вердикт по performance: FAIL** — клиентский frame p99 30.9–31.5 мс > 25 мс; серверный frame p99 125.6–129.0 мс > 25 мс, p99.9 167–173 мс > 50 мс; loop gap > 100 мс; main-thread persistence p99 55–64 мс > 50 мс. Все пороги исходные (25/50/100 мс, ≥59 Гц), не менялись.

**Вердикт функциональный: PASS** — 3/3 прогонов: соединение обоих клиентов до конца, движение в 8 фаз (в т.ч. sprint, разворот, stop/start), Quaternius remote у обоих, reconnect_b с ростом ownership epoch, 0 backwards-hold, snapshot_received 2143–2153 на клиента за окно (потерь снапшотов нет), correction_m p99 ≤ 0.4 м, max ≤ 1.2 м.

## 3. Стадии снапшота (trace, ms)

### Сервер: `movement_snapshot_stages` (n = 2819–2828 на чистый прогон)

| Стадия | p50 | p95 | p99 | max (худший) |
|---|---|---|---|---|
| capture_ms | 0.906–1.016 | 1.374–1.907 | 2.045–3.194 | 16.77 |
| encode_ms | 1.355–1.604 | 2.099–2.943 | 2.978–4.592 | 20.99 |
| `compact_send_ms` | 13.40–14.58 | 19.19–19.27 | 25.30–26.15 | 52.26 |
| `seam_check_send_ms` | 0.132–0.134 | 0.234–0.243 | 0.386–0.444 | 2.91 |
| `send_and_seam_ms` (сумма) | 13.56–14.74 | 19.44–19.53 | 25.51–26.32 | 52.50 |

`seam_sent` в измеряемом окне: **0** (JOIN обоих клиентов до `measure.start` — ожидаемо); `seam_skipped_unchanged`: **5635–5654** за прогон (≈2 на снапшот, по одному на клиента — дедупликация работает ровно как задумано, без «лавинообразного роста» и без потери JOIN/resync).

### Клиенты: `compact_snapshot_stages` (мс, n = 2143–2153 в окне, 2613–2801 в трейсе)

| Стадия | p50 | p99 | max (худший) |
|---|---|---|---|
| decode_ms | 1.17–1.26 | 1.81–2.12 | 4.84 |
| accept_ms | 0.83–0.89 | 1.33–1.58 | 3.55 |
| reconcile_ms | 1.44–1.66 | 2.38–2.94 | 4.61 |
| presentation_ms | 0.48–0.54 | 0.89–1.10 | 2.66 |

Клиентский hot-path дёшев (~4 мс p50), как и в R2; клиентский frame p99 ~31 мс создаётся рендером/кадровым циклом, не сетевой обработкой.

## 4. Seam-stress и reconnect

- `r3-seam-stress` (+ try1–try4): 180 с + warmup 30 с, 5 запусков. В 5/5 фаза reconnect клиента b воспроизводит **задокументированный known finding** `USER1_SEAM_JOIN_FROZEN_WHILE_PLAYER_REMOTE` (`b/errors.txt`, JOIN_REJECTED при оставшемся remote-пире a) — контракт описан в `NET_SMOOTH1_WINDOWS_RU.md` как отдельный repair, устранять отключением seam запрещено. По этой причине orchestrator фиксирует `orchestrator incomplete`, verdict прогона **INCONCLUSIVE**.
- Фактические переходы: в измеряемом окне p‌imary↔secondary roundtrip не зафиксирован; одно изменение seam-состояния в окне доставлено надёжно (`seam_sent=1`, `seam_skipped_unchanged` продолжал расти; `seam_check_send_ms` p50 0.10–0.16 мс при 7965 снапшотах). По критерию документа («нет фактического crossing/roundtrip → INCONCLUSIVE, не PASS») **seam-stress: INCONCLUSIVE** — как по отсутствию roundtrip, так и по блокировке reconnect-фазы known finding.
- Надёжный ordered delivery вне stress-сценария подтверждён: в чистой GUI-тройке reconnect_b — success, ownership epoch 1→2, 0 disconnects; focused process-наборы `test_m7_playable_networked_recovery_processes`, `test_m6_dedicated_recovery_processes` — PASS. Ложных `USER1_PRODUCT_SEAM_STATE_STALE` и потери remote-аватара в чистых прогонах не зафиксировано (remote_count=1 у обоих клиентов, `problems=[]`).

## 5. Негативные контроли (инжекция 250 мс)

| Прогон | Роль инжекции | Exit | `injected_stall` в trace | Дополнительно |
|---|---|---|---|---|
| r3-negative-server | server | 1 | да, ровно в `server/trace.jsonl`, `{"duration_ms":250}` | loop gap/persistence уже FAIL в базе |
| r3-negative-client-a | a | 1 | да, ровно в `a/trace.jsonl`, `{"duration_ms":250}` | у клиента a появился frame gap >100 мс, отсутствующий в чистых прогонах |

Детектор работает: событие фиксируется именно в инжектируемой роли. Оговорка как в R2: базовый сервер по gap/persistence уже FAIL, поэтому по серверной роли дискриминация ограничена; по клиенту a — чёткий дифференцирующий признак.

## 6. Итоговый вердикт

**FAIL (performance), функционально PASS, регрессов против R2 нет; главный целевой показатель R3 (`send_and_seam_ms`) улучшен на 30–39 % (p99) без изменения wire-schema, бюджетов и порогов.** Merge не выполнялся; VERIFIED не объявляется (нужна независимая проверка). 19/19 focused PASS, включая 86/86 нового seam-delivery теста и ранее падавший M6 process-набор.

## 7. Следующие узкие шаги (по стадийным измерениям, без изменения порогов)

1. **Серверные хвосты теперь не в seam-пути**: `message_ms` p99 ~106–119 мс и `persistence_ms` p99 55–64 мс коррелируют с frame/loop хвостами — sync durable command checkpoint, как и планировано, отдельный HIGH-risk slice (ordered durable journal + crash-matrix, без premature ACK).
2. `compact_send_ms` p50 13.4–14.6 мс — оставшаяся дорогая часть стадии снапшота; если требуется следующий performance slice — отделить `Frame.create/validate`, очередь и flush.
3. Клиентский frame p99 ~31 мс при дешёвом снапшот-пути (~4 мс) — отдельная стадийная CPU/render диагностика клиента.
4. Контракт reconnect при remote-пире (`USER1_SEAM_JOIN_FROZEN_WHILE_PLAYER_REMOTE`) — отдельный repair по `NET_SMOOTH1_WINDOWS_RU.md`; до его приёмки seam-stress остаётся INCONCLUSIVE по reconnect-фазе.

## 8. Доказательства (sha256)

| Файл | SHA256 |
|---|---|
| `r3-win-focused/focused.json` | `7a1c3536e8d295f1f1d2f25b34f2cabd382be066b36986f0a7ce305871657d9e` |
| `r3-gui-final-1/manifest.json` | `6e3629bad6f1a821364db81d02a621c1a5568cdc031f330fe9862c96d00cc3f5` |
| `r3-gui-final-1/report.json` | `65dd0a7122e85c76be57cd8c3389b6b786dedca9fbf936db0d468ac4d0293320` |
| `r3-gui-final-1/server/trace.jsonl` | `c761ca6a2a5fed22973f2cb34817b778e5d02c8c50aaa490f62fdcd9276c9209` |
| `r3-gui-clean-1/manifest.json` | `72abdbaac3671a4abb29ff2e792ee1c1b7591e734b76659110c9738efd37b235` |
| `r3-gui-clean-1/report.json` | `e782aa4fbc2ad6cb4098ba5a8406d2640fb300636020eac76d8f35ee31d5bbc1` |
| `r3-gui-clean-1/server/trace.jsonl` | `65b750af803445f0fcfdea0d9c506e6a32c4062f6a07cd7cda31e1af0a2b4236` |
| `r3-gui-clean-2/manifest.json` | `5a508158f4eaf348f215881803feb3a25270327e1e945ec4cf2fe57d390e508a` |
| `r3-gui-clean-2/report.json` | `5bb0a2bf891f2560019e36659a793003f280db6dfad6cecedf77fd8560709291` |
| `r3-gui-clean-2/server/trace.jsonl` | `db9728f49ec5e9bd20ae8a5d67173454e64e9a0b03732681912f7c5908308057` |
| `r3-negative-server/server/trace.jsonl` | `baa975f86742e8ea50574602fd436a08cbf409cb2965e33adf2065d7524a0245` |
| `r3-negative-client-a/a/trace.jsonl` | `dfdd443f7eec35d3cdbca25f1ea446430aa86604d49b3fe1bde82894d4ea397c` |
| `r3-seam-stress/report.json` | `a2640c5cd5b0ded62201ab823cc216bc702f6df6059b1240e10b759e3a9daa44` |
| `r3-seam-stress/server/trace.jsonl` | `24dfba451b7fbe92f6ccc67eafe7a5a9cfb814e9c986e15f153fe780f635b903` |

Инструмент анализа: `artifacts/net-smooth1/r3-analysis.py` (перцентили из `report.json` + `trace.jsonl`).

## 9. Оговорки

- Реестр INCONCLUSIVE-стартов (стартовая гонка клиент-таймаута под внешней CPU-конкуренцией) сохранён и не скрывался; чистая тройка отобрана по критерию `tick_hz ≥ 59`, `manifest.completed=true`, 0 ошибок рантайма. Это не «перебор до зелёного»: все включённые прогоны имеют verdict FAIL по performance.
- Reconnect-контракт seam-stress — известный documented finding, воспроизведён 5/5; заказ на его исправление принадлежит отдельному repair, не R3.
- Persistence/replay caveats R2 остаются: async checkpoint-write измеряется как `persistence_ms`; durable journal и crash-matrix — вне скоупа R3.
- Отчёт реализатора; независимый Reviewer/Verifier и решение владельца — до любого merge.
