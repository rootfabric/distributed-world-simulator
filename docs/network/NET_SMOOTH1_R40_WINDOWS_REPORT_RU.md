# NET-SMOOTH1 R4.0 — Windows exact diagnostics: отчёт о фактах

**Субъект:** ветка `repair/net-smooth1-r4-durable-commit-r0`, PR #754.
**Базовый опубликованный HEAD задания:** `acdb715f5d23e91ad9d314da57c04a64ff346643`, tree `b4d898c885e136b595a4f2090bf4a139f44bf491`.
**HEAD реализации durable-workload сценария:** `829ba2e39a0d691ac5b5952e4af093fb31330973`, tree `41d54e79779d51775ef09f9d3f64c19fc453aaea`.
**Godot:** 4.7.1.stable.double.custom_build.a13da4feb, SHA256 `3633C3E609C8CE2F9BAE334A9C7E75C7F974DE3AF0415AB4A8050A625A15A7A5` (совпадает с `NET_SMOOTH1_R40_WINDOWS_RU.md`).
**Verdict:** R4.0 telemetry измерена; performance FAIL ожидаем и пороги не менялись. **Не VERIFIED, merge запрещён** — требуется независимый Reviewer/Verifier.

## 1. Что сделано

1. Python analyzer: 20/20 PASS (`test_net_smooth1_analyzer.py`), включая R4-тесты `durable_stage_metrics`, invalid/negative → INCONCLUSIVE, `success=false` → FAIL. Прогон на `acdb715f` и повторно на `829ba2e3` — OK.
2. Focused-набор: на `acdb715f` — 19/20 PASS + 1 timing-flake; на `829ba2e3` — тот же результат (см. §4).
3. **Durable-workload сценарий** (новый, `--Scenario durable-commands`):
   - allowlist строго из 2 реальных авторитетных ITEM_COMMAND: `inventory.select_hotbar`, `inventory.permission_probe` (self);
   - команды идут через обычный клиентский seam `execute_item_command_blocking` → сервер `_handle_item_command` → `_persist_command_result` (durable-before-ACK);
   - оркестратор добирает ≥24 non-replay успешных коммитов (cap 60 попыток), каждый с уникальным `operation_id`;
   - дубликат первого `operation_id` обязан вернуться как идемпотентный replay **без изменения revision**;
   - `manifest.durable_stages_required=true` → analyzer требует непустые `durable_command_stages` и `durable_checkpoint_stages`, иначе INCONCLUSIVE;
   - rejection никогда не считается коммитом (ранний `raise`).
   - Новый тест: `tests/runtime/test_net_smooth1_r40_automation_item_command.gd` — 9/9 PASS (allowlist, reject extra/missing fields, revision++, duplicate replay без мутации).

## 2. GUI A/B факты (`artifacts/net-smooth1/r40-gui-durable`)

Сервер + 2 GUI клиента Earth/Quaternius (`avatar/quaternius`, `QUATERNIUS_RETARGET`, ready), 120s измеряемое окно + warmup; сценарий `durable-commands`; движение A/B и reconnect B сохранены как в `local`.

- `durable-commands.json`: **24 успешных durable-коммита**, 2 типа, дубликат = replay, `item_graph_revision` монотонно рос по каждому коммиту.
- Server: **25** `durable_command_stages` (24 + периодический) и 25 `durable_checkpoint_stages`, все `success=true`, 0 durable failures; checkpoint generation росла с каждой командой (по одной на команду + periodic), `origin=COMMAND` подтверждён анализатором.
- Client blocking success возвращается **только после** `persisted.success` → **нет успешного ACK до долговечного commit** (структурно: `_send_result` после `_persist_command_result`).
- Повторная команда (тот же `operation_id`+payload) — replay, revision не изменился → **мир не мутирует дважды**.

### Stage-метрики сервера (p50/p95/p99/p99.9/max, ms)

| Стадия | p50 | p95 | p99 | p99.9 | max |
|---|---|---|---|---|---|
| command_player_checksum_ms | 0.48 | 0.90 | 0.98 | 0.98 | 0.98 |
| command_item_graph_checksum_ms | 0.74 | 1.37 | 1.42 | 1.42 | 1.42 |
| command_outbox_stage_ms | 122.27 | 220.59 | 222.98 | 222.98 | 222.98 |
| command_checkpoint_total_ms | 858.10 | 2823.83 | 2836.90 | 2836.90 | 2836.90 |
| checkpoint_wait_async_ms | 0.01 | 1293.54 | 1417.09 | 1417.09 | 1417.09 |
| checkpoint_quiesce_ms | 13.24 | 18.50 | 23.71 | 23.71 | 23.71 |
| checkpoint_persist_atomic_ms | 846.02 | 1518.54 | 1601.97 | 1601.97 | 1601.97 |

Server loop (n=2444): `message_ms` p50=1.74, p95=8.07, **p99=883.01, p999=3754.75, max=3874.28**; `persistence_ms` p50=0.26, p95=0.50, **p99=352.78, p999=422.37, max=431.46**; frame p99=1274.34, max=4190.37; tick ≈23.2Hz (<59 FAIL).
Clients: frame p50≈16.5, p99≈29.4–29.6 (FAIL >25), p99.9≈1259–1328 (FAIL >50), max≈5019–5425 (FAIL >100).

### Сопоставление со spikes

99 `server_stall` аномалий. Основной вклад: `wait_async_ms` (ожидание предыдущего async movement checkpoint, до 1417ms) + `persist_atomic_ms` (846–1602ms) суммарно объясняют `checkpoint_total_ms` до 2837ms и коррелируют с `message_ms` spikes 350–3874ms в окне команд; `persistence_ms` spikes 352–431ms соответствуют синхронной части commit. Checksum-стадии дёшевы (<1.5ms) — тяжёлые стадии: **wait_async + persist_atomic + outbox_stage**. Это и есть цель R4.1.

**Environment caveat:** во время GUI-прогона и части focused-прогонов на хосте параллельно работал чужой процесс (`Godot_v4.7.2` из `C:\warehouseconstructionbackend`, max CPU) и периодические headless ecology-тесты другой сессии; CPU load 64–68%. Чужие процессы не завершались. Абсолютные значения следует читать как верхнюю оценку; относительная структура стадий (checksum дёшев, persist/wait дорог) устойчива.

## 3. Project Control --candidate (воспроизведение CANDIDATE_MAIN_DRIFT)

Локально воспроизведена точная CI-команда (`.github/workflows/project-control.yml`, шаг "Check product coordination"):

```
PYTHONPATH=scripts python -m harness.cli check-consistency --candidate
```

Результат: `ok=false`, exit 3 (`CONTRACT_OR_DEPENDENCY_INVALID`), finding:

- `CANDIDATE_MAIN_DRIFT` (ERROR, product_blocking): **Observed main `3d7672cba293d8e7bd72427b803f73fc8fcee5da` != canonical main `fc69771a6a536463010ca880f03c27b3aa66e45e`**; provenance: `canonical_ref=origin/main`, `LOCAL_GIT_REFS_ONLY_NO_FETCH`, registry_generation 82.

Это тот же красный gate, что и в GitHub CI. Main-owned registry из repair-ветки **не исправлялся**, gate не подменялся локальным `-CheckConsistency`, error не скрывался. Это отдельная candidate authority issue.

## 4. Известные наблюдения (без изменения порогов)

- `test_m6_dedicated_recovery_processes.gd`: 4 прогона в этой сессии — 2 PASS (128/0), 2 FAIL на одном и том же assert `A observed dedicated crash`. Во всех FAIL-случаях итоговое состояние файла `seed-a.json` = `DISCONNECTED_AFTER_CRASH`, но запись происходила на границе/за пределами окна `DISCONNECT_TIMEOUT_MS=45s`: обнаружение force-kill клиентом (ENet timeout) занимает ~45s+ под нагрузкой хоста. Все durability-ассерты (checkpoint generation, durable commits, recovery checksums, replay, отсутствие двойных мутаций) проходят в каждом прогоне. Классификация: **harness timing flake**, не регрессия durability; пороги/окна не менялись, вопрос вынесен в R4.1 follow-up.
- Один headless запуск имел `M3_CLIENT_CONNECT_TIMEOUT` у клиента b (фоновая нагрузка); инфраструктурный, повтор прошёл.
- Performance thresholds: frame p99≤25ms, p99.9≤50ms, max≤100ms, server≥59Hz, no main-thread persistence>50ms — **не изменены**; их нарушение и есть измеренный R3/R4.0 hotspot.

## 5. Evidence manifest

- `artifacts/net-smooth1/r40-focused` — focused 20 наборов на `acdb715f` (19/20 + flake);
- `artifacts/net-smooth1/r40-focused-postchange` — focused на `829ba2e3` (19/20 + тот же flake);
- `artifacts/net-smooth1/r40-gui-durable` — GUI A/B durable-workload (полный: manifest, report.json/md, traces `server|a|b/trace.jsonl`, `durable-commands.json`, phases, screenshots, world checkpoints);
- `artifacts/net-smooth1/r40-durable-smoke10` — headless контрольный прогон сценария (24 коммита, идемпотентный replay);
- Логи `Project Control --candidate` воспроизведены и процитированы в §3.

## 6. Следующий шаг — R4.1 (подготовка, не реализация в этой поставке)

Неблокирующий durable commit с отложенным ACK по design brief (`NET_SMOOTH1_R4_DURABLE_COMMIT_DESIGN_RU.md` §R4.1):

- переиспользовать `async_checkpoint_writer.gd` + M6 outbox; полный detached checkpoint вне главного цикла;
- **нельзя подтверждать команду раньше долговечного commit**: ответ в bounded pending-ACK до успешного atomic commit; FAIL_CLOSED при отказе;
- сериализация поколений: строгий порядок по generation, монотонный progression, epoch/session fences, bounded queue с backpressure, без busy-spin/`Thread.wait_to_finish` из `_process`;
- данные R4.0 указывают цели: `wait_async_ms` (конкуренция с movement writer) и `persist_atomic_ms` (846–1602ms) — serialization поколений и вынос atomic commit из кадра дают основной выигрыш; checksum-стадии оптимизировать не нужно;
- обязательна crash/fault матрица R4.2 (crash между стадиями, duplicate operation_id, stale epoch) и независимая приёмка (свежий Reviewer/Verifier + 4h soak).

**No merge. No self-VERIFIED.** Реализатор не может сам принять эту работу.
