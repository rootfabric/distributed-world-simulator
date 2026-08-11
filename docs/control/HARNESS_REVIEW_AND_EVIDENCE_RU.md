# Distributed World Simulator — Evidence-Driven Agent Review

**Review layer:** `H0-REVIEW-2026-08-11-R1`  
**Canonical owner:** `main`  
**Harness dependency:** `H0-2026-08-11-R1`

Этот документ дополняет `DEVELOPMENT_HARNESS_RU.md` и определяет, как масштабировать агентскую разработку без пропорционального роста человеческого review.

## 1. Основная модель

```text
COMMITS ARE RECOVERY UNITS
CHECKPOINTS ARE CONTROL UNITS
EVIDENCE PACKAGES ARE REVIEW UNITS
EXCEPTIONS ARE HUMAN ATTENTION UNITS
```

Человек не должен читать каждый commit или каждую строку рутинного agent-generated code. Система обязана автоматически сжимать поток работы до checkpoint evidence и исключений, где реально нужно архитектурное или продуктовое решение.

```text
many agent actions
      ↓
durable commits
      ↓
Work Orders
      ↓
checkpoint evidence packages
      ↓
review findings
      ↓
Human Attention Queue
```

## 2. Risk routing

Каждый Work Order имеет `risk_class`:

```text
LOW
  docs / tests / simple UI / presentation plumbing / simple adapters
  → Implementer + Verifier

MEDIUM
  bounded internal runtime / representation / cache / non-authoritative optimization
  → Implementer + Reviewer + Verifier

HIGH
  protocol / persistence / canonical state mutation / public contract / recovery / authority
  → Implementer + Reviewer + Verifier + Director

CRITICAL
  architecture ownership / migration / security-auth / global identity / new foundation / cross-server authority
  → Implementer + Reviewer + Verifier + Director + Human
```

Risk можно повысить, но нельзя понизить ниже minimum trigger из `risk-policy.v1.json`.

## 3. Pre-build Design Brief

Для `MEDIUM+` implementation нельзя сразу переходить к коду. Work Order должен зафиксировать:

```text
problem statement
current behavior
desired behavior
alternatives considered
selected design + why
affected canonical owners
dependencies
non-goals
expected risks
validation plan
```

Цель — тратить архитектурное внимание до реализации, а не после десятков commits.

## 4. Repair Doctrine

`FIX_REQUIRED` не означает "исправь строку, где упал тест".

Перед новым fix для MEDIUM/HIGH/CRITICAL работы строится Repair Map:

```text
affected module
canonical owner
entry points
callers / callees
sibling paths
existing + missing tests
contracts
expected shipped behavior
history/evidence
root cause hypothesis
canonical fix location
why this is not symptom patching
```

```text
FAILING TEST != ROOT CAUSE LOCATION
```

Если второй fix того же defect снова неуспешен — обязательна escalation к более сильной модели/Director и replan.

## 5. Reviewer — отдельная роль

```text
IMPLEMENTER
  реализует bounded Work Order

REVIEWER
  пытается доказать, что design/root cause/owner/sibling coverage ошибочны

VERIFIER
  независимо запускает проверки и подтверждает evidence

INTEGRATOR
  проверяет cross-branch/composition при необходимости

PC0
  проверяет global constraints

DIRECTOR
  принимает checkpoint verdict
```

Implementer не может сам принять свою работу.

Reviewer имеет только три verdict:

```text
PASS
FAIL
INSUFFICIENT_EVIDENCE
```

`INSUFFICIENT_EVIDENCE` используется вместо догадок.

## 6. Evidence Map

Перед runtime checkpoint proposal создаётся Evidence Map по `evidence-map.schema.v1.json`.

Она должна позволять понять изменение без чтения всей истории commits:

```text
intent / root cause
risk class
exact evidence head
changed surfaces
canonical owner
entry points
callers / callees
siblings checked
canonical truth changed? yes/no
architecture ownership changed? yes/no
focused validation
full regression
PC0 / directional PC0
production diff summary
remaining risks
required fixes
rank-up moves
review verdict
```

Evidence Map — основной интерфейс review, а не commit list.

## 7. Post-build critique

После реализации MEDIUM+ Work Order выполняется один обязательный bounded critique pass:

```text
появилась ли лишняя сложность?
duplicate truth?
implicit owner?
можно уменьшить coupling?
нужно проверить/fix sibling surface?
есть удаляемый код?
design стал хуже плана?
какой refactor был бы нужен при redesign?
```

Результат:

```text
NO_MATERIAL_REFACTOR_REQUIRED
or
REFACTOR_REQUIRED
```

Это один обязательный проход, не бесконечный refactor loop.

## 8. Required fixes vs Rank-up moves

Reviewer разделяет:

```text
REQUIRED_FIXES
  блокируют checkpoint

RANK_UP_MOVES
  полезные улучшения, не блокирующие checkpoint по умолчанию
```

Director может поднять Rank-up move в текущий scope только явно; иначе он становится будущим Work Order/checkpoint candidate.

## 9. Exact-head review freshness

Для runtime checkpoint:

```text
reviewed HEAD
== evidence HEAD
== tested runtime HEAD (для runtime scope)
```

Runtime commit после review делает review `STALE`. Такой review не может поддерживать checkpoint proposal до повторной проверки.

## 10. Human Attention Queue

Человеку показываются исключения, а не поток commits.

Типичная запись:

```text
Decision: HD-042
Program: NX
Checkpoint: NX_SOURCE_ACCEPTED
Risk: CRITICAL/HIGH
Reason: authority contract choice
Decision required: ...
Options: A / B
Recommended: A
Blast radius: NX / reconnect / persistence
Blocking: true
```

Основные triggers:

```text
CRITICAL risk
architecture/ownership choice
security/auth change
cross-server authority
unresolved HIGH-risk reviewer disagreement
failed composition requiring scope expansion
product choice that Director cannot infer safely
```

## 11. Scoped agent instructions

Root `AGENTS.md` является router. Он не дублирует архитектуру.

```text
ROOT AGENTS.md
   ↓
PROJECT_CONTROL.md
HARNESS_CONTROL.md
   ↓
program passport
   ↓
nearest scoped AGENTS.md / local guidance if present
```

Scoped instructions могут добавлять локальные traps/tests/conventions, но не могут переопределять:

```text
architecture ownership
PC0 policy
main-owned project registry
harness checkpoints
autonomy ceiling
human gates
```

## 12. Throughput metrics

Harness оптимизирует не Git activity.

```text
GOOD KPIs
accepted checkpoints
critical-path checkpoints
blockers cleared
regressions escaped
architecture drift findings
accepted-but-not-integrated backlog
average Work Order cycle
human decisions required
recovery success rate

NOT KPIs
commits/day
lines changed
raw agent action count
```

Цель:

```text
PROVEN PROJECT PROGRESS
```

## 13. Activation by harness stage

### H0.0

Review contracts обязаны загружаться/валидироваться scaffold-ом, но runtime review flow ещё не исполняется. Runtime workers = 0.

### H0.1 / C22

Обязательны:

```text
risk classification
Design Brief if risk requires it
post-build critique
Evidence Map
independent Reviewer
PASS (не INSUFFICIENT_EVIDENCE)
exact-head review freshness
Human Attention Queue empty/resolved
```

### H0.2 / NX

NX имеет минимум HIGH risk и используется как экзамен high-risk authority/protocol review.

### H0.3+

Добавляется Integrator и несколько runtime workers; человеческий интерфейс становится exception-oriented dashboard/attention queue.

## 14. Machine contracts

```text
config/control/harness/risk-policy.v1.json
config/control/harness/review-policy.v1.json
config/control/harness/repair-doctrine.v1.json
config/control/harness/evidence-map.schema.v1.json
config/control/harness/human-attention.schema.v1.json
```
