# H0 Channel Recovery — Repair R2: exact source и активная проверка

**Наблюдаемый рубеж этой записи:** `IMPLEMENTED_VALIDATION_IN_PROGRESS`.

Запись не является independent review, CHECKPOINT_ACCEPTED, разрешением merge или завершением product mission. Дальнейшие результаты дописываются отдельной записью с тем же exact subject; эта точка не требует сохранности текущего chat/tool resource.

## Exact subjects

```text
repository = rootfabric/distributed-world-simulator
PR = 607
work_order = H0-CHANNEL-RECOVERY-REPAIR-R2
candidate_branch = control/h0-channel-recovery-r1
candidate_head = 816fe98cb8b47108af4a62947cd5c737b6f42fd2
candidate_tree = 88578cc6d463e2ebdcd70b6033aba755bff24c58
observed_base_main = 127c732a56cc5c25d5712f24a7627ed4bb877374
predecessor_R1 = 910b65787858063659f16ce4650ea03a03393a0e
```

R2 содержит ровно 5 добавленных строк в `scripts/harness/contracts.py` и новый `tests/harness/test_execution_channel_routing_policy.py` (104 строки), без удалений. Git compare `910b6578...` → `816fe98c...` и patch коммита перечитаны после публикации. Прежние legacy/anchor guards, P7 assertions, runtime, workflow и permissions не менялись. Все изменения PR #607 по отношению к base — 9 Harness/control/test/documentation файлов.

## Причина R2

Независимый Codex review `5185189302` на exact `910b6578...` завершился с P2 `3995095825`: строка `execution_channel_recovery.github_source_routing.repository_read_write` не проверялась. Можно было подставить `USE_GITHUB_ACTIONS_AS_GIT_TRANSPORT`, сохранив остальные boolean guards.

R2 требует точного типа `str` и точного значения:

```text
GITHUB_CONNECTOR_OR_NORMAL_GIT_WHEN_NETWORK_AND_AUTH_ARE_PROVEN_AVAILABLE
```

Нарушение, включая отсутствие строки, отклоняется с `CHANNEL_GITHUB_REPOSITORY_ROUTE_INVALID`.

Предыдущие P1 `3994885215` (double omission) и P2 `3994885224` (anchor requirements) не забыты: их R1 implementation и regression tests наследуются неизменными. R1 machine evidence на 322 tests — отдельное историческое доказательство, не приёмка R2.

## Защита от повторения класса дефекта

Новый набор включает три test method:

1. Разрешённая строка, её подмены, отсутствие и неверные типы.
2. Автоматическое перечисление всех объявленных полей и членов списков `execution_channel_recovery`, поочерёдное удаление каждого и требование `ContractValidationError`. Это обнаруживает объявленное, но не проверяемое обязательное правило; добавление нового требования без guard должно сделать regression красной.
3. Настоящие `Drive` и `CloseMission` на локальном fixture с committed запрещённым маршрутом. Ожидаются exit 3 и конкретный contract error, а не полномочия на запрещённую операцию.

Тестовый clone использует существующий локальный CI checkout, не сеть контейнера и не GitHub transport workaround. Само наличие tests не выдаётся за их окончательный PASS.

## Действительно запущенные проверки

```text
workflow = Project Control
run_id = 34673302661
job_id = 103498610041
subject_head = 816fe98cb8b47108af4a62947cd5c737b6f42fd2
last_observed_state = IN_PROGRESS
full_harness_conclusion = NOT_YET_OBSERVED
```

На момент записи шаги exact checkout, syntax/generation, product coordination, project overview, checkpoint-session, architecture/ownership, H0.2, V0/P7 и generation-80 safety завершены SUCCESS. Full Harness discovery ещё выполнялась; последующий итог этой записью не предсказывается. Отсутствие артефакта у ещё работающего run не является product failure.

Fresh independent review request: PR comment `5643474514`. Бот `chatgpt-codex-connector[bot]` (id `199175422`) подтвердил запрос реакцией `eyes` в `2026-09-12T04:33:31Z`. Подтверждение запуска не считается review PASS. Work Order/repair anchor: comment `5643465221`; ответ на finding: comment `3995103270`.

## Durable resume

```text
last_completed_predicate = BOUNDED_R2_SOURCE_PUBLISHED_AND_DIFF_AUDITED
active_validation_run = 34673302661
active_review_request = 5643474514
next_actor = COORDINATOR_AND_FRESH_INDEPENDENT_REVIEWER
next_action = COLLECT_EXACT_R2_CI_AND_REVIEW_RESULTS
allowed_route = GITHUB_CONNECTOR_EXACT_SHA_RUN_JOB_AND_COMMENT_READ
known_forbidden_route = CONTAINER_GITHUB_CLONE_OR_DOWNLOAD_WORKAROUND
mission_complete = false
merge_performed = false
independent_acceptance = NOT_CLAIMED
```

Сначала live-проверить PR HEAD/base; при дрейфе не переносить результаты на новый source. Получить завершённый run/job, прочитать финальные test markers и PC0 результаты; статус workflow не заменяет чтение цветов PC0 при `--no-fail-on-red`. Сохранить точную привязку artifact/run/HEAD/digest и честно отличать metadata digest от локальной проверки ZIP.

Затем прочитать review на этом HEAD. При findings — scoped repair, новая точная проверка; при положительном независимом результате — existing verification/acceptance и human merge gate. Не повторять реализацию или все старые PASS из-за потери временного resource. Старые review comments не считать новым verdict.

CI и Codex review реально запущены, но эта запись не обещает автоматическую работу координатора после окончания его ответа. Права на принудительное продолжение вопреки остановке пользователя, обход security/authorization или self-acceptance отсутствуют.

## Исторические evidence pointers

R1 evidence: commit `2f77771c3dc3d971313397dda998d01e9026cb24`, path `docs/evidence/H0_CHANNEL_RECOVERY_REPAIR_R1_910b6578.md`, run `34672933829` — 322 tests OK. Его review RUNNING относится к моменту публикации, до нового P2; текущий маршрут R2 записан здесь без переписывания старой фактуры.
