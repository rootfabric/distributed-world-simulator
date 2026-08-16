# ECO VIS2.1 — CONTROL vs TREATMENT — интеграционный checkpoint

Дата: 2026-08-16

Статус: **IMPLEMENTED_CANDIDATE**

Независимая проверка и Windows graphical confirmation ещё обязательны. Этот checkpoint не является self-accept и не означает глобальное принятие VIS2.1.

## 1. Точные входы

Validated VIS2.0 base:

`94c46c9d4475a0d0671690c1e75b4d9334983c81`

CONTROL:

- branch: `feature/eco-vis2-1-control-branch`
- exact HEAD: `529e61863d99ab5ca17aad11201cc54a5ce28e69`
- source commits: `b524b6759203ac8a0cbe886fbcf894eb7a57a4b7`, `529e61863d99ab5ca17aad11201cc54a5ce28e69`

TREATMENT R1:

- branch: `feature/eco-vis2-1-treatment-branch`
- exact HEAD: `f5b22d2250a13cb0eaa640e991ca989d3b9301e3`
- source commits: `5ea9dd5ff083cd8f150e0b7a41284d172fd1ad10`, `f5b22d2250a13cb0eaa640e991ca989d3b9301e3`

COMPARATOR R1:

- branch: `feature/eco-vis2-1-comparator`
- exact HEAD: `59c2537509ca4cf0a5ec7f4fc20bcdcb8fce30d1`
- source commits: `40b29f83e2bf9a910504980ef343eec55424f055`, `59c2537509ca4cf0a5ec7f4fc20bcdcb8fce30d1`

Integration branch:

`feature/eco-vis2-1-control-vs-treatment`

Validated implementation/code-under-test HEAD before this documentation-only checkpoint commit:

`0a0c95d780724a70c5dc18508191577a966abb69`

## 2. Source-of-truth / topology

До интеграции через GitHub App проверено:

- все четыре заданных exact SHA существуют;
- remote refs всех трёх worker branches указывают на заявленные exact HEAD;
- каждый worker HEAD находится ровно на 2 commits ahead / 0 behind базы;
- merge-base каждого worker HEAD — точно `94c46c9d4475a0d0671690c1e75b4d9334983c81`;
- worker ownership соответствует заданию;
- пересечений worker-owned файлов нет.

После интеграции implementation HEAD `0a0c95d...` остаётся `ahead` от той же exact base, `behind_by=0`, merge-base не изменён.

## 3. Импорт worker commits

CONTROL сохранён в ancestry без переписывания:

- `b524b6759203ac8a0cbe886fbcf894eb7a57a4b7`
- `529e61863d99ab5ca17aad11201cc54a5ce28e69`

Из-за отсутствия обычного Git checkout в текущем runtime TREATMENT и COMPARATOR перенесены через GitHub Git-object API как отдельные эквивалентные commits с сохранёнными исходными blob-ами и `cherry picked from` provenance:

- source `5ea9dd5ff083cd8f150e0b7a41284d172fd1ad10` -> integration `b705feb30b0de7d64b5541a30dbefaf4a1ddd471`;
- source `f5b22d2250a13cb0eaa640e991ca989d3b9301e3` -> integration `0512dc2c1422680ac2c2f4abbba2d98174a4b36e`;
- source `40b29f83e2bf9a910504980ef343eec55424f055` -> integration `157a4f4bd17332d9a92bf416bca3c7b9020272c5`;
- source `59c2537509ca4cf0a5ec7f4fc20bcdcb8fce30d1` -> integration `c1241f480b775e16d7857dc52df8f0fa1ad85314`.

Конфликтов при импорте не было. Worker-owned production/test files после импорта интеграционным кодом не изменялись.

## 4. Интеграционные commits

Основная интеграция:

`ce355578ccff37f93312977eec46a6b6b6633ec0` — `feat(eco): integrate VIS2.1 control vs treatment lab`

Integration repair:

`0a0c95d780724a70c5dc18508191577a966abb69` — `fix(eco): harden VIS2.1 paired presentation and causal switch gate`

Repair затрагивает только integration-owned scene/test. Причины:

1. VIS1.9 parent processing при paused paired-mode мог накапливать progressive PH5; добавлен scene-level paired guard, который в paired-mode обнуляет progressive-detail accumulator и очищает progressive detail, не создавая второй ecology world.
2. causal-switch assertion усилен: DROUGHT и FLOOD теперь сравниваются на одном и том же будущем generation после rewind/switch; одновременно проверяется неизменность CONTROL future.

## 5. Common random numbers

Common CRN root вычисляется ровно один раз через CONTROL:

`ControlRunner.derive_common_random_seed_hash(fork_generation, common_fork_generation_map)`

CONTROL derivation использует canonical fork field hash:

`TraceContract.compute_field_hash(fork_generation, common_fork_generation_map)`

и domain `ECO.VIS2.1/COMMON_RANDOM_NUMBERS`.

После `ControlRunner.configure_from_fork(...)` интеграция проверяет, что accessor CONTROL возвращает тот же derived root. TREATMENT получает именно этот root как явный аргумент `configure_from_fork(...)`; после конфигурации обязательно проверяется точное равенство CONTROL/TREATMENT root.

`VIS2.0 snapshot_hash`, branch id, experiment id и intensity не используются для derivation/salting common root.

## 6. Fork semantics

На `F` текущий BASELINE generation N останавливается и один раз снимаются deep copies:

- common generation map;
- common recent history.

На N:

- CONTROL map == common fork map;
- TREATMENT map == common fork map;
- TREATMENT environment остаётся BASELINE;
- canonical field hashes совпадают;
- environment revisions совпадают;
- Comparator deltas равны нулю.

Treatment intervention начинает действовать только с `N+1`.

`R` в paired-mode означает restart from common fork. `Left` ограничен диапазоном уже существующих paired generations. `Right` продвигает пару. `Space` переключает paired play/pause.

Treatment controls в VIS2.1:

- `2` — DROUGHT;
- `3` — FLOOD;
- `4` — NUTRIENT_PULSE;
- `5` — SHADE;
- `-` / `+` — intensity Treatment only;
- `F` — fork текущего BASELINE generation.

До fork родительский VIS2.0 world принудительно остаётся BASELINE; выбор будущего Treatment не изменяет pre-fork environment.

## 7. Canonical trace normalization

Добавлен единый adapter:

`scripts/labs/ecology/eco_vis2_1_trace_adapter.gd`

Он одинаково строит CONTROL и TREATMENT point из generation map и явно переданных branch/experiment/environment identifiers.

Из generation map вычисляются:

- `visual_count`;
- `birth_count`;
- `death_count`;
- `survivor_count`;
- `mean_fitness`;
- `unique_genomes`;
- `alpha_count`;
- `beta_count`;
- `represented_biomass_kg`.

Field hash для обеих сторон вычисляется только:

`TraceContract.compute_field_hash(generation, generation_map)`

и затем вызывается `TraceContract.create_point(...)`.

Raw CONTROL/TREATMENT traces не подаются непосредственно в Comparator. Paired canonical traces строятся начиная с fork generation и только через latest generation, вычисленный обеими ветками.

## 8. Rendering architecture

Архитектура: две симуляционные ветки, один rendered ecology world.

- CONTROL — только data-only runner, PH5/renderer для него не создаётся.
- TREATMENT — единственный visible post-fork branch.
- Existing realtime proxy renderer получает `TreatmentRunner.generation_map(G)`.
- Visible field environment sampling в paired-mode делегируется TreatmentRunner для отображаемого generation.
- Whole-field PH5 turnover rebuild не добавлен.
- Progressive VIS1.9 PH5 в paired-mode очищается/не накапливается через `PairedProgressivePH5Guard`.
- Comparison panel остаётся `MOUSE_FILTER_IGNORE`.

## 9. Автоматический gate, реализованный в candidate

`RUN_ECO_VIS2_1_TESTS.ps1` проверяет exact engine identity и запускает в порядке:

1. CONTROL worker regression;
2. TREATMENT R1 worker regression;
3. COMPARATOR R1 regression;
4. VIS1.8B regression;
5. VIS1.9 regression;
6. VIS2.0 regression;
7. integrated VIS2.1 regression.

Integrated test содержит ровно **33 `_check` assertions**, соответствующих секциям COMMON FORK, CRN, INTERVENTION BOUNDARY, CAUSAL DIVERGENCE, TRACE, PERFORMANCE/PRESENTATION и BOUNDEDNESS. Дополнительно используются setup guards, которые аварийно завершают test при невозможности создать требуемую исходную сцену/ветку.

Long-smoke в этом test: fork `G20`, CONTROL=BASELINE, TREATMENT=DROUGHT 100%, advance through `G80`.

## 10. Exact Godot identity / parser preflight

Локально из предоставленного engine archive реально запущен:

`Godot 4.7.1.stable.double.custom_build.a13da4feb`

Parser-preflight integration-owned GDScript/scene выполнен этим exact engine в минимальном локальном project с API-совместимыми заглушками отсутствующих repository dependencies.

Результат parser-preflight:

- exact Godot identity: PASS;
- `Parse Error`: 0;
- `SCRIPT ERROR`: 0;
- integrated `_check` count: 33;
- same-generation DROUGHT->FLOOD switch assertion присутствует;
- paired progressive-PH5 guard присутствует.

Это **только parser/syntax preflight**, не runtime regression и не замена запуску на полном repository checkout.

## 11. Runtime regression status в текущей среде

Текущий Linux execution environment не содержит checkout `rootfabric/distributed-world-simulator`; обычный `git clone`/`git ls-remote` не может разрешить `github.com`. Подключённый GitHub App даёт object/API read-write access, но archive endpoint через connector не предоставил локальные bytes checkout.

Поэтому в этой среде **не были фактически выполнены** и не помечаются PASS:

- CONTROL worker exact-engine regression — NOT EXECUTED;
- TREATMENT R1 worker exact-engine regression — NOT EXECUTED;
- COMPARATOR R1 exact-engine regression — NOT EXECUTED;
- VIS1.8B regression — NOT EXECUTED;
- VIS1.9 regression — NOT EXECUTED;
- VIS2.0 regression — NOT EXECUTED;
- integrated 33-assertion VIS2.1 runtime gate — NOT EXECUTED;
- full G20->G80 long-smoke — NOT EXECUTED.

Никакие runtime PASS/count/performance цифры для этих запусков не выдумывались.

## 12. Boundedness note

Canonical comparison series ограничена 64 points. Для заданного long-smoke `G20..G80` paired interval содержит 61 generation и укладывается в это окно.

Worker generation caches по реализации сохраняют вычисленные fork-to-current generations; полноценное подтверждение boundedness semantics и отсутствия роста за пределами acceptance horizon должно быть сделано exact-engine runtime gate/independent review. Этот checkpoint не заявляет доказанную unlimited-duration boundedness.

## 13. Windows validation

Validated base `94c46c9d...` является указанным Windows-runtime-validated VIS2.0 checkpoint.

VIS2.1 candidate `0a0c95d...` в этой сессии на Windows не запускался.

Windows graphical confirmation: **PENDING**.

## 14. Changed files

Worker-owned imported files:

- `scripts/labs/ecology/eco_vis2_1_branch_trace_contract.gd`
- `scripts/labs/ecology/eco_vis2_1_control_branch_runner.gd`
- `tests/research/ecology/test_eco_vis2_1_control_branch_runner.gd`
- `scripts/labs/ecology/eco_vis2_1_treatment_branch_runner.gd`
- `tests/research/ecology/test_eco_vis2_1_treatment_branch_runner.gd`
- `scripts/labs/ecology/eco_vis2_1_comparison_model.gd`
- `scripts/labs/ecology/eco_vis2_1_comparison_panel.gd`
- `tests/research/ecology/test_eco_vis2_1_comparison_model.gd`

Integration-owned files:

- `scripts/labs/ecology/eco_vis2_1_trace_adapter.gd`
- `scripts/labs/ecology/eco_vis2_1_control_vs_treatment_lab.gd`
- `scenes/labs/ecology/eco_vis2_1_control_vs_treatment_lab.tscn`
- `tests/research/ecology/test_eco_vis2_1_control_vs_treatment_lab.gd`
- `RUN_ECO_VIS2_1_TESTS.ps1`
- `RUN_ECO_VIS2_1_LAB.ps1`
- `docs/checkpoints/2026-08-16_ECO_VIS2_1_CONTROL_VS_TREATMENT_RU.md`

## 15. Итоговый статус

**IMPLEMENTED_CANDIDATE**

Не merge. Не self-accept. Следующий обязательный шаг — полный exact-engine gate на полном checkout, затем независимый review и Windows graphical confirmation.
