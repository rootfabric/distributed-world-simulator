# Distributed World Simulator — Harness Control

**Canonical owner:** `main`
**Foundation revision:** `H0-2026-08-11-R1`
**Review layer:** `H0-REVIEW-2026-08-18-R2`
**Continuation layer:** `H0-CONTINUATION-2026-08-19-R3`
**Hygiene layer:** `H0-HYGIENE-2026-08-18-R1`

Это короткая точка входа для автономной/полуавтономной разработки. Mutable state берётся из machine-owned contracts и `CONTROL_DEVELOPMENT.ps1 -Status/-Plan/-Resume`; право завершить роль — только через `-Close`.

Полные протоколы:
```text
docs/control/DEVELOPMENT_HARNESS_RU.md
docs/control/HARNESS_REVIEW_AND_EVIDENCE_RU.md
docs/control/HARNESS_HYGIENE_AND_CONTINUATION_RU.md
```

Machine contracts:
```text
config/control/harness/project-goals.v1.json
config/control/harness/checkpoint-catalog.v1.json
config/control/harness/harness-policy.v1.json
config/control/harness/scheduler-policy.v1.json
config/control/harness/work-order.schema.v1.json
config/control/harness/event.schema.v1.json
config/control/harness/project-epoch.schema.v1.json
config/control/harness/risk-policy.v1.json
config/control/harness/review-policy.v1.json
config/control/harness/repair-doctrine.v1.json
config/control/harness/evidence-map.schema.v1.json
config/control/harness/human-attention.schema.v1.json
config/control/harness/continuation-policy.v1.json
config/control/harness/instruction-hygiene-policy.v1.json
config/control/harness/rule-registry.v1.json
```

## Основной контур
```text
mission / parent objective
        ↓
eligible checkpoint
        ↓
Project Epoch + bounded Work Order
        ↓
Implementer
        ↓ durable implementation/evidence
Verifier / Reviewer as required
        ↓ durable role result
Director / Integrator
        ↓
PC0 + directional audit
        ↓
checkpoint / merge gate
        ↓
post-gate validation
        ↓
resume parent mission
```

Потеря чата не должна мешать `Resume`. Результат штатной роли, существующий только в чате, не завершает handoff.

```text
COMMITS          = recovery units
CHECKPOINTS      = control units
EVIDENCE MAPS    = review units
EXCEPTIONS       = human attention units
ROLE HANDOFFS    = continuation transitions
MISSION          = end-to-end objective
```

## Continuation invariant
После любого промежуточного состояния Harness обязан уметь ответить:
```text
mission_complete?
next_actor
next_action
handoff_class
evidence_sink
resume_condition
on_success
on_failure
session_exit_allowed
closure_loop_required
stop_obligation
```

`REVIEW_REQUIRED` — `ROLE_BOUNDARY`, а не конец mission. Остановка роли допустима только после успешного `CONTROL_DEVELOPMENT.ps1 -Close`; exit code `7` означает обязательное продолжение по `next_action`.

Human Attention предназначен для реальных решений, а не для переноса PASS/FAIL между агентами.

## Self-closing role execution R3
`PLANNED`, `DISPATCHED`, `IN_PROGRESS` и автоматически исправимый `FIX_REQUIRED` не являются допустимым концом роли. `IMPLEMENTED` также не review-ready, пока не закрыты required predicates текущей роли.

Для in-scope repair Harness возвращает:
```text
handoff_class = CONTINUE_SAME_ROLE
next_actor = IMPLEMENTER
next_action = EXECUTE_REPAIR_TEST_CLOSURE_LOOP
session_exit_allowed = false
closure_loop_required = true
stop_obligation = DO_NOT_STOP_WHILE_AN_IN_SCOPE_AUTOMATABLE_REPAIR_REMAINS
```

Обязательный цикл:
```text
continue active role
  ↓
diagnose / Repair Map / canonical fix
  ↓
focused test
  ↓
all required regressions / control gates
  ↓
repair any new in-scope failure
  ↓
retest until GREEN or takeover threshold
  ↓
persist evidence + exact next transition
  ↓
CONTROL_DEVELOPMENT.ps1 -Close
```

Нельзя завершать роль сообщением «не доделал», «осталось проверить», «нужно продолжить позже», если Harness видит автоматически исполнимый переход. Review не запускается поверх незакрытой implementer-owned validation.

Повторный одинаковый defect после repair-attempt ceiling передаётся Director/stronger-context takeover с durable repair history, а не человеку как неопределённая проблема.

Fresh independent review не ослабляется: Implementer доводит роль до review-ready, но не self-reviews. Review `FAIL` маршрутизируется к repair ownership.

## Review durability
Reviewer имеет verdict только:
```text
PASS
FAIL
INSUFFICIENT_EVIDENCE
```

Для Harness Work Order default sink — versioned execution review result. Для PR-only gate — GitHub PR review/comment на exact HEAD. Chat-only verdict не является durable evidence.

Runtime checkpoint review остаётся exact-head fresh:
```text
reviewed HEAD == evidence HEAD == tested runtime HEAD
```

## Current state
Не поддерживать вручную список текущих gate. Получать его из:
```text
config/control/harness/scheduler-policy.v1.json
config/control/project-program-registry.v1.json
CONTROL_DEVELOPMENT.ps1 -Status
CONTROL_DEVELOPMENT.ps1 -Plan
CONTROL_DEVELOPMENT.ps1 -Resume
```

## Hygiene
Harness обязан контролировать собственную сложность:
- root instructions остаются router-ом;
- mutable state не дублируется в prose;
- правила имеют source / trigger / enforcement / retirement;
- protected safety/security/control/architecture rules не удаляются автоматически;
- часто нарушаемое prose-правило переносится в механику вместо усиления текста;
- механизированное правило вытесняет дублирующий prose только через reviewed change;
- self-tests обязаны доказывать, что известные bad fixtures fail closed;
- Golden Harness Set защищает от «улучшений», которые сокращают текст ценой поведения.
