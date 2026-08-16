# ECO VIS2.1 — CONTROL vs TREATMENT — integration checkpoint R2

Дата: 2026-08-16

Статус: **IMPLEMENTED_CANDIDATE**

Не merge. Не self-accept. Независимый review, полный exact-engine gate на полном checkout и Windows graphical confirmation остаются обязательными.

## 1. Точные входы

Validated common base:

`94c46c9d4475a0d0671690c1e75b4d9334983c81`

CONTROL authoritative input:

`529e61863d99ab5ca17aad11201cc54a5ce28e69`

TREATMENT R1 authoritative input:

`f5b22d2250a13cb0eaa640e991ca989d3b9301e3`

COMPARATOR R1 authoritative input:

`59c2537509ca4cf0a5ec7f4fc20bcdcb8fce30d1`

Integration branch:

`feature/eco-vis2-1-control-vs-treatment`

R2 previous HEAD:

`4a55d8496b2982ed3323b0a5b751219723e3567b`

R2 code-under-test commit:

`c16f439b319a524f27ea33ca308c5b8c40c7eeb3` — `fix(eco): bound VIS2.1 paired integration`

Worker commits не переимпортировались. Causal semantics, common-root derivation и Comparator implementation не перерабатывались.

## 2. Сохранённые causal invariants

Common CRN root по-прежнему выводится только CONTROL через:

`ControlRunner.derive_common_random_seed_hash(fork_generation, common_fork_generation_map)`

с canonical fork hash:

`TraceContract.compute_field_hash(fork_generation, common_fork_generation_map)`

Treatment получает этот же root явно. Branch id, experiment id, intensity и VIS2.0 snapshot hash не salt-ят RNG.

На fork generation N:

- CONTROL map == immutable common fork map;
- TREATMENT map == immutable common fork map;
- Treatment environment == BASELINE;
- canonical field hashes равны;
- environment revisions равны;
- numeric Comparator deltas равны 0.

Treatment forcing начинается только с N+1.

## 3. R2 bounded branch caches

Добавлена интеграционная политика:

`VIS21_BRANCH_CACHE_WINDOW := 64`

После успешного forward simulation до G рассчитывается:

`floor = max(fork_generation, G - VIS21_BRANCH_CACHE_WINDOW + 1)`

и оба runner-а pruning-уются до rolling window.

CONTROL получил минимальный bounded API:

- `prune_before(min_generation)`;
- `cached_generation_count()`;
- `oldest_cached_generation()`;
- `cached_trace_point_count()`.

TREATMENT получил эквивалентный API плюс:

- `is_generation_cached(generation)` — read-only cache probe;
- `rewind_to_cached_generation(generation)` — bounded rewind без replay от fork.

Immutable `_fork_generation_map`, `_fork_history` и common CRN root pruning не изменяет. `generation_map(fork_generation)` возвращает отдельно сохранённый immutable fork map даже после физического eviction fork из rolling `_generation_cache`. `restart_from_fork()` заново строит runtime cache от этого immutable fork state.

Пример для fork G20 / current G140: rolling cache содержит примерно G77..G140, то есть 64 generation maps, но G20 всё ещё доступен для causal fork identity и restart.

## 4. Rewind и Treatment rebranch

Visible Left rewind clamp-ится к:

`oldest_paired_rewind_generation = max(control_oldest_cached_generation, treatment_oldest_cached_generation)`

и не запускает replay от original fork.

Если Treatment меняется после rewind внутри rolling window:

1. `TreatmentRunner.rewind_to_cached_generation(visible_generation)`;
2. Treatment future после visible generation удаляется;
3. `set_experiment(...)` ставит intervention effective at visible generation + 1;
4. CONTROL не rewind-ится и его уже рассчитанный baseline future может быть переиспользован;
5. CRN root остаётся неизменным.

Это устраняет прежний O(total-history) путь restart-from-fork + replay до текущей rewind position.

## 5. Bounded canonical comparison

Raw worker traces по-прежнему не передаются Comparator. Для обеих сторон canonical points строятся через единый `eco_vis2_1_trace_adapter.gd`, field hash — только через `TraceContract.compute_field_hash()`.

R2 comparison rebuild больше не итерирует `fork_generation .. simulated_generation`.

Input всегда состоит из:

- immutable canonical fork point;
- до 63 последних post-fork paired points, доступных в rolling cache.

Поэтому `comparison_rebuild_input_count <= 64` и rebuild имеет O(64) shape независимо от полной длины эксперимента.

Например G140 / fork G20:

- G20;
- G78..G140;
- всего 64 points.

Fork point сохраняется навсегда в canonical comparison input, поэтому Comparator продолжает при каждом rebuild проверять fork field-hash identity, environment-revision identity и нулевые causal deltas даже после eviction fork из runner caches.

## 6. TreatmentRunner lifecycle / rendering

`TreatmentRunner` остаётся data-only Node, но теперь является child VIS2.1 lab scene с диагностическим именем:

`VIS21TreatmentDataRunner`

У него нет visual children, PH5 tree или второго ecology world. При `queue_free()` lab scene runner освобождается вместе с ней.

CONTROL остаётся `RefCounted` data-only runner.

Post-fork rendering architecture остаётся:

- CONTROL — data-only;
- TREATMENT — единственный visible realtime population;
- progressive VIS1.9 PH5 в paired mode отключён/очищается;
- whole-field PH5 turnover rebuild == 0;
- comparison panel == `MOUSE_FILTER_IGNORE`.

## 7. R2 spectator regression

Integrated test больше не использует текстовый fallback для mouse-look.

Проверяется routed input:

1. `_set_mouse_capture(true)`;
2. `InputEventMouseMotion` с координатой внутри comparison panel и non-zero `relative`;
3. `get_root().push_input(motion)`;
4. после frame camera rotation обязана измениться;
5. `_set_mouse_capture(false)`;
6. второй routed MouseMotion не должен менять camera rotation.

Это одновременно проверяет real captured spectator mouse и mouse transparency comparison panel.

## 8. Hardened RUN_ECO_VIS2_1_TESTS.ps1

Gate переписан по isolated VIS2.0 pattern.

Для каждого Godot process используется `System.Diagnostics.ProcessStartInfo`:

- `UseShellExecute = false`;
- `RedirectStandardOutput = true`;
- `RedirectStandardError = true`;
- `ReadToEndAsync()` для обоих streams;
- timeout 240 s для обычных regressions;
- timeout 300 s для integrated long smoke;
- process Kill при timeout.

Gate rejects:

- non-zero exit code;
- zero-exit output с `^SCRIPT ERROR:`;
- zero-exit output с `^ERROR:`;
- `Parse Error`;
- отсутствие ожидаемого PASS marker.

Перед runtime regressions запускается `--check-only` parser preflight integrated preload graph.

Gate создаёт temporary isolated Godot project, копирует только требуемый VIS/ecology dependency graph, worker/integration scripts, scenes и tests и удаляет temp project в `finally`.

Ожидаемые PASS markers проверяются отдельно для:

1. CONTROL runner;
2. TREATMENT R1 runner;
3. Comparator R1;
4. VIS1.8B;
5. VIS1.9;
6. VIS2.0;
7. VIS2.1 integrated.

## 9. Integrated assertions / long smoke

R2 integrated test содержит **56 `_check` assertions**. Предыдущие 33 causal/presentation semantics сохранены и добавлены реальные проверки:

- runner cache counts;
- runner trace-cache counts;
- physical rolling eviction;
- oldest paired rewind generation;
- bounded comparison input;
- permanent fork point retention;
- actual routed captured mouse;
- released-mouse stability;
- TreatmentRunner SceneTree lifecycle;
- cached Treatment rewind/rebranch без replay от fork;
- CONTROL future reuse;
- restart after eviction;
- deterministic G20..G32 replay after eviction;
- G140 and G220 boundedness/performance shape.

Long smoke теперь идёт fork G20 -> G140 и далее G220, поэтому rolling eviction гарантированно должен произойти.

На G140/G220 test требует branch generation caches <=64, raw runner trace caches <=64, oldest cached generation > fork, comparison input <=64, canonical fork G20 присутствует, latest generation присутствует, same CRN root сохраняется, CONTROL остаётся data-only, visible population field один, whole-field PH5 rebuild == 0, biomass contracts валидны, SceneTree growth ограничен.

## 10. Exact engine и фактически выполненная validation в agent environment

Фактически запущенный engine:

`Godot 4.7.1.stable.double.custom_build.a13da4feb`

В текущем agent environment выполнено:

- exact-Godot `--check-only` integrated R2 script/preload surface на локальном API-compatible stub graph — PASS, exit 0;
- exact-Godot `--check-only` изменённого CONTROL regression script на stub graph — PASS, exit 0;
- exact-Godot `--check-only` изменённого TREATMENT regression script на stub graph — PASS, exit 0;
- отдельный exact-Godot synthetic bounded-API runtime smoke на реальных R2 CONTROL/TREATMENT runner scripts с simulation/environment stubs — PASS: G20->G140, pruning до 64 maps (G77..G140), cached Treatment rewind, future eviction, CRN stability, rebranch, restart from fork и replay G32.

Synthetic/stubbed runs подтверждают parser/API/bounded-cache mechanics, но **не считаются полноценными ecology regression PASS**.

## 11. Неисполненные official runtime gates в текущей среде

Полного repository checkout по-прежнему нет. Runtime не может разрешить `github.com` для обычного clone/raw download; GitHub App предоставляет repository object API, но не монтирует полный checkout в execution filesystem. Локального PowerShell/pwsh также нет.

Поэтому здесь не заявляются PASS и фактически не были выполнены на полном real ecology graph:

- CONTROL runner official regression — NOT EXECUTED;
- TREATMENT R1 official regression — NOT EXECUTED;
- Comparator R1 official regression — NOT EXECUTED;
- VIS1.8B regression — NOT EXECUTED;
- VIS1.9 regression — NOT EXECUTED;
- VIS2.0 regression — NOT EXECUTED;
- VIS2.1 integrated 56-assertion real-graph runtime — NOT EXECUTED;
- real-graph long smoke G20..G220 — NOT EXECUTED;
- Windows graphical confirmation — PENDING.

`RUN_ECO_VIS2_1_TESTS.ps1` подготовлен именно для запуска этих gates на Windows exact worktree и не принимает exit code без PASS marker/error scan.

## 12. R2 changed files

R2 code commit изменяет только разрешённые 7 code/test/gate files:

- `RUN_ECO_VIS2_1_TESTS.ps1`;
- `scripts/labs/ecology/eco_vis2_1_control_branch_runner.gd`;
- `scripts/labs/ecology/eco_vis2_1_treatment_branch_runner.gd`;
- `scripts/labs/ecology/eco_vis2_1_control_vs_treatment_lab.gd`;
- `tests/research/ecology/test_eco_vis2_1_control_branch_runner.gd`;
- `tests/research/ecology/test_eco_vis2_1_treatment_branch_runner.gd`;
- `tests/research/ecology/test_eco_vis2_1_control_vs_treatment_lab.gd`.

Этот checkpoint document является восьмым разрешённым R2 file.

Comparator files и VIS2.0/earlier validated files R2 не изменяет.

## 13. Итог

**IMPLEMENTED_CANDIDATE**

R2 устраняет известные integration-quality defects boundedness, O(total-history) comparison rebuilding, weak cache assertions, weak process gating, mouse regression и Treatment Node lifecycle, не меняя causal contract.

Следующий обязательный шаг: полный `RUN_ECO_VIS2_1_TESTS.ps1` на exact Windows worktree, затем независимый review и graphical confirmation. До этого VIS2.1 не считается accepted.
