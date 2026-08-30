# ECO.EVO7 PAR3 — Параллельное детерминированное воспроизводство кандидатов (R1)

Статус: R2 ROLL-FORWARD LOCAL CANDIDATE / **BLOCKED_PENDING_PAR2_FORMAL_ACCEPTANCE**.

База: PAR2 candidate `499797653373bf7fa009a99652c2db4a8429ac8c`
(локальный кандидат, сам заблокирован до приёмки PAR1).

Ветка: `feature/eco-evo7-par3-parallel-candidate-reproduction-r1`.

## Аудит потокобезопасности (выполнен ДО распараллеливания)

Цепочка `LineageExtension.reproduce_bundle(...)` и все её зависимости
(`plant_mutation_lineage_kernel_v1`, `plant_genome_v1`,
`plant_development_traits_v1`, `plant_development_traits_extension_evo7_v1`,
`plant_development_contract_v1`) проверены:

- нет Node / SceneTree / рендеринга / физики;
- нет FileAccess / сети / OS-вызовов;
- нет глобального RNG и глобального мутабельного состояния — все броски
  детерминированы keyed-sha256 (`_unit01`/`_seed48`);
- родительский бандл не мутируется (`duplicate(true)` внутри
  reproduce_bundle, ядро не пишет в parent).

Вывод: **аудит чист**. Выбранный в PAR1 бэкенд — PROCESS_POOL (процессы),
дополнительная изоляция ещё и адресным пространством.

## Архитектура

- **Единое чистое ядро**
  `scripts/ecology/perf/eco_evo7_par3_candidate_kernel_v1.gd`:
  mutation seed, вызов `reproduce_bundle`, поля кандидата, candidate_hash —
  формулы перенесены из LS3.3 байт-в-байт. Ядро НЕ реализует мутацию само.
  Серийный LS3.3 `_build_candidates` вызывает ЭТО ЖЕ ядро; параллельный
  исполнитель — тоже. Одна реализация.
- **Шов LS3.3**: `set_candidate_executor` / `clear_candidate_executor` /
  `has_candidate_executor` (по умолчанию — серийно через ядро; любой отказ
  исполнителя = fail-closed, поколение не коммитится).
- **Каноническое разбиение**: родители сортированы по `record_id`, слайсы
  контурные; каждый родитель даёт ровно 2 кандидатов; merge ТОЛЬКО по
  `candidate_hash`, порядок завершения воркеров не важен; координатор
  перепроверяет каждый `candidate_hash` повторным вычислением ядра.
- **Process-путь**: минимальное расширение протокола PAR0-воркера —
  payload с `"phase": "CANDIDATE_BUILD"` (+ schema/version/evolution_seed/
  offspring_per_parent); framing/mailbox/lifecycle переиспользованы,
  второго транспорта нет. Payload без phase = замороженный PAR0-семантика
  (обратная совместимость, унаследованные тесты проходят без изменений).
- **Аудит**: поколение 1 и каждое 10-е — серийный оракул кандидатов;
  требуется равенство candidate_pool_hash И байт-точность записей.
  Расхождение → `PAR3_AUDIT_PARITY_FAILURE`, fail-closed.
- Коды отказов: `PAR3_BACKEND_FAILURE`, `PAR3_AUDIT_PARITY_FAILURE`,
  `PAR3_INPUT_MISMATCH`, `PAR3_RESULT_COUNT_MISMATCH`,
  `PAR3_CANDIDATE_HASH_INVALID`.

## Тесты

`tests/ecology/eco_evo7_par3_parallel_candidate_reproduction_acceptance.gd`:
идентичность ядра (серия == ядро байт-в-байт), end-to-end паритет
3 рецепта × wc 1/2/4 × 12 поколений (≥108 сравнений всех канонических
хэшей), длинная кампания (расписание аудитов, элиминация ≥80%), инъекции
отказов (бэкенд / порча параллельного результата / рассинхрон аудита),
перф-гейт (фикстуры 64–2048 родителей; ≥20% ускорение при ≥1024; полное
поколение не хуже 5%).

`RUN_ECO_EVO7_PAR3_TESTS.ps1` — транзитивная регрессия (PAR0.2 → PAR1 →
PAR2 → PAR3 → VIS3 → PLAY0). `RUN_ECO_EVO7_PAR3_PLAY0.ps1` — ≥5 минут
графической эволюции с ОБОИМИ параллельными путями.

## Результаты (2026-08-30, i9-13900H, 20 LP, Godot 4.7.1.stable.double.custom_build.a13da4feb)

- приёмка: **PASS, 93 assertions**;
- точных end-to-end сравнений: **108/108** (все канонические хэши);
- длинная кампания: 50 поколений, 6 аудитов (ровно по расписанию),
  элиминация оракула кандидатов **88.0%**;
- ускорение построения кандидатов (wc=8): 64→2.45x, 256→3.34x, 512→3.68x,
  1024→**3.79x**, 2048→**4.07x** (гейт ≥20% при ≥1024 выполнен с запасом);
- полное поколение (2048 родителей, не-аудит): параллельно **8.92 s**
  против серийно 11.50 s — на 22% БЫСТРЕЕ (гейт «не хуже 5%» выполнен);
- инъекции отказов: fail-closed, именованные коды, поколение не
  коммитится;
- PLAY0 combined (≥5 мин): см. артефакт прогона.

Артефакты: `artifacts/par3_candidate_perf.json`, `artifacts/par3_acceptance.log`,
`artifacts/par3_play0_console.log` (локально в worktree).


## R2 repair

External review findings closed in this roll-forward:

- empty process-worker slices are explicitly valid; 1..7 parents with wc=8 are covered by focused byte-exact tests;
- LS3.4 and Rule Workbench expose public candidate-executor facades;
- combined PLAY0 test composes both PAR2 recruitment and PAR3 candidate executors only through Workbench public APIs;
- dead LS3.3 candidate reproduction/mutation-seed helpers are removed;
- LS3.3 evidence validation calls `Par3CandidateKernel.candidate_hash(...)`, so candidate construction + identity validation have one implementation.

PAR3 R2 must be verified only after PAR2 R2 becomes accepted.


## R2 exact-Windows rejection and R3 repair

Fresh exact-Windows verification of R2 (`735b3fd40cf18337fa33f51c79578dd5c03aab42`) found two reproducible integration defects while the PAR3 focused kernel gate itself remained green:

1. inherited LS3.3 acceptance still reflected the pre-PAR3 private `_mutation_seed` location and hung after an invalid reflective call;
2. the 5-minute PLAY0 combined test sampled telemetry at the wall-clock cutoff while generation N+1 could be in flight, allowing candidate telemetry to be one phase ahead of the last published generation. The audit predicate also treated generation 0 as divisible by the interval.

R3 repairs the integration boundary without changing candidate biology:
- LS3.3 acceptance imports the single PAR3 candidate kernel and tests mutation-seed invariance there;
- source guards follow the moved mutation/candidate-hash ownership into the kernel;
- PAR3 audit schedule explicitly rejects generation <= 0;
- combined PLAY0 first disables AUTO and waits until `is_generation_running()==false`, then evaluates exact audit counts against the fully published generation;
- focused acceptance freezes generation-zero and gen1/gen10 schedule semantics.

R2 remains immutable rejected evidence. R3 requires a fresh exact-Windows full regression and combined PLAY0 verification before acceptance.
