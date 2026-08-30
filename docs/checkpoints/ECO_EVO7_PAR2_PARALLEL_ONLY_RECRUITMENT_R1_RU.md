# ECO.EVO7 PAR2 — Parallel-only рекрутмент с ограниченными аудитами (R1)

Статус: R2 ROLL-FORWARD LOCAL CANDIDATE / **BLOCKED_PENDING_PAR1_FORMAL_ACCEPTANCE**.

База: PAR1 candidate `d70473f0f446488a89b3e83ec9b3b49fe64ce7aa`
(локальный кандидат, внешний ревью.pending).

Ветка: `feature/eco-evo7-par2-parallel-only-recruitment-r1`.

## Цель

Перевести рекрутмент с PAR0.2 dual-режима (серийный оракул + параллельно
каждое поколение — дублирование работы) на канонический PARALLEL-ONLY:

```
вход → ВЫБРАННЫЙ PAR1 БЭКЕНД (PROCESS_POOL) → канонический результат
         ↓ (только поколения-аудиты)
серийный аудит (поколение 1 и каждое 10-е) → точное сравнение
```

Расписание аудитов — только по номеру поколения (никогда по времени):
`audit_generation = generation == 1 or generation % 10 == 0`.

## Изменения

- `scripts/ecology/perf/eco_evo7_par2_canonical_executor... ` — точное имя
  `eco_evo7_par2_canonical_recruitment_executor_v1.gd`: выбранный бэкенд,
  детерминированная политика аудитов, серийный аудит, точное сравнение,
  fail-closed, неканоническая телеметрия. Бэкенд-агностичен по отношению к
  LS3.3 (существующий шов `set_recruitment_executor`).
- Минимальные pass-through (LS3.4 и Workbench):
  `set_recruitment_executor` / `clear_recruitment_executor` /
  `has_recruitment_executor` — без обращения Workbench к внутренностям
  ecology.core.
- Биология, формулы, хэши, сортировки — не изменены. Телеметрия никогда не
  входит в канонические хэши.

## Политика отказов (fail-closed, без серийного фолбэка)

- отказ бэкенда → `PAR2_BACKEND_FAILURE`, поколение не коммитится;
- рассинхрон аудита → `PAR2_AUDIT_PARITY_FAILURE`, поколение не коммитится;
- несовпадение входов → `PAR2_INPUT_MISMATCH`;
- дивергенция контекста → `PAR2_CONTEXT_MISMATCH`;
- несовпадение числа результатов → `PAR2_RESULT_COUNT_MISMATCH`.

## Тесты (`tests/ecology/eco_evo7_par2_parallel_only_recruitment_acceptance.gd`)

1. Серийная совместимость (исполнитель не внедрён) — поведение байт-в-байт
   как принятый серийный путь.
2. Parallel-only: коммиты поколений от выбранного бэкенда.
3. Длинная кампания (до 100 поколений): serial_audit_calls << parallel_calls,
   элиминация оракула ≥80% (цель ≥90%).
4. Точный внешний базовый сравнение: 3 рецепта × wc 1/2/4 × 12 поколений —
   ≥108 сравнений всех канонических хэшей, ноль расхождений.
5–7. Инъекции отказов (бэкенд/аудит/порча параллельного результата) —
   fail-closed, поколение не коммитится, именованные коды ошибок.
Плюс перф-гейт: parallel-only p50 не хуже 5% против прямого замера PAR1.

Регрессия: `RUN_ECO_EVO7_PAR2_TESTS.ps1` (PAR0.2 inherited + PAR1 + PAR2 +
VIS3 + PLAY0).

## Результаты

Прогоны 2026-08-30 (i9-13900H, 20 логических процессоров, Godot
4.7.1.stable.double.custom_build.a13da4feb):

- приёмка: PASS, 92 assertions;
- точных внешних сравнений: **108/108** (3 рецепта × wc 1/2/4 × 12 поколений,
  все канонические хэши, ноль расхождений);
- длинная кампания: 100 поколений, 11 аудитов (расписание 1 + каждое 10-е —
  детерминированно ровно), элиминация оракула **89.0%** (требование ≥80%);
- перф-гейт: parallel-only wc=4 p50 = **247.1 ms** против прямого замера
  PAR1 wc=4 (интерполяция 316.9 ms при тех же объёмах) — регрессии нет,
  выигрыш ~22%;
- инъекции отказов (бэкенд / аудит / порча параллельного результата):
  fail-closed, поколение не коммитится, именованные коды подтверждены;
- PLAY0 live (190 c, PROCESS_POOL wc=4, AUTO): 39-40 поколений,
  FPS mean 159.8, элиминация оракула 87.5%, 4 аудита, stall 0 — PASS;
- полная регрессия RUN_ECO_EVO7_PAR2_TESTS.ps1: 9/9 PASS
  (LS3.3/LS3.4/PERF1/VIS3/PAR0/PAR0.2/PAR1/PAR2/PLAY0).


## R2 repair

External review выявил два блокирующих дефекта performance evidence и один composition gap. R2 исправляет их без изменения биологии:

- performance gate больше не зависит от untracked `artifacts/par1_backend_benchmark.json`;
- PAR1 direct PROCESS_POOL и PAR2 executor измеряются на одном и том же captured `candidates/routes/context` batch (2 warmup + 7 measured);
- исчезла неверная аппроксимация через post-recruitment `record_count * 2`;
- PLAY0 test использует публичный Workbench recruitment-executor facade и больше не проходит через `workbench.ecology.core`.

PAR2 по-прежнему fail-closed и не имеет serial fallback.
