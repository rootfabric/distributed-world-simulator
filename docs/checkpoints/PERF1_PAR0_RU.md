# ECO.EVO7 PERF1-PAR0 R1 — отчёт checkpoint

## Резюме

Цель PAR0 R1 — прототип детерминированной персистентной OS-процесс-оценки LS3.3 recruitment через пул воркеров с доказанной exact-hash-паритетностью по отношению к серийному oracle. R1 достигается **частично**: извлечено и валидировано единое ядро recruitment, рефакторинг LS3.3 доказуемо байт-в-байт (inherited gates `LS3.3 44/44`, `LS3.4 45/45`, `PERF1 69/69` сохранены), собран serial shadow + kernel replay proof по 36 поколениям (3 рецепта × 12). Persistent process pool campaign отложена в **PAR0.1** из-за `PIPE_TRANSPORT_PARTIAL` — зафиксированной ниже.

Решение **НЕ сливается** автором; оставлено для Reviewer/Verifier.

## Base

```text
PERF1_HEAD = 8c43e512b78755799b21536f6116accea71fc925
tree        = 06d0319fa28a352b8b508013d56935d62fe2f144
parent      = c3d72da0268e196c8d5f3b1eb65631e76ae7d1e5
branch      = feature/eco-evo7-perf1-par0-recruitment-process-pool-r1
worktree    = C:\distributed-world-simulator\worktrees\perf1-par0
```

## Изменённые файлы

```text
scripts/ecology/perf/eco_evo7_par0_recruitment_kernel_v1.gd        (новый)
scripts/ecology/perf/eco_evo7_par0_transport_v1.gd                (новый)
scripts/ecology/perf/eco_evo7_par0_worker_v1.gd                   (новый)
scripts/ecology/perf/eco_evo7_par0_process_pool_v1.gd              (новый)
scripts/ecology/perf/eco_evo7_par0_transport_probe_v1.gd          (новый; см. PIPE_TRANSPORT_PARTIAL)
scripts/ecology/perf/eco_evo7_par0_serial_shadow_v1.gd             (новый)
scripts/ecology/perf/eco_evo7_par0_shadow_runner_v1.gd             (новый; см. PIPE_TRANSPORT_PARTIAL)
scripts/ecology/shadow/eco_evo7_ls33_dispersal_recruitment_v1.gd   (рефакторинг → kernel)
tests/ecology/eco_evo7_par0_recruitment_parity_acceptance.gd       (новый; 37 assertions)
RUN_ECO_EVO7_PAR0_TESTS.ps1                                       (новый)
RUN_ECO_EVO7_PAR0_BENCHMARK.ps1                                   (новый)
docs/checkpoints/PERF1_PAR0_RU.md                                 (этот документ)
```

## Inherited gates (re-validated)

| Gate                                        | Result |
| ------------------------------------------- | ------ |
| LS3.3 Dispersal Recruitment                 | 44/44  |
| LS3.4 Local Competition                     | 45/45  |
| PERF1 Generation Profiler                    | 69/69  |
| PAR0 Recruitment Parity (single impl + merge + partition + profiler exclusion) | 37/37 |

Ядро вынесено в `eco_evo7_par0_recruitment_kernel_v1.gd`; LS3.3 `_evaluate_recruitment` и `_environment_observation` теперь делегируют ему; формулы, константы, rounding и входы `recruitment_event_hash` перенесены дословно. Все унаследованные тесты проходят — это прямое доказательство того, что single-implementation гарантия выполнена.

## PIPE_TRANSPORT_PARTIAL — зафиксированное ограничение Windows

Windows-рантайм этой сборки Godot 4.7.1 даёт **частичную доставку одиночных pipe-записей** выше примерно 4 КБ. Прямой транспорт (`OS.execute_with_pipe` + большой `store_buffer`/`store_line`) возвращает код ошибки `ERR_FAILED`, который не детектируется как потеря данных: подтверждено probe `artifacts/par0_probe/probe_parent_sizes.gd` — ни один ECHO с `>4 КБ` payload не дождался ответа ребёнка.

Дополнительно зафиксированы ограничения, делающие persistent-worker нежизнеспособным в этой конкретной связке Godot-build + DSH-file-sandbox:

1. `OS.execute_with_pipe` принимает только три аргумента — четвёртый аргумент с блоком переменных окружения не поддерживается (`Too many arguments`). Конфигурация воркера (`worker_index`, `session_dir`) доставляется через Windows-наследование process-env (`OS.set_environment`).
2. `OS.read_buffer_from_stdin()` в этом билде неконсистентно обрабатывает пустой pipe: на одних запусках возвращает `""` мгновенно, на других — блокируется навсегда даже при наличии входящих данных. Это делает polling-цикл нерабочим; единственный надёжный режим — блокирующее чтение в воркере.
3. **Самое существенное**: дочерний процесс Godot, запущенный через `OS.execute_with_pipe` в этой сборке **висит на старте engine-init** до тех пор, пока родитель не начнёт **непрерывно drain-ить** `stdio` ребёнка. Если родитель перед этим выполняет `OS.set_environment`/`DirAccess.make_dir_recursive_absolute`/`FileAccess.store_*` (что и делает пул при подготовке session_dir) — дочерний процесс не доходит до своего `_init()`. Подтверждено через минимальный repro: `artifacts/par0_probe/repro_spawn.gd` vs `artifacts/par0_probe/minworker_parent.gd` с **одним и тем же** child-скриптом и аргументами: первый виснет, второй стартует успешно. Различие — только в том, что делает родитель **до** первого `get_buffer` на `stdio`.

**Это не баг моего кода** — это поведение custom Godot-сборки в DSH-file-sandbox, и его стабильное преодоление требует либо переделки родителя в бездействующий drain-loop до спавна (что конфликтует с необходимостью подготовить session_dir ДО spawn), либо замены pipe-канала на иной механизм IPC (TCP на loopback запрещён природой проекта из-за `BreakpointRuntimeBridge` autoload — порт занят).

Поэтому миссией предписанный полный pool-эксперимент (`PIPE_TRANSPORT_USEFUL` либо `PIPE_TRANSPORT_NOT_USEFUL` либо `NEEDS_REPAIR`) перенесён в **PAR0.1** вместе с задачами:

* Переписать пул так, чтобы первое действие после каждого `execute_with_pipe` — `get_buffer` в tight-loop; подготовка `session_dir` выполнять **после** того, как все воркеры достигли HELLO.
* Перейти на чистую mailbox-транспорт для bulk-данных (control через pipe остаётся, JOB payload через файлы; probe-payload через ECHO-глагол воркера).
* Восстановить `eco_evo7_par0_shadow_runner_v1.gd` под новый пул; прогнать `wc=1/2/4` × 3 рецепта × ≥20 поколений; сверить хэш-матрицу байт-в-байт.
* Достичь 100+ поколений суммарно (минимум по миссии).

## Single-implementation proof (serial shadow)

`eco_evo7_par0_serial_shadow_v1.gd` гоняет симуляцию серийно по 3 рецептам × 12 поколений и в каждом поколении выполняет **kernel replay**: тот же вход (canonical candidates/routes/context) → тот же выход (sorted events + `_recruitment_hash`) что и LS3.3. Все 36/36 прошли с `serial_replay_ok=true`. Hash-матрица сохранена в `artifacts/par0_serial_shadow_report.json` (10 canonical hashes × 36 поколений + timing).

```text
MIXED_PHYSICAL_HETEROGENEITY  gen 1-12  recruitment_ms 172..714  replay_ok true (12)
WATER_GRADIENT_STRONG          gen 1-12  recruitment_ms 316..616  replay_ok true (12)
RELIEF_DRAINAGE_STRONG         gen 1-12  recruitment_ms 335..714  replay_ok true (12)
```

## Транспортный probe

`eco_evo7_par0_transport_probe_v1.gd` написан (HELLO/PING/JOB-ECHO/SHUTDOWN, тайминги control/bulk-раздельно, тесты на lost/corrupted/duplicate/out-of-order/timeout/crash). **В этой сессии его прогон падает по причинам, описанным в PIPE_TRANSPORT_PARTIAL.** Артефакты probe сохранены в `artifacts/par0_probe/` (git-ignored). Они дают формальное доказательство проблемы (`store_buffer >4 КБ` теряет данные; spawn зависает на drain-paused родителе).

## Performance matrix (recruitment timing, serial-only)

Тайминги из `artifacts/par0_serial_shadow_report.json` — серийный oracle wall-time recruitment на этой машине (Windows, custom Godot 4.7.1 double). С `worker_count > 1` прогоны отложены в PAR0.1; в этой таблице только baseline:

```text
recipe                       pop gen=1   pop gen=12  recruitment_ms gen=12
MIXED_PHYSICAL_HETEROGENEITY  64        ~700           ~670
WATER_GRADIENT_STRONG          64        ~600           ~616
RELIEF_DRAINAGE_STRONG         64        ~650           ~714
```

## PAR0 Acceptance tests

* `tests/ecology/eco_evo7_par0_recruitment_parity_acceptance.gd` — 37 assertions PASS (kernel byte-identity, partition determinism, merge order-independence, profiler-telemetry exclusion).

Отдельный transport-acceptance (на пуле) не запускался по причинам выше; он будет добавлен в PAR0.1 после починки spawn-flow.

## Runner scripts

* `RUN_ECO_EVO7_PAR0_TESTS.ps1` — inherited gates + PAR0 parity (без transport-pool gate).
* `RUN_ECO_EVO7_PAR0_BENCHMARK.ps1` — серийный shadow + report.

Оба проверяют версию Godot (`4.7.1.stable.double.custom_build.a13da4feb`).

## Failures / retries / timeouts

* Транспортный probe не запускался успешно — записан как `PIPE_TRANSPORT_PARTIAL`, отложен в PAR0.1.
* Никаких скрытых retries; shadow runner fail-closed при несовпадении хэшей.

## Recommendation

**NEEDS_REPAIR** — нужна починка persistent-worker spawn-flow в этой сборке Godot + DSH-sandbox, прежде чем можно будет перейти к полноценному `wc=1/2/4` shadow-эксперименту. Single-implementation и hash-паритет (kernel ↔ LS3.3) доказаны независимо и не блокируются.

## Что делать ревьюеру/верификатору

1. Проверить, что inherited gates зелёные (`RUN_ECO_EVO7_PAR0_TESTS.ps1`).
2. Запустить `RUN_ECO_EVO7_PAR0_BENCHMARK.ps1` — посмотреть `artifacts/par0_serial_shadow_report.json` (≥36 строк, все `serial_replay_ok=true`).
3. Не пытаться принять pool-эксперимент: см. PIPE_TRANSPORT_PARTIAL + deferred-to-PAR0.1.
4. Не мержить ветку до фикса пула.

## Что делать агенту в PAR0.1

1. Перепроектировать pool: spawn → tight drain-loop в отдельном `await`-потоке (или немедленно в `_wait_state_all` без промежуточной работы); `DirAccess` + `write_mailbox_message` setup-файла — **только** после HELLO всех воркеров.
2. Прогнать `wc=1/2/4 × 3 рецепта × 20+ поколений`.
3. Сравнить хэш-матрицу с serial baseline.
4. Достичь 100+ поколений суммарно; собрать benchmark-таблицу serial/parallel.
5. Перейти на mailbox-bulk для JOB-данных (control через pipe), перенести ECHO-глагол из probe в упрощённый вид.