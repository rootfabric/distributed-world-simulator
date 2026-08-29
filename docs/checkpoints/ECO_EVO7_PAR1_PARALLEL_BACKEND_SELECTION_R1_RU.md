# ECO.EVO7 PAR1 — Выбор production-параллельного бэкенда (R1)

Статус: LOCAL CANDIDATE (не принят; external review pending).

База: `1e512b834a85ec985c270529686c4197f6df8042` (PLAY0.FINAL R2, ACCEPTED).

Ветка: `feature/eco-evo7-par1-parallel-backend-selection-r1`.

## Цель

Сравнить два ЧЕСТНЫХ прямых параллельных бэкенда рекрутмента на одинаковом
контракте и выбрать production-бэкенд для PAR2/PAR3:

- **A. PROCESS_POOL** — постоянный пул OS-процессов (переиспользование
  принятого PAR0 пула/транспорта/протокола, без серийного оракула внутри);
- **B. WORKER_THREAD_POOL** — `WorkerThreadPool.add_group_task()` +
  `wait_for_group_task_completion()`.

Сравнение с PAR0.2 dual-mode НЕ производится (dual содержит серийный
оракул — нечестная база). Ядро расчёта одно: принятый чистый
`eco_evo7_par0_recruitment_kernel_v1.gd`; вторая формулы рекрутмента не
создаётся.

## Файлы

- `scripts/ecology/perf/eco_evo7_par1_recruitment_backend_contract_v1.gd` —
  контракт `evaluate_generation(generation, candidates, routes, context)` →
  `{success, backend, worker_count, canonical_events, canonical_hash,
  failure_code, timings_ms}`; канонизация входа, формула агрегатного хэша,
  серийный эталон, побайтовый компаратор.
- `scripts/ecology/perf/eco_evo7_par1_process_recruitment_backend_v1.gd` —
  прямой процесс-бэкенд (fail-closed: stale/duplicate/missing/generation/
  input_hash/context).
- `scripts/ecology/perf/eco_evo7_par1_worker_thread_recruitment_backend_v1.gd` —
  WTP-бэкенд: results/errors ресайзятся ДО группы, воркер пишет только свой
  индекс, никаких append/resize/erase внутри задач, RefCounted-воркер,
  никаких Node/SceneTree.
- `scripts/ecology/perf/eco_evo7_par1_backend_benchmark_v1.gd` — бенчмарк
  (фикстуры LS3.3 64/256/512/1024/2048 родителей; SERIAL/PROCESS/WTP ×
  wc 1/2/4/8; 2 warmup + 7 замеров; p50/p95/min/max).
- `tests/ecology/eco_evo7_par1_backend_selection_acceptance.gd` — приёмка:
  паритет фикстур (wc 1/2/4/8), кампания 3 рецепта × wc 1/2/4 × 12 поколений
  на каждый бэкенд (>=108 точных сравнений), fail-closed проверки.
- `tests/ecology/eco_evo7_par1_play0_contention.gd` + `RUN_ECO_EVO7_PAR1_CONTENTION.ps1` —
  графическая конкуренция с PLAY0 (>=3 мин AUTO-эволюции, выбранный бэкенд
  через существующий шов LS3.3).
- `RUN_ECO_EVO7_PAR1_TESTS.ps1`, `RUN_ECO_EVO7_PAR1_BENCHMARK.ps1`.
- `config/ecology/eco-evo7-parallel-runtime.v1.json` — машинно-читаемый
  выбор бэкенда (обновляется по факту измерений).

## Политика выбора

Корректность первична: идеальный паритет, ноль падений/таймаутов/stale,
отсутствие обращений к Node/SceneTree из воркеров, доказанный fail-closed.
Далее: геометрическое среднее времени рекрутмента на больших фикстурах
(512/1024/2048); преимущество >=15% побеждает (p95 не хуже 20%); при
разнице <15% — WTP при чистом аудите потокобезопасности и стабильном p95.

## Результаты

Измерено (i9-13900H, 20 логических процессоров, Godot
4.7.1.stable.double.custom_build.a13da4feb; 2 warmup + 7 замеров;
полная матрица в `artifacts/par1_backend_benchmark.json`):

| Родители | Кандидаты | SERIAL p50 | PROCESS wc8 p50 | WTP wc8 p50 |
|---:|---:|---:|---:|---:|
| 64 | 128 | 220.7 ms | 100.5 ms | 83.1 ms |
| 256 | 512 | 955.6 ms | 272.9 ms | 319.3 ms |
| 512 | 1024 | 1935.9 ms | 530.4 ms | 671.0 ms |
| 1024 | 2048 | 3926.5 ms | 973.0 ms | 1355.1 ms |
| 2048 | 4096 | 7638.1 ms | 1731.7 ms | 2668.1 ms |

- SELECTED_BACKEND: **PROCESS_POOL** ( wc=8 );
- причина: на больших фикстурах 512/1024/2048 средний p50 полного времени
  рекрутмента 1078.4 ms против 1564.7 ms у WTP (перевосходство 45.1% ≥ 15%),
  p95 также лучше (1994.9 против 2965.7);
- скорость против серии на 2048 родителей: PROCESS ×4.41, WTP ×2.86;
- точных сравнений: 224 (приёмка: фикстуры wc 1/2/4/8 + кампания 3 рецепта ×
  wc 1/2/4 × 12 поколений × 2 бэкенда + реплеи), ноль расхождений;
  бенчмарк: 40 ячеек, все exact;
- thread-safety аудит WTP-пути и ядра: чисто (нет Node/SceneTree/FileAccess/
  OS/глобального RNG в Par0Kernel и в цепочке мутации);
- contention PLAY0: см. `artifacts/par1_contention_console.log`
  (PASS-критерии внутри `tests/ecology/eco_evo7_par1_play0_contention.gd`).

## Инварианты

Канонический рекрутмент в PAR1 остаётся СЕРИЙНЫМ: бэкенды исполняются в
shadow-стиле (как в принятой PAR0-кампании). Все биологические формулы,
хэши и порядок сортировки не изменены. PAR1 только выбирает бэкенд.
