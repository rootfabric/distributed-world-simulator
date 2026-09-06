# PROJECT-FOCUS AUTONOMY REVIEW REPAIR R3

Статус при открытии: FIX_IN_PROGRESS; не Reviewer/Verifier PASS и не acceptance.

## Ограничение работы

Work Order: `PROJECT-FOCUS-AUTONOMY-REVIEW-REPAIR-R3`.
Base: `696bd6b7329236913de6e514d643099e6f1bc7cf`, tree
`d690bc62774c9759b9b1981ca4090bafae74d535`.
Canonical main при начале ремонта: `fa2b6024481ea5a796ec9c7b0e2f9885f1a82c91`.
Перед публикацией принят main `d768a7ee4d60eab25a125a10604ec068079478d5`: additive
stall-guard policy и три policy tests. Guard сохранён вместе с autonomy; runtime и
generation main не менялись. Новый candidate наследует обе линии без rewrite.
Parent PR: #547. Независимый review на `719a896`:
3940491129, 3940491138, 3940491144 (три P1).

Разрешены только Harness provenance/continuation, их тесты, обновление observed-main
после доказанного transport-only drift и документация этой коррекции.
Runtime, scenes, существующие executions/reviews/evidence/acceptance не изменяются.
Нет merge, P7 acceptance, MVP activation, нового runtime lease или dispatch.

## Repair Map

- affected_module: Harness continuation, state_builder и event_reducer.
- canonical_owner: main-owned Harness; никакого второго scheduler/evidence owner.
- entry_points: CONTROL_DEVELOPMENT.ps1 → harness.cli → build_state/build_continuation.
- callers: CLI, review loader, guarded checkpoint-proposal/recovery transitions.
- callees: committed Git objects, immutable event ledger, review policy.
- sibling_paths: review PASS в reducer обязан пройти тот же provenance validator.
- existing_tests: autonomy runtime/policy, checkpoint-session, historical generation 80.
- missing_tests: настоящие Git repositories → immutable event → build_state → CLI;
  nonexistent/untracked/dirty/rebound proof; missing/wrong manifest/digest/tree/run/log;
  guarded event path и сохранение исторической совместимости.
- public_or_internal_contracts: typed hard-block proof в существующем evidence_paths;
  generation-81 post-build review machine_evidence + committed digest manifest.
- expected_shipped_behavior: корректное proof позволяет реальный HARD_BLOCKED;
  вымышленное proof не позволяет выход; digest-free current PASS не имеет authority.
- relevant_history_or_evidence: frozen Windows R1/R2 и review threads сохраняются;
  они не переносятся на новый subject.
- root_cause_hypothesis: декларации policy тестировались на искусственном state;
  production loader и event consumers не использовали новые provenance требования.
- canonical_fix_location: единый evidence_provenance validator и реальные consumers.
- why_not_symptom_patch: не ослаблять CloseMission, не добавлять безусловный PASS,
  не выключать regressions и не переписывать старые evidence.

## Почему предыдущая сессия не дошла до результата

Сначала повторялось чтение/проектирование без repair commit. Новые autonomy правила
расширили control subject после прежнего PASS; свежий Reviewer нашёл реальные P1.
Затем main получил transport-policy merge, но observed_main кандидата остался старым.
Это разные причины; CI success и Windows PASS предшественника не закрывают их.

## Ограниченный протокол продолжения

1. Сверить live main/control один раз перед изменениями и ещё раз перед публикацией.
2. Один bounded patch закрывает перечисленные P1 и observed-main drift; новые
   несвязанные улучшения не добавляются в этот subject.
3. На каждый P1 — воспроизводимый отрицательный тест и положительный production path.
4. Команды имеют timeout; повтор одинаковой инфраструктурной ошибки не заменяет работу.
   После двух одинаковых ошибок сменить разрешённый способ, сохранив точную причину.
5. После локальных проверок публиковать repair и заморозить HEAD; evidence добавлять
   отдельно. Не изменять subject ради новых статусов/описаний во время review.
6. Не создавать Actions для source export/Git transport. Обычный git failure сначала
   диагностировать; разрешённый GitHub connector остаётся каналом Git operations.
7. Independent Reviewer/Verifier не подменяются Implementer self-test.
8. Ожидание внешней роли/CI не выдаётся за исполнение. Сохранять request ID, subject,
   evidence и точный следующий шаг. Mission acceptance не объявлять.

## Исполняемые evidence-контракты

### Hard block

Существующий `BLOCKED` event использует `evidence_paths`; event schema не меняется.
Один referenced JSON имеет schema
`distributed_world_simulator.harness_hard_block_proof.v1` и поля:
`work_order_id`, `project_epoch`, `checkpoint`, `blocked_event_id`,
`blocked_head_sha`, `blocked_tree_sha`, `blocker`, `proof_evidence_path`.
Значения должны точно совпадать с active Work Order и последним BLOCKED event.
К ним добавляются все boolean/string clauses действующей continuation policy.
Proof и event должны быть обычными immutable committed файлами; non-empty path
сам по себе ничего не доказывает. Git TREE сверяется по subject commit.
`build_state` выбирает proof только через последнее authoritative событие;
continuation повторно проверяет эту связь. Незакрытый epoch/checkout finding
не может быть скрыт за прежним hard-block proof.

### Post-build review generation 81+

`machine_evidence` обязателен для текущего post-build PASS как в loader, так и в
checkpoint/recovery event guards. Поля: `mode` (FRESH_EXECUTION или REUSED),
`manifest_path`, `manifest_sha256`, `runner_id`, `run_id`, `artifact_paths`.
Название FRESH_EXECUTION не заменяет факт исполнения.

Manifest schema: `distributed_world_simulator.harness_machine_evidence_manifest.v1`.
Он содержит `work_order_id`, `project_epoch`, `subject_head_sha`,
`subject_tree_sha`, `runner_id`, `run_id`, `tracked_checkout_clean_before/after`,
`artifacts`, `commands`. Artifact содержит `path`, `sha256`, `run_id`,
`subject_head_sha`. Command содержит `command`, `exit_code`, `expected_exit_code`,
`log_path`; каждый log обязан присутствовать среди artifacts.

Digest считается по committed Git blob bytes. На Windows текстовый EOL может
нормализоваться Git: hash manifest/log после канонизации либо сохранять бинарно.
Относительные POSIX paths не могут выходить из checkout, входить в .git или
проходить через symlink. Review, manifest и artifacts должны быть committed,
append-only и не изменены в рабочем дереве. Отсутствующий/непривязанный digest
даёт derived INSUFFICIENT_EVIDENCE, сохраняя исходный review JSON без переписывания.
Исторические epochs <=80 сохраняют прежний контракт; текущая generation-проверка
не позволяет использовать их как active authority. Pre-build design review не
нуждается в runtime manifest, но не может заменить post-build PASS в proposal.

Digest подтверждает целостность и идентичность, а не правдивость автора лога.
Доверие runner, достаточность команд, skips и независимый verdict остаются
обязанностью свежих Reviewer/Verifier, а не Implementer или hash-функции.
