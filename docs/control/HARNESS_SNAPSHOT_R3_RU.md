# HARNESS SNAPSHOT R3 — HYGIENE + CONTINUATION

**Snapshot:** `HARNESS-SNAPSHOT-R3`
**Captured:** 2026-08-18
**Status:** `VALIDATED_CANDIDATE_NOT_CANONICAL_MAIN`

## 1. Назначение

R3 фиксирует следующую ступень эволюции DWS Harness после R2. Главная цель — сделать Harness не только fail-closed, но и end-to-end live: локальная роль не должна терять глобальную цель, а штатный Reviewer/Verifier не должен превращать человека в message bus.

Одновременно R3 переносит безопасную часть Hybrid Harness R1: instruction hygiene, rule lifecycle, context budget, protected-rule retirement policy, Golden Harness Set и negative self-tests.

## 2. Provenance

### R1 — protocol baseline

```text
snapshot_id: HARNESS-SNAPSHOT-R1
branch: control/harness-development-protocol-r1
exact head: 4b9e6c2c9428f59860368ccad6cf1a561f28206e
PR: #65
role: first restart-safe Harness protocol baseline
```

### R2 — executable/review/control snapshot

```text
snapshot_id: HARNESS-SNAPSHOT-R2
captured: 2026-08-18
source main: d9a1a3ca03016d6851a258ff93d5c260a86c5b4c
snapshot branch: control/harness-development-snapshot-r2
snapshot metadata head: 9c0a00363662305569534e51efbe0ab11409432a
role: executable Harness + review/evidence + hardened Project Control
```

### R3 — hygiene + continuation candidate

```text
snapshot_id: HARNESS-SNAPSHOT-R3
captured: 2026-08-18
source base main: 598e92bb29a147bf12208d8549ddecaa4c9781ab
source branch: control/harness-continuation-hygiene-r1
exact source HEAD: 580c9453f205170600c5d8d2f596617d090359f4
PR: #131
Project Control: 32102853947 — SUCCESS
snapshot branch: control/harness-development-snapshot-r3
```

R3 source is a direct descendant of the R2 source and is 11 commits ahead of `d9a1a3ca...`; the merge base remains exactly the R2 source SHA.

## 3. Почему R3 пока candidate snapshot

Implementer этого изменения не должен сам себе выдать fresh independent PASS. Поэтому snapshot честно фиксирует состояние:

```text
CI / Project Control GREEN
fresh independent review still required
main not mutated by this candidate
```

PR #131 — единственный integration carrier. Snapshot branch — reference only.

## 4. Главная коррекция: Mission Continuation

Добавлен machine-derived continuation contract:

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

Новая семантика:

```text
REVIEW_REQUIRED != STOP
REVIEW_REQUIRED = ROLE_BOUNDARY
```

Штатный handoff обязан иметь durable sink. Chat-only PASS не авторизует переход.

Для Harness-managed Work Order default sink:
`EXECUTION_LEDGER`.

Для PR-only review gate:
`GITHUB_PR_REVIEW`.

## 5. Goal continuity

Work Order получил optional `mission` и `handoff` metadata. Исторические Work Orders не мигрируются и остаются schema-valid.

Если mission metadata отсутствует, Harness строит fallback:

```text
mission_id = CHECKPOINT:<goal_checkpoint>
mission_complete = false
```

Локальный конец роли не считается завершением end-to-end mission.

## 6. Human Attention

Новый invariant:

```text
HUMAN IS NOT A ROUTINE RESULT COURIER
```

Человек вызывается только при реальном `HUMAN_DECISION_REQUIRED`. Review/verification — обычные role boundaries.

## 7. Instruction hygiene

R3 убирает mutable current H0.x/frontier state из root router prose. Текущее состояние читается из scheduler/registry/`CONTROL_DEVELOPMENT`.

Добавлены:

```text
config/control/harness/instruction-hygiene-policy.v1.json
config/control/harness/rule-registry.v1.json
scripts/harness/instruction_hygiene.py
```

Проверяются budgets, mutable-state drift, rule passport completeness, duplicate IDs и protected-rule auto-retirement.

## 8. Rule lifecycle

Rule passport:

```text
rule_id
class
source
trigger
enforcement
retirement
```

Protected classes:

```text
SAFETY_INVARIANT
SECURITY_INVARIANT
CONTROL_INVARIANT
ARCHITECTURE_INVARIANT
```

Они не удаляются автоматически из-за возраста или отсутствия нарушений.

## 9. Context architecture

Root `AGENTS.md` теперь task-sensitive router. Вместо unconditional чтения всей control документации он сначала устанавливает authority, затем маршрутизирует по типу работы: implementation/fix, review/verify, control/recovery, architecture, Godot runtime.

Это уменьшает instruction noise без ослабления hard rules.

## 10. Self-tests / Golden Set

Добавлены 16 focused unit/self-tests и 9 golden cases. Покрываются:

```text
chat-only reviewer PASS
stale exact-head review
GitHub review sink routing
review PASS -> evidence refresh
missing predicates -> Verifier
blocking Human Attention
system blocker
parent mission continuity
protected rule retirement
mutable router state
context budget
golden-set breadth
```

Offline component suite: PASS.
Project Control exact candidate run `32102853947`: SUCCESS.

## 11. Что намеренно НЕ изменено

```text
production runtime
ECO
NX/V0 authority/runtime owners
scheduler mutation lease
Project Control ownership semantics
event reducer semantics
transition-table semantics
historical execution ledgers
A4/A5 autonomy ceiling
self-review prohibition
exact-head freshness
```

## 12. Seed/extraction profile

### KEEP AS GENERIC CORE

```text
scripts/harness/continuation.py
scripts/harness/instruction_hygiene.py
config/control/harness/continuation-policy.v1.json
config/control/harness/instruction-hygiene-policy.v1.json
config/control/harness/rule-registry.v1.json
review/evidence/risk/repair contracts
state/recovery core
```

### COPY THEN PARAMETERIZE

```text
AGENTS.md
HARNESS_CONTROL.md
CONTROL_DEVELOPMENT.ps1
scripts/harness/cli.py
scripts/harness/contracts.py
.github/workflows/project-control.yml
tests/harness/**
validation/harness/**
```

### RECREATE FOR TARGET PROJECT

```text
project goals
checkpoint catalog
program registry
architecture ownership
scheduler product lanes
Project Control domain policy
```

### EXCLUDE FROM CLEAN SEED

```text
DWS historical executions
DWS branch passports
V0/NX/SM0/ECO/MRPF domain identifiers
runtime/domain tests and evidence
```

## 13. Future lineage

Следующий snapshot должен называться `HARNESS-SNAPSHOT-R4`. R1/R2/R3 не переписываются и не переименовываются. Если PR #131 после review потребует repair, R3 остаётся историческим candidate snapshot; исправленное каноническое состояние фиксируется новым snapshot, а не rewrite R3.
