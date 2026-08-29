# ECO.EVO7 PAR3 — Параллельное детерминированное воспроизводство кандидатов (R1)

Статус: LOCAL CANDIDATE / **BLOCKED_PENDING_PAR2_FORMAL_ACCEPTANCE**.

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
