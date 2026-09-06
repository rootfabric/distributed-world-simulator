# PROJECT-FOCUS — Repair Map / generation regression R1

Дата: 2026-09-05. Продолжение PROJECT-FOCUS-CONTROL-VALIDATION-R1, PR #547.

## Воспроизведение

Subject: `abf05ac905808d23e2aaf8e8e11943ddce49e282`.
Tree: `3e2990bc19003110118fcbc36d931def276f4d27`.
GitHub Actions run: `33956681972`; job: `101281163108`.

Checkout exactness подтверждена равенством EXPECTED_HEAD и ACTUAL_HEAD.
Fetch всех origin branch refs исполнен на GitHub-hosted Ubuntu runner.

Generation-80 + directional-clearance regression: 19 tests, 1 failure, exit 1.
Failure: `test_historical_p4_prebuild_subject_remains_auditable_after_current_v0_moves_post_p6`,
строка 305: ожидается `current_v0["branch"].startswith("control/v0-p7-")`,
фактическое значение — `control/project-focus-harness-reconciliation-r1`.

Предшествующие suite summaries в этом run: project_overview 7/0,
checkpoint_session 22/0, architecture/ownership 65/0, H0.2 8/0,
V0 product 24/0. Эти результаты относятся только к указанному subject.
Standard и directional PC0 в этом run пропущены после failure; результатов нет.

## Причина и владелец

Классификация: CONTROL_REGRESSION_EXPECTATION_DRIFT, не runtime product defect.
Owner: существующий regression `tests/harness/test_v0_generation80_safety_guards.py`.
Причина: синтаксис имени текущей control-ветки использован как семантический
инвариант исторической проверяемости P4. Project-focus закономерно меняет имя
текущего control frontier, сохраняя P4/P7 provenance и запрещая runtime dispatch.

## Минимальное исправление

Заменить только устаревшее ожидание branch prefix проверками действующего
COMPOSITION_FRONTIER, closure phase, historical_only для prebuild snapshot,
отключённой P7.7 runtime authorization и scheduler runtime hold.

Сохранить assertions точной P4 baseline ancestry, P7 historical head/branch,
runtime_mutation_present как исторического факта и несовпадения current/P4 веток.
Не менять registry или scheduler ради теста. Не переписывать historical evidence.
Все negative provenance/lease tests сохраняются.

## Повторная проверка

На новом опубликованном subject повторить полный существующий Project Control
workflow, включая ранее не достигнутые standard/directional auditors.
Проверить diff: только этот regression и новый Repair Map.
После каждого изменения subject требуются fresh exact-head Reviewer/Verifier.
Этот документ не заявляет результата проверки исправления или acceptance.
