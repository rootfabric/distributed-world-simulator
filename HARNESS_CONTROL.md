# Distributed World Simulator — Harness Control

**Canonical owner:** `main`  
**Harness foundation:** `H0-2026-08-11-R1`  
**Continuation layer:** `H0-CONTINUATION-2026-08-20-R5`  
**Git authority layer:** `H0-GIT-AUTHORITY-2026-08-20-R1`

Это короткая точка входа для автономной/полуавтономной разработки. Mutable current checkpoint/execution не должен быть зашит в этот файл: он определяется machine-owned scheduler policy и durable execution state.

Полные протоколы:

```text
docs/control/DEVELOPMENT_HARNESS_RU.md
docs/control/HARNESS_REVIEW_AND_EVIDENCE_RU.md
```

Machine contracts:

```text
config/control/harness/project-goals.v1.json
config/control/harness/checkpoint-catalog.v1.json
config/control/harness/harness-policy.v1.json
config/control/harness/scheduler-policy.v1.json
config/control/harness/continuation-policy.v1.json
config/control/harness/work-order.schema.v1.json
config/control/harness/event.schema.v1.json
config/control/harness/project-epoch.schema.v1.json
config/control/harness/risk-policy.v1.json
config/control/harness/review-policy.v1.json
config/control/harness/repair-doctrine.v1.json
config/control/harness/evidence-map.schema.v1.json
config/control/harness/human-attention.schema.v1.json
```

## R5: checkpoint-session + default Git authority invariant

```text
ROADMAP CHECKPOINT = user-visible mission/session unit
WORK ORDER          = bounded execution unit
ROLE                = isolated responsibility unit
ATTEMPT             = repair/retry unit
COMMIT               = recovery unit
```

`ROLE_BOUNDARY` не является `MISSION_BOUNDARY`. Implementer, Reviewer, Verifier, Integrator и Director могут сменяться внутри одной пользовательской сессии, но checkpoint mission остаётся открытой.

Mission exit разрешён только в трёх случаях:

```text
MISSION_COMPLETE
  canonical main contains durable ACCEPTED record for goal checkpoint

HUMAN_DECISION_REQUIRED
  real blocking Human Attention item exists

HARD_BLOCKED
  durable proof says the blocker is non-automatable in current scope
```

`BLOCKED` без такого proof не является `HARD_BLOCKED` и маршрутизируется Director-у для recovery/replan.

Следующие состояния не являются концом checkpoint mission:

```text
PLANNED
DISPATCHED
IN_PROGRESS
IMPLEMENTED
VERIFYING
VERIFIED
AUDITED
CHECKPOINT_PROPOSED
FIX_REQUIRED
REVIEW_REQUIRED
REVIEW_FAIL
VERIFIER_REQUIRED
EVIDENCE_REFRESH_REQUIRED
PC0_REQUIRED
TAKEOVER_REQUIRED
EPOCH_INVALIDATED
WORK_ORDER_CANCELLED
```


## Default Git authority

Запуск checkpoint mission одновременно даёт проектную Git authority до `A3_INTEGRATE_CANDIDATE`. Отдельное подтверждение человека для штатных операций не требуется:

```text
create feature/control/repair branch
create clean worktree
stage only Work-Order-scoped paths
commit durable checkpoint
non-force push
post durable evidence / PR comment
open or update draft PR
request independent review
propose checkpoint
```

Рутинный `ROLE_BOUNDARY` эту authority не сбрасывает. Director также может выпустить новый bounded repair Work Order внутри уже активной checkpoint mission, если не расширяются scope/ownership/human gates.

Человеческое подтверждение требуется только для настоящих gates: runtime merge, direct push to canonical `main`, force-push/history rewrite, destructive remote branch deletion, architecture/foundation authority transfer и явные product decisions.

Если внешний Git/GitHub tool сам технически требует подтверждение, Harness не должен называть это project human gate. Машинная классификация: `EXTERNAL_TOOL_AUTH_REQUIRED`.

## Driver

Публичный контур:

```text
.\CONTROL_DEVELOPMENT.ps1 -Drive
```

Без override Harness берёт `v0_product_train_routing.current_checkpoint` из scheduler policy, находит свежий execution для этого checkpoint и возвращает machine-derived:

```text
mission_id
mission_complete
handoff_class
next_actor
next_action
resume_condition
role_exit_allowed
mission_exit_allowed
session_exit_allowed
human_decision_required
hard_blocked
stop_obligation
```

`session_exit_allowed` сохранён как compatibility alias и равен `mission_exit_allowed` — пользовательская сессия принадлежит mission, а не текущей роли.

Рекомендуемый цикл Director/parent session:

```text
Drive
  ↓
execute next_actor / next_action in isolated child role
  ↓
persist durable result/evidence
  ↓
Drive again
  ↓
repeat across role boundaries
  ↓
MISSION_COMPLETE | HUMAN_DECISION_REQUIRED | HARD_BLOCKED
```

Fresh Reviewer/Verifier всё ещё обязательны там, где это требует risk policy. Их независимость не отменяется; устраняется только необходимость человеку вручную переносить результат в новую пользовательскую сессию.

## Close gates

```text
.\CONTROL_DEVELOPMENT.ps1 -CloseRole
```

Проверяет только текущую ответственность роли. Exit code `7 / ROLE_EXIT_FORBIDDEN` означает, что у роли осталось автоматизируемое действие и она не должна завершаться.

```text
.\CONTROL_DEVELOPMENT.ps1 -Close
.\CONTROL_DEVELOPMENT.ps1 -CloseMission
```

Оба проверяют checkpoint mission. Exit code `8 / MISSION_EXIT_FORBIDDEN` означает, что родительская пользовательская сессия должна продолжить `next_actor / next_action`. `-Close` намеренно является alias именно mission close.

## Canonical mission completion

Локальные `IMPLEMENTED`, `VERIFIED`, `AUDITED` и `CHECKPOINT_PROPOSED` не закрывают mission. `mission_complete=true` выводится только из main-owned durable acceptance record для точного `goal_checkpoint`.

Это сохраняет существующую модель:

```text
COMMITS       = recovery units
CHECKPOINTS   = control + user-session units
EVIDENCE MAPS = review units
EXCEPTIONS    = human attention units
```

Risk routing, exact-head freshness, Evidence Map, Repair Doctrine, PC0/directional audit, runtime merge human gates и запрет Implementer self-accept остаются действующими.
