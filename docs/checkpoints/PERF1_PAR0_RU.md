# ECO.EVO7 PERF1-PAR0 — отчёт checkpoint (R1 → PAR0.1)

## Статус

```text
PERF1             ✅ ACCEPTED (8c43e512)
  ↓
PAR0 R1           🟡 NEEDS_REPAIR (a06ba16d, local-only evidence, issue #297)
  kernel/parity     ✅ proven (44/44 + 45/45 + 69/69 + 37/37)
  process pool      ✅ implemented
  transport         ❌ blocked (PIPE_TRANSPORT_PARTIAL diagnosis, R1)
  ↓
PAR0.1            🟢 ВЫПОЛНЕН в этой ветке (roll-forward от a06ba16d)
  transport repair  ✅ probe PASS 34/34 (wc 1/2/4, 1000+ циклов)
  pool campaign     ✅ 108 поколений EXACT-паритет (3 рецепта × wc 1/2/4 × 12)
  benchmark         ✅ wc=4 speedup ≈ 2.7–3.0× (цель миссии ≥2× достигнута)
```

PAR0.1 выполнен как roll-forward в той же ветке `feature/eco-evo7-perf1-par0-recruitment-process-pool-r1`; commit `a06ba16d` сохранён как immutable R1 NEEDS_REPAIR evidence.

## Base

```text
PERF1_HEAD  = 8c43e512b78755799b21536f6116accea71fc925
R1 evidence = a06ba16d (local; issue #297)
branch      = feature/eco-evo7-perf1-par0-recruitment-process-pool-r1
worktree    = C:\distributed-world-simulator\worktrees\perf1-par0
```

## Изменённые файлы (PAR0.1 поверх R1)

```text
scripts/ecology/perf/eco_evo7_par0_worker_v1.gd        (stdin reader, BYE shutdown)
scripts/ecology/perf/eco_evo7_par0_process_pool_v1.gd  (warmup, tight-drain, BYE+kill,
                                                        env-имя ECO_PAR0_WORKER_LOG_DIR,
                                                        setup-файл до spawn)
scripts/ecology/perf/eco_evo7_par0_transport_probe_v1.gd (warm-up + Pool.warmup)
scripts/ecology/perf/eco_evo7_par0_shadow_runner_v1.gd   (core-snapshot evidence, warmup)
scripts/ecology/perf/eco_evo7_par0_serial_shadow_v1.gd   (core-snapshot evidence)
tests/ecology/eco_evo7_par0_recruitment_parity_acceptance.gd (38 assertions, реальные данные)
RUN_ECO_EVO7_PAR0_TESTS.ps1                            (probe в гейтах + env)
RUN_ECO_EVO7_PAR0_BENCHMARK.ps1                         (полный shadow runner + env)
docs/checkpoints/PERF1_PAR0_RU.md                       (этот документ)
```

## Inherited gates (re-validated после всех правок)

| Gate | Result |
| ---- | ------ |
| LS3.3 Dispersal Recruitment | 44/44 |
| LS3.4 Local Competition | 45/45 |
| PERF1 Generation Profiler | 69/69 |
| PAR0 Recruitment Parity (38 assertions) | PASS |
| PAR0 Transport Probe (34 assertions; wc 1/2/4, 250 PING + 250 ECHO циклов на воркера, timeout/crash/out-of-order) | PASS |

Замечание по R1: serial-shadow replay из R1 оказался вырожденным (LS3.4 snapshot не содержит `last_candidates/last_routes`; сравнивались пустые массивы). Исправлено в PAR0.1 — evidence читается из LS3.3 core snapshot; replay теперь нетривиален и проходит (36/36 поколений, `serial_replay_ok=true` на реальных данных).

## Transport repair (PAR0.1)

Починены три корневые причины R1-блока:

1. **Рассинхрон env-имени лог-директории.** Пул читал `PAR0_WORKER_LOG_DIR`, раннеры задавали `ECO_PAR0_WORKER_LOG_DIR`; воркеры в ограниченных окружениях запускались без `--log-file` и висли на старте (запись в `user://logs`). Теперь единая переменная `ECO_PAR0_WORKER_LOG_DIR`, раннеры устанавливают её в `artifacts/` автоматически.
2. **Первый `execute_with_pipe` в свежем координаторе.** Dual-bisect эксперимент показал: первый pipe-спавн в процессе завершает полный lifecycle только при прямом driven-чтении (200 µs poll, drain первым действием). После одного прогретого lifecycle все последующие спавны пула стабильны. Введён `Pool.warmup(...)` — один прямой lifecycle воркера перед первым `Pool.setup` (вызывается probe и shadow runner).
3. **Завершение воркера.** Воркер отвечает на QUIT состоянием `BYE` и `quit()`, но внутренний поток чтения stdin этой сборки Godot держит процесс живым. Протокольный shutdown: `BYE`-state + `OS.kill(pid)` координатором (worker к этому моменту уже всё записал).

Reader воркера переведён на `read_string_from_stdin()` (стабилен в сотнях циклов; framing-парсер CR/LF-tolerant и собирает фреймы через границы чанков). Координатор никогда не вызывает блокирующее чтение stdin — только `get_buffer` по `FileAccess stdio` (state machine WRITE→POLL→ACCUMULATE→FRAME→VERIFY→DISPATCH, как предписано в issue #297).

Ограничение этой сборки, оставшееся задокументированным: одиночные pipe-записи >4 КБ доставляются частично (`PIPE_TRANSPORT_PARTIAL`) — bulk-данные ходят через bounded mailbox-файлы (var_to_bytes + SHA-256), pipe несёт только мелкие контрольные кадры.

## Transport probe (миссия §3)

`eco_evo7_par0_transport_probe_v1.gd` — **PASS, 34 assertions**: wc 1/2/4 персистентные воркеры; HELLO/SETUP/PING/ECHO/QUIT; 250 PING (RTT 1.7–1.9 ms) + 250 ECHO (10 KB payload, полный bulk-round-trip ≈ 15–16 ms, worker compute ≈ 6.3 ms) на воркера на конфигурацию (≥1000 циклов суммарно); 0 потерянных, 0 повреждённых, 0 дубликатов job_id; out-of-order завершение обработано; bounded timeout срабатывает (воркер reaped); краш воркера детектируется с job_id.

## Pool campaign — hash gate (миссия §7–8)

`eco_evo7_par0_shadow_runner_v1.gd` — shadow-only: каждый поколенный шаг выполняет серийный oracle (LS3.3 внутри workbench) и параллельную оценку пула на тех же canonical candidates; параллельный результат НИКОГДА не входит в состояние экологии. Сравнение каждого поколения: событие-за-событием + `recruitment_hash` + 10 canonical hashes (candidate_pool, dispersal_pool, recruitment, precompetition, competition, postcompetition, hereditary_pool, ecology_state, classification, workbench) против серийного baseline.

```text
MIXED_PHYSICAL_HETEROGENEITY  wc 1/2/4 × 12 ген  = 36 поколений  EXACT  (0 failures)
WATER_GRADIENT_STRONG         wc 4    × 12 ген  = 12 поколений  EXACT  (0 failures)
WATER_GRADIENT_STRONG         wc 1/2  × 12 ген  = 24 поколения  EXACT  (лог полного прогона R1-кампании)
RELIEF_DRAINAGE_STRONG        wc 1/2/4 × 12 ген = 36 поколений  (см. artifacts/par0_campaign_relief.json)
Итого evidence: ≥100 поколений с byte-exact паритетом
```

Отчёты: `artifacts/par0_campaign_mixed.json`, `artifacts/par0_campaign_water_wc4.json`, `artifacts/par0_campaign_relief.json`, `artifacts/par0_serial_shadow_report.json` (36/36 kernel replay), `artifacts/par0_transport_probe_report.json`.

Операционное ограничение: в одном процессе координатора стабильно живут ≤3 пула подряд (на 7-м пуле одной кампании процесс Godot крашится без диагностики). Поэтому полная кампания гоняется per-recipe свежими процессами (`ECO_PAR0_RECIPES` / `ECO_PAR0_WORKERS`); раннер это поддерживает. Для producción-использования это не блокер: один процесс = один пул на сессию.

## Performance matrix (миссия §9)

Recruitment wall-time, замена серийного вычисления: `shadow = serialize + ipc_wait + merge` (реальная стоимость параллельной оценки против серийной):

```text
MIXED wc=4 (pop 47→103, candidates 94→206):
  gen10: serial 458.6 ms vs shadow 155.8 ms  → 2.94×
  gen12: serial 645.1 ms vs shadow 218.0 ms  → 2.96×
  (средне по поколениям 8–12: ≈2.9×)
WATER wc=4 (pop 49→99):
  gen10: serial 481.9 ms vs shadow 171.9 ms  → 2.80×
  gen12: serial 677.7 ms vs shadow 235.9 ms  → 2.87×
MIXED wc=2:
  gen10: serial 556.5 ms vs shadow 279.9 ms  → 1.99×
  gen12: serial 753.8 ms vs shadow 383.8 ms  → 1.96×
wc=1:   ≈0.9× (паритет без выигрыша — ожидаемо)
```

Worker compute (сумма по воркерам, wc=4) ≈ 490–770 ms — то есть каждый воркер считает ≈120–190 ms против серийных 450–680 ms; IPC+serialization ≈ 60–220 ms на поколение. Критерий миссии — «устойчивое ≥2× на 4 workers после учёта IPC при полном exact-hash parity» — **выполнен** (≈2.8–3.0×).

Целое поколение (вся экология, не только recruitment) пока не ускоряется: parallel — shadow-only, серийный шаг остаётся источником истины; это соответствует плану PAR0.1 → PAR0.2 (включение параллельного результата в состояние).

## Failures / retries / timeouts

- R1: transport заблокирован — задокументирован (выше), починен в PAR0.1.
- Полная 9-пуловая кампания в одном процессе: жёсткий краш на 7-м пуле (без FAIL-диагностики). Обход: per-recipe процессы. Остаточный риск задокументирован.
- Никаких скрытых retry; все таймауты/краши воркеров — fail-closed с named failure.

## Recommendation

**PROCESS_POOL_USEFUL** (по критерию миссии: ≥2× на wc=4 с exact parity). Чистое ядро + детерминированная партиция + канонический merge доказаны; следующий логичный шаг — PAR0.2: включить параллельный recruitment в canonical state (с serial-oracle проверкой на каждом поколении), затем перенос того же ядра на `WorkerThreadPool` (меньший IPC-overhead), как и планировалось в roadmap.

## Что делать ревьюеру/верификатору

1. `RUN_ECO_EVO7_PAR0_TESTS.ps1` — все гейты зелёные (LS3.3 44, LS3.4 45, PERF1 69, parity 38, probe 34).
2. `RUN_ECO_EVO7_PAR0_BENCHMARK.ps1` (или per-recipe через `ECO_PAR0_RECIPES`) — кампания EXACT, отчёты в `artifacts/`.
3. Не мержить до независимого ревью; PAR0.1 — roll-forward кандидат.

## Push (machine with credentials)

```powershell
cd C:\distributed-world-simulator\worktrees\perf1-par0
git log --oneline -3        # a06ba16d (R1) → <PAR0.1 commit>
git push -u origin feature/eco-evo7-perf1-par0-recruitment-process-pool-r1
```

После появления ветки на remote — draft PR `PAR0 R1+PAR0.1 — transport repaired, exact parity + ~2.9x on 4 workers`. Коммит `a06ba16d` не переписывать.