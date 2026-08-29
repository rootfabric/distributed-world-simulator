# ECO.EVO7 PERF1-PAR0.2 — canonical parallel recruitment activation (dual-mode R1)

## Статус

```text
PAR0.1            ✅ ACCEPTED predecessor (e4b32070, tree f399b9f4…)
  ↓
PAR0.2 R1         🟡 LOCAL CANDIDATE (эта ветка, НЕ acceptance)
  dual executor   ✅ serial oracle + PAR0 pool на одних immutable inputs
  authority flip  ✅ canonical_source = PARALLEL_VERIFIED в LS3.3
  fail-closed     ✅ mismatch/stale/generation/input_hash/duplicate/context
  campaign        ✅ 108 поколений, 1080/1080 exact hash comparisons
  speedup gate    ❌ ОТСУТСТВУЕТ — PAR0.2 IS NOT A SPEEDUP GATE
```

## Смысл checkpoint

PAR0.2 не оптимизирует recruitment и не меняет биологию. Он доказывает смену
execution authority: результат persistent process pool после EXACT-проверки
против serial oracle становится тем результатом, который LS3.3 реально
коммитит в состояние. Serial остаётся oracle, но перестаёт быть canonical
source в dual-mode.

```text
same candidates + routes + context
        │
  ┌─────┴─────┐
  ▼           ▼
serial       process pool
kernel       parallel
  │           │
  └─────┬─────┘
        ▼
   EXACT COMPARE
        │
   equal│mismatch
        ▼        ▼
PARALLEL_VERIFIED   FAIL-CLOSED
→ LS3.3 state       evidence dump, no commit
```

## Base

```text
PAR0.1 HEAD   = e4b32070c0f3325945fb5a8b0abc728ef61fb7b1
PAR0.1 tree   = f399b9f420486932498cffff07b8e013a9657153
parent        = a06ba16df298aa18b5388ee5dca4e1caaa56aa2f
PERF1         = 8c43e512b78755799b21536f6116accea71fc925 (accepted ancestor)
branch        = feature/eco-evo7-perf1-par02-canonical-parallel-recruitment-r1
worktree      = C:\distributed-world-simulator\worktrees\perf1-par0
```

## Файлы PAR0.2

```text
scripts/ecology/shadow/eco_evo7_ls33_dispersal_recruitment_v1.gd
    инъекция executor'а (set/clear/has_recruitment_executor); dual-ветка в
    _evaluate_recruitment (fail-closed через пустой результат -> step_generation
    не коммитит); телеметрия recruitment_mode/dual_executor_calls/canonical_source
    ТОЛЬКО в non-canonical last_profile; serial path и снапшот не тронуты.
scripts/ecology/perf/eco_evo7_par02_dual_recruitment_executor_v1.gd
    новый компонент: serial oracle replay, один persistent pool на процесс
    (lazy Pool.warmup + Pool.setup ровно один раз), порядок submit → serial
    concurrently → collect → validate → canonical merge → EXACT compare;
    fail-closed коды: PAR02_RECRUITMENT_PARITY_FAILURE, STALE_WORKER_RESULT,
    GENERATION_MISMATCH, INPUT_HASH_MISMATCH, DUPLICATE_WORKER_RESULT,
    MISSING_WORKER_RESULT, CONTEXT_MISMATCH, POOL_FAILURE, INPUTS_INVALID;
    evidence dumps в artifacts/par02/evidence/; test-only fault injection
    (ALTER_PARALLEL_EVENT, INJECT_STALE_RESPONSE, INJECT_WRONG_GENERATION,
    INJECT_WRONG_INPUT_HASH, INJECT_DUPLICATE_RESPONSE); timings
    serial_oracle/serialize/ipc/merge/compare/dual_total (не являются gate).
scripts/ecology/perf/eco_evo7_par02_dual_campaign_runner_v1.gd
    одна комбинация на процесс: ECO_PAR02_MODE=serial|dual; dual сравнивает
    10 canonical hashes поколение-за-поколением против serial baseline
    артефакта; пишет артефакт run'а (rows, external_parity, pool counters).
scripts/ecology/perf/eco_evo7_par02_campaign_matrix_v1.gd
    агрегатор: 3 рецепта × wc {1,2,4} × 12 поколений; парит EXIT!=0 при любом
    несоответствии; пишет par02_hash_matrix.json + par02_summary.json.
tests/ecology/eco_evo7_par02_dual_recruitment_acceptance.gd
    focused acceptance, 62 assertion (см. ниже).
RUN_ECO_EVO7_PAR02_TESTS.ps1 / .sh
    inherited gates (без активации PAR0.2) → PAR0 gates → focused acceptance.
RUN_ECO_EVO7_PAR02_CAMPAIGN.ps1 / .sh
    fresh process на каждый run: 3 serial baseline + 9 dual (по одному
    persistent pool на процесс) → матрица.
docs/checkpoints/PERF1_PAR02_RU.md (этот документ)
```

Заморожено и не изменено: формула recruitment, семантика kernel, воспроизведение
кандидатов, мутация, дисперсия, environment lookup, establishment gate,
competition, classification, canonical hash formulas, PAR0 transport framing,
worker protocol, partition algorithm, canonical merge ordering,
`eco_evo7_par0_recruitment_kernel_v1.gd`.

## Гейты локальной валидации

### Serial-default isolation (без активации PAR0.2, свежие процессы)

| Gate | Result |
| ---- | ------ |
| LS3.3 Dispersal Recruitment | 44/44 PASS |
| LS3.4 Local Competition | 45/45 PASS |
| PERF1 Generation Profiler | 69/69 PASS |
| VIS3 Planet Patch / Biome Viewer | 107/107 PASS |

Дополнительно в focused acceptance: без инъекции `recruitment_mode == SERIAL`,
`dual_executor_calls == 0`, executor setup сам по себе не спавнит pool
(lazy lifecycle).

### PAR0 gates (наследование PAR0.1)

| Gate | Result |
| ---- | ------ |
| PAR0 Recruitment Parity | PASS (38 assertions) |
| PAR0 Transport Probe | PASS (35 assertions) |

### PAR0.2 focused acceptance — PASS (62 assertions)

Покрытие: serial default без pool; инъекция executor; одни immutable inputs
в serial + parallel; EXACT compare; verified parallel result становится
canonical source LS3.3 (`canonical_source == PARALLEL_VERIFIED` в отчёте
executor'а и в профиле LS3.3); external baseline parity 3 поколения × 10
hashes = 30/30 exact; mismatch fail-closed (`PAR02_RECRUITMENT_PARITY_FAILURE`,
no commit, population hash не двигается, first mismatch + divergent hashes в
evidence dump); stale job / wrong generation / wrong input hash / duplicate
result — отвергнуты до merge, состояние не двигается; context divergence
отвергнут (`CONTEXT_MISMATCH`); telemetry-ключи отсутствуют в ecology
snapshot; `pool_setup_count == 1`, `pool_shutdown_count == 1`, второй
shutdown — no-op; fixtures `par02_mismatch_fixture.json` +
`par02_stale_response_fixture.json` записаны.

## Campaign — 108 поколений

```text
3 рецепта (MIXED_PHYSICAL_HETEROGENEITY, WATER_GRADIENT_STRONG,
RELIEF_DRAINAGE_STRONG) × wc {1,2,4} × 12 поколений = 108 generation
comparisons; каждый dual run — свежий процесс координатора, один persistent
pool (warmup/setup/shutdown ровно по разу), 12 поколений через один пул.

Результат (par02_summary.json, base_sha = e4b32070c0f3325945fb5a8b0abc728ef61fb7b1):
  generation comparisons : 108/108
  hash comparisons       : 1080/1080 EXACT (0 failures)
  каждый dual run        : pool_setup=1, pool_shutdown=1, generation_jobs=12,
                           canonical_source=PARALLEL_VERIFIED,
                           external parity 12/12 поколений
10 canonical hashes: candidate_pool, dispersal_pool, recruitment,
precompetition, competition, postcompetition, hereditary_pool,
ecology_state, classification, workbench — byte-for-byte против serial
baseline каждого рецепта.
```

## Производительность

```text
PAR0.2 IS NOT A SPEEDUP GATE
```

Timings собираются (serial_oracle_ms, serialize_ms, ipc_ms, merge_ms,
compare_ms, dual_total_ms — в отчёте executor'а и артефактах run'ов), FAIL за
«dual медленнее serial» запрещён. Ожидаемо dual wall time ≈ max(serial,
parallel) + IPC + compare; speedup снова станет gate в PAR1 (parallel-only,
serial oracle как периодический safety check).

## Границы

- Dual-mode включается ТОЛЬКО явной инъекцией executor'а в LS3.3; env-флагов
  внутри domain layer нет. Inherited tests никогда не создают pool.
- `canonical_source` — только телеметрия: в canonical ecology snapshot/hashes
  не входит (проверено acceptance-фазой телеметрии).
- В dual proof-mode никакого fallback на serial: любое расхождение/нарушение
  протокола = named failure + evidence dump + no generation commit.
- Untracked Godot `.uid` файлы перечислены отдельно по принятому правилу.

## Вердикт

```text
PAR0.2 LOCAL CANDIDATE READY
```

Это НЕ `PAR0.2 ACCEPTED` — требуется remote review по стандартной процедуре
harness. Следующий checkpoint после приёмки: PAR1 (process pool VS
WorkerThreadPool, performance objective, parallel-only execution).
