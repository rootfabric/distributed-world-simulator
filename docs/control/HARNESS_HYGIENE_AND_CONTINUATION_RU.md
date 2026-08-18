# Harness Hygiene + Continuation R1

**Дата:** 2026-08-18
**Статус:** control-layer candidate
**Scope:** Harness/control only. Production runtime, ECO, NX/V0 authority/runtime semantics не меняются.

## 1. Почему появился этот слой

Существующий Harness хорошо умеет fail-closed остановить неправильный переход, но до R1 не всегда мог машинно ответить, кто обязан выполнить следующий разрешённый шаг.

Типичный дефект:

```text
Implementer завершил repair
→ fresh Reviewer обязателен
→ Reviewer вернул PASS только в чат
→ следующий Director не видит durable PASS
→ человек вручную переносит результат между сессиями
→ глобальная цель теряется за локальной ролью
```

Это нарушает одновременно два собственных принципа Harness:

```text
GIT IS DURABLE MEMORY; CHAT IS NOT
EXCEPTION IS THE UNIT OF HUMAN ATTENTION
```

Fresh independent review остаётся обязательным. Исправляется не строгость review, а liveness между ролями.

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
```

Классы: `CONTINUE_SAME_ROLE`, `ROLE_BOUNDARY`, `EXTERNAL_WAIT`, `HUMAN_DECISION_REQUIRED`, `SYSTEM_BLOCKED`, `MISSION_COMPLETE`.

`REVIEW_REQUIRED` — это `ROLE_BOUNDARY`, не терминальная остановка.

## 4. Durable role handoff

Штатные результаты ролей не передаются через человека. Reviewer пишет durable review result; Verifier — durable verification; Director — durable checkpoint/control decision.

Для Harness-managed Work Order default sink — `EXECUTION_LEDGER`. Для PR-only gate — `GITHUB_PR_REVIEW`. Review Request обязан назвать sink. `PASS` только в чате не имеет authority. Freshness остаётся exact-head fail-closed.

## 5. On-success / on-failure

Каждый role boundary описывает обе стороны: PASS/success → следующий transition; FAIL → repair; INSUFFICIENT → evidence repair; STALE → fresh review. Нельзя оставлять промежуточный PASS без следующего действия.

## 6. Instruction hygiene

Root instruction files — router, а не энциклопедия и не live dashboard. Mutable state (`current H0.x`, active branch/head/frontier) не копируется вручную в `AGENTS.md`/`HARNESS_CONTROL.md`; оно читается из machine-owned state.

Иерархия хранения правила: machine check → template → routed thematic doc → short triggered rule → explanation.

## 7. Rule lifecycle

Control-layer rule имеет passport: `rule_id`, `class`, `source`, `trigger`, `enforcement`, `retirement`.

Protected classes: `SAFETY_INVARIANT`, `SECURITY_INVARIANT`, `CONTROL_INVARIANT`, `ARCHITECTURE_INVARIANT`. Они никогда не удаляются автоматически из-за возраста или отсутствия нарушений. `PROCESS_GUARD` может стать retirement candidate, но только reviewed change.

## 8. Context budget

`instruction_hygiene.py` fail-closed проверяет budgets root router files, запрещённый mutable state, дубли rule IDs, обязательные поля rule passport, запрет auto-retirement protected rules и inflation importance markers.

## 9. Golden Harness Set

Golden Set содержит failure modes: chat-only reviewer PASS, stale exact-head review, self-accept, blocking human decision, system blocker, evidence refresh, missing predicates, protected rule retirement и mutable state in router. Он не запускает модель в обычном CI.

## 10. Совместимость

Коррекция не меняет event reducer semantics, не добавляет обязательных полей историческим Work Orders, не переписывает execution ledgers, не меняет scheduler mutation lease, не меняет Project Control ownership/runtime truth, не касается ECO, не разрешает self-review, не превращает chat PASS в evidence, не ослабляет exact-head и не расширяет A4/A5 autonomy.

## 11. Правильный PR handoff

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

Человек не должен копировать `PASS` между чатами.
