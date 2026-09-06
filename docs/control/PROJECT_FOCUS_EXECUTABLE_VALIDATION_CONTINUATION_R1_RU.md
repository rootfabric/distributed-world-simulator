# PROJECT-FOCUS — executable validation continuation R1

Дата: 2026-09-05. PR: #547. Работа ограничена фазой project-focus control.
Это продолжение проверки, не checkpoint acceptance, не runtime dispatch и не разрешение merge.

## Основание и точный вход

Текущий запрос владельца явно разрешает и требует проверки. Запрет на запуски,
описанный в PROJECT_FOCUS_CHANGE_RU.md, относится к предыдущей подготовительной
сессии; исторический документ сохранён без изменений.

Проверенные через GitHub API refs до этого continuation:

- canonical main: `5b4152958624be4e9cc40f2369ce32c4964f65c3`;
- control subject: `6b80271d9451efff90a9ae58e851f44b5f4f1637`;
- control tree: `72c1996ad23ce19deee7678d7c918906f71f8118`;
- сравнение: ahead 2, behind 0, merge base равен canonical main;
- draft PR #547 открыт из `control/project-focus-harness-reconciliation-r1` в `main`.

## Repair Map: CI_SUPPRESSED_BY_HEAD_SKIP_DIRECTIVE

Классификация: control execution / CI trigger metadata, не product defect.
Владелец: существующий Project Control workflow и GitHub Actions event semantics.
Вход: pull_request opened/synchronize. Потребитель: exact-head control verification.

Наблюдения: GitHub API вернул ноль workflow runs и check suites для указанного
control HEAD. Его сообщение содержит директиву пропуска CI. Workflow уже объявляет
pull_request и workflow_dispatch, поэтому runtime или policy-изменение для этой
причины не требуется.

Официальный контракт:
https://docs.github.com/actions/managing-workflow-runs/skipping-workflow-runs

Canonical fix: добавить этот ограниченный continuation commit без директивы
пропуска; не менять существующие commits, workflow trigger, проверочные пороги,
исторические review/verification или runtime. После публикации проверить создание
workflow run и равенство PROJECT_CONTROL_EXPECTED_HEAD / PROJECT_CONTROL_ACTUAL_HEAD
новому опубликованному HEAD. До результата причина не считается проверенно устранённой.

## Ограниченный Work Order

Идентификатор: `PROJECT-FOCUS-CONTROL-VALIDATION-R1`.
Risk: HIGH. Scope наследует PROJECT_FOCUS_CHANGE_RU.md и паспорт control-ветки.
Разрешены проверка control-кандидата, новые evidence/continuation документы,
минимальные исправления только воспроизведённых control-дефектов и draft PR.

Запрещены runtime/scenes mutations, изменение canonical main, переписывание
historical generation-80 executions, создание runtime lease, самостоятельное
принятие Implementer-ом, merge без отдельного решения человека.

Обязательные результаты:

1. JSON Schema и duplicate-key validation, Harness regressions, project overview
   regressions и обновлённые V0 product-policy regressions на одном exact HEAD.
2. Standard и directional PC0: читать фактические reports; успешный процесс с
   no-fail-on-red сам по себе не доказывает отсутствие blocking findings.
3. Fresh independent Reviewer и Fresh independent Verifier на одном замороженном
   subject. Старое static evidence для 2a502c28 не переносится автоматически.
4. Drive и CloseMission с фактическим результатом либо документированным отказом
   среды до исполнения. Не выдумывать Harness exit code при отсутствии запуска.
5. Только после всех обязательных результатов — отдельный human merge gate #547.

После любого кодового или контрактного repair фиксировать новый exact subject,
повторять затронутые проверки и fresh review. Новые результаты добавлять отдельно,
не редактировать старые evidence. Смена роли не закрывает родительскую mission.

## Ограничения локальной среды

В этой сессии clone и `git fetch --all --prune` завершились с exit 128:
`Could not resolve host: github.com`. Последующие `git rev-parse origin/main` и
`git rev-parse origin/control/project-focus-harness-reconciliation-r1` также
завершились с exit 128: refs не получены. `pwsh` не найден.

Проверка refs через GitHub connector не выдаётся за успешный локальный fetch,
получение exact checkout или запуск тестов. Штатный GitHub Actions runner остаётся
проверяемым альтернативным исполнителем control suites; его результаты должны
быть получены, а не предположены. Godot для этой фазы не требуется.

## Последовательность после control

P7 closure reconciliation начинается после human-approved merge control в main.
P7 runtime #487 не реализуется заново. MVP exact-base activation и отдельный
MVP_SHARED_VISUAL_SCENE Work Order допустимы лишь после canonical P7 acceptance.
ECO/FABRIC/WORLD FILL/WORLD PACKS не получают новых полномочий или роли MVP gate.

На момент записи этот continuation не содержит результатов executable validation,
независимого review/verifier текущего subject или acceptance.
