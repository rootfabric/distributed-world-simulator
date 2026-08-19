# Harness Hygiene + Continuation R2

**Дата:** 2026-08-19
**Статус:** control-layer candidate
**Scope:** Harness/control only. Production runtime, ECO, NX/V0/SM authority/runtime semantics не меняются.

## 1. Почему появился этот слой

Существующий Harness хорошо умеет fail-closed остановить неправильный переход, но до continuation R1 не всегда мог машинно ответить, кто обязан выполнить следующий разрешённый шаг. R1 исправил role handoff, но оставил второй liveness gap: `FIX_REQUIRED` всё ещё мог стать фактическим концом implementer-сессии даже при полностью автоматизируемом repair.

Типичный дефект R1:

```text
Implementer запускает тест
→ тест FAIL
→ durable FIX_REQUIRED
→ Harness классифицирует состояние как SYSTEM_BLOCKED
→ Director должен отдельно диагностировать очевидный repair
→ implementer-сессия заканчивается фразой «не доделал»
→ человек вручную решает, продолжать ли тот же repair
```

Это безопасно в fail-closed смысле, но плохо для throughput и автономности. R2 вводит self-closing role execution без ослабления separation of duties.

## 2. Mission continuity

Work Order может опционально объявить `mission_id`, `objective`, `parent_mission_id`, `completion_condition`. Исторические Work Orders не мигрируются. Для них mission выводится как `CHECKPOINT:<goal_checkpoint>`.

Локальное завершение Implementer/Reviewer/Verifier не закрывает mission. `mission_complete` может быть объявлен только после канонического условия завершения, а не потому что конкретный агент закончил свою роль.

## 3. Continuation contract

`CONTROL_DEVELOPMENT` обязан выдавать:

```text
mission_id
mission_complete
handoff_class
next_actor
next_action
evidence_sink
resume_condition
on_success
on_failure
human_decision_required
session_exit_allowed
closure_loop_required
stop_obligation
```

Классы: `CONTINUE_SAME_ROLE`, `ROLE_BOUNDARY`, `EXTERNAL_WAIT`, `HUMAN_DECISION_REQUIRED`, `SYSTEM_BLOCKED`, `MISSION_COMPLETE`.

`REVIEW_REQUIRED` — это `ROLE_BOUNDARY`, не terminal mission state. `FIX_REQUIRED` — это `CONTINUE_SAME_ROLE`, если repair остаётся in-scope и automatable.

## 4. Durable role handoff

Штатные результаты ролей не передаются через человека. Reviewer пишет durable review result; Verifier — durable verification; Director — durable checkpoint/control decision.

Для Harness-managed Work Order default sink — `EXECUTION_LEDGER`. Для PR-only gate — `GITHUB_PR_REVIEW`. Review Request обязан назвать sink. `PASS` только в чате не имеет authority. Freshness остаётся exact-head fail-closed.

## 5. Self-closing execution loop

Implementer не имеет права завершить роль только потому, что очередная попытка дала FAIL.

Пока defect:

- находится в `allowed_paths` / declared Work Order scope;
- не требует новой architecture ownership decision;
- не требует human approval;
- не упирается во внешний недоступный ресурс;
- не достиг takeover threshold повторного одинакового defect,

Harness обязан возвращать:

```text
handoff_class = CONTINUE_SAME_ROLE
next_actor = IMPLEMENTER
next_action = EXECUTE_REPAIR_TEST_CLOSURE_LOOP
session_exit_allowed = false
closure_loop_required = true
stop_obligation = DO_NOT_STOP_WHILE_AN_IN_SCOPE_AUTOMATABLE_REPAIR_REMAINS
```

Исполнитель обязан пройти:

```text
1. Diagnose root cause.
2. Create or refresh Repair Map before a non-trivial fix.
3. Fix canonical owner, not only failing symptom.
4. Run the focused failing test.
5. Run every required regression / Project Control gate owned by the Work Order.
6. If a new in-scope failure appears, diagnose and repair it in the same session.
7. Repeat until role predicates are GREEN or takeover threshold is reached.
8. Persist exact evidence.
9. Persist exact next transition before role exit.
```

Focused test GREEN не означает role complete, если остаются required regression/control predicates.

Запрещён не сам факт незавершённой mission, а **неструктурированный выход из роли при доступном автоматическом продолжении**.

## 6. Repeated defect takeover

Repair Doctrine по-прежнему не разрешает бесконечно латать один и тот же defect. R2 интерпретирует повторный failure как takeover boundary, а не как конец работы:

```text
same defect reaches configured threshold
→ ROLE_BOUNDARY
→ DIRECTOR
→ ESCALATE_REPEATED_DEFECT_FOR_TAKEOVER
→ stronger context / new bounded Repair Work Order
```

Human не является default escalation target. Human Attention используется только когда нужен реальный выбор/approval.

## 7. Review routing

Fresh independent review остаётся обязательным там, где его требует risk/review policy.

R2 различает:

```text
review MISSING / STALE
→ REVIEWER

review FAIL
→ IMPLEMENTER repair ownership

review INSUFFICIENT_EVIDENCE
→ DIRECTOR routes each evidence gap to its owner

review PASS + stale/missing Evidence Map
→ DIRECTOR evidence refresh
```

Review `FAIL` не должен бесконечно отправляться обратно Reviewer без изменения candidate.

## 8. Пример SM1-I2.1 Repair R2

Для PR #149 Implementer на Repair R2 уже выполнил свой closure loop:

```text
OD-CAS-17 PASS
+ previous Repair R1 component evidence remains valid
+ exact-head Project Control SUCCESS
+ exact candidate and durable PR body updated
```

Следующий шаг — fresh independent review. Это корректный `ROLE_BOUNDARY`, потому что Implementer не имеет права сам выполнить independent review.

Правильный machine outcome здесь:

```text
session_exit_allowed = true
handoff_class = ROLE_BOUNDARY
next_actor = REVIEWER
next_action = PERSIST_FRESH_EXACT_HEAD_REVIEW
resume_condition = durable exact-head review verdict
```

То есть R2 не заставляет одну сессию нарушать independence. Он заставляет её **полностью закрыть собственную роль** и оставить однозначный durable handoff.

## 9. Instruction hygiene

Root instruction files — router, а не энциклопедия и не live dashboard. Mutable state (`current H0.x`, active branch/head/frontier) не копируется вручную в `AGENTS.md`/`HARNESS_CONTROL.md`; оно читается из machine-owned state.

Иерархия хранения правила: machine check → template → routed thematic doc → short triggered rule → explanation.

## 10. Rule lifecycle

Control-layer rule имеет passport: `rule_id`, `class`, `source`, `trigger`, `enforcement`, `retirement`.

Protected classes: `SAFETY_INVARIANT`, `SECURITY_INVARIANT`, `CONTROL_INVARIANT`, `ARCHITECTURE_INVARIANT`. Они никогда не удаляются автоматически из-за возраста или отсутствия нарушений. `PROCESS_GUARD` может стать retirement candidate, но только reviewed change.

## 11. Context budget

`instruction_hygiene.py` fail-closed проверяет budgets root router files, запрещённый mutable state, дубли rule IDs, обязательные поля rule passport, запрет auto-retirement protected rules и inflation importance markers.

## 12. Golden Harness Set

Golden Set содержит failure modes: chat-only reviewer PASS, stale exact-head review, self-accept, blocking human decision, system blocker, evidence refresh, missing predicates, protected rule retirement, mutable state in router, automatable `FIX_REQUIRED` session stop и review-FAIL loopback to Reviewer.

Он не запускает модель в обычном CI.

## 13. Совместимость

Коррекция не меняет event reducer semantics, не добавляет обязательных полей историческим Work Orders, не переписывает execution ledgers, не меняет scheduler mutation lease, не меняет Project Control ownership/runtime truth, не касается ECO/NX/V0/SM runtime, не разрешает self-review, не превращает chat PASS в evidence, не ослабляет exact-head и не расширяет A4/A5 autonomy.

## 14. Правильный PR handoff

```text
Mission: RESTORE_MAIN_NON_RED_AND_RESUME_PARENT
repair candidate GREEN
→ next_actor = REVIEWER
→ evidence_sink = GITHUB_PR_REVIEW
→ resume_condition = durable PASS on exact candidate
PASS persisted
→ next_actor = DIRECTOR
→ evaluate pinned merge / declared gate
post-gate NON_RED
→ resume parent mission
```

Человек не должен копировать `PASS` между чатами и не должен вручную решать, продолжать ли автоматизируемый in-scope repair.
