# Distributed World Simulator — Project Control Center

**Control plane:** `PC0-2026-08-10-R1`  
**Global architecture:** `GLOBAL-P0-2026-08-10-R2`  
**Development harness:** `H0-2026-08-11-R1`  
**Agent review layer:** `H0-REVIEW-2026-08-11-R1`  
**Canonical owner:** `main`

Это центральная точка верхнеуровневого контроля проекта. Быстро меняющееся состояние программ не дублируется в архитектурном roadmap вручную: operational truth строится из main-owned registry, branch passports, validation heads и реальных Git refs.

## С чего начинать проверку проекта

Для ответа на вопросы «какие ветки сейчас в работе, что им делать дальше и какой checkpoint следующий» сначала читать:

```text
docs/control/CURRENT_PROJECT_FRONTIERS_RU.md
```

Machine operational truth:

```text
config/control/project-program-registry.v1.json
```

Подробный convergence train:

```text
docs/plans/PROJECT_CONVERGENCE_2026-08-11_RU.md
```

Для автономной/полуавтономной разработки через harness:

```text
AGENTS.md
HARNESS_CONTROL.md
docs/control/DEVELOPMENT_HARNESS_RU.md
docs/control/HARNESS_REVIEW_AND_EVIDENCE_RU.md
config/control/harness/project-goals.v1.json
config/control/harness/checkpoint-catalog.v1.json
```

## Главное правило

```text
BRANCHES REPORT FACTS
MAIN DECLARES PROJECT STATE
AUDITOR CHECKS CONSISTENCY
GLOBAL ARCHITECTURE DEFINES WHAT IS ALLOWED
HARNESS MOVES ONLY BETWEEN DECLARED CHECKPOINTS
RISK ROUTES REVIEW DEPTH
EVIDENCE PACKAGE IS THE REVIEW UNIT
EXCEPTION IS THE HUMAN ATTENTION UNIT
```

Оперативный active frontier берётся из:

```text
config/control/project-program-registry.v1.json
```

Поля `active_frontiers` внутри старого `GLOBAL-P0 R2` считаются advisory legacy state до следующей global architecture revision. Это отделяет быстро меняющееся движение веток от медленно меняющейся архитектурной конституции.

## Canonical continuation rule

После принятого major handoff новая production-разработка по умолчанию **не продолжается бесконечным stacked lineage**.

```text
accepted evidence
      +
current canonical main
      ↓
fresh convergence/runtime frontier
      ↓
minimal capability transfer
      ↓
validation
      ↓
composition / merge / handoff
```

Длинная accepted ветка может оставаться evidence, но не становится автоматически базой следующего major runtime frontier.

## Harness continuation rule

Open-ended команда вроде `продолжай разработку проекта` не должна напрямую уходить worker-агенту.

```text
Director reads main + PC0
        ↓
select declared eligible checkpoint
        ↓
classify risk / Design Brief when required
        ↓
create Project Epoch from exact main SHA
        ↓
issue bounded Work Order
        ↓
worker implementation
        ↓
post-build critique when required
        ↓
Evidence Map
        ↓
independent Reviewer + Verifier
        ↓
PC0 + directional audit
        ↓
checkpoint proposal
        ↓
Human Attention only for explicit exception/approval
```

Git является durable memory harness. Возобновление работы не должно требовать истории чата. Implementer не может сам объявить checkpoint accepted.

Полные правила:

```text
docs/control/DEVELOPMENT_HARNESS_RU.md
docs/control/HARNESS_REVIEW_AND_EVIDENCE_RU.md
```

### Единицы управления

```text
commit          = recovery unit
checkpoint      = control unit
Evidence Map    = review unit
exception       = human attention unit
```

Количество commits или lines changed не является throughput KPI. Цель — доказанный project progress через принятые checkpoints, снятые blockers, свежую regression evidence и отсутствие architectural drift.

### Risk routing

```text
LOW      → Implementer + Verifier
MEDIUM   → Implementer + Reviewer + Verifier
HIGH     → Implementer + Reviewer + Verifier + Director
CRITICAL → Implementer + Reviewer + Verifier + Director + Human
```

Reviewer имеет verdict только:

```text
PASS
FAIL
INSUFFICIENT_EVIDENCE
```

Если доказательства не хватает, reviewer не угадывает.

`FIX_REQUIRED` для MEDIUM+ работы требует Repair Map перед следующим non-trivial fix. Runtime review должен быть exact-head fresh; runtime commit после review делает review stale.

### Human Attention Queue

Человек должен получать не поток agent commits, а явные решения:

```text
decision id
program / checkpoint
risk
reason
options
recommended option + reason
blast radius
blocking/non-blocking
evidence paths
```

Типичные human-attention triggers: architecture/ownership choice, security/auth, global identity, cross-server authority, CRITICAL risk, unresolved HIGH-risk reviewer disagreement, scope expansion after failed composition и product decision, который Director не может безопасно вывести сам.

Текущая harness pilot-последовательность:

```text
H0.0 RESTART-SAFE HARNESS SCAFFOLD
        ↓
H0_0_SCAFFOLD_READY
        ↓
H0.1 CLOSED-LOOP C22 PILOT
        +
C22 SOURCE_ACCEPTED_MERGE_READY
```

До `H0_0_SCAFFOLD_READY` автономная runtime-разработка запрещена. H0.0 должен также загружать/валидировать review/evidence contracts, но не исполняет runtime review flow. На H0.1 допускается максимум один автономный runtime worker и уже обязательны Risk Classification, Evidence Map, independent Reviewer, bounded post-build critique и exact-head review freshness.

Runtime merge, TS0.4 activation, global architecture promotion, foundation ownership transfer и новые global foundations остаются human gates.

## Как читать проект

```text
GLOBAL architecture / rules
        ↓
main-owned Project Registry
        +
main-owned Harness Goals / Checkpoints / Review Policy
        ↓
root AGENTS.md router
        ↓
registered branch passports
        ↓
Work Orders / Events / Evidence Maps
        ↓
validation + actual Git refs
        ↓
Reviewer + Verifier
        ↓
standard PC0 auditor
        +
directional watched-dependency auditor
        ↓
Director checkpoint verdict
        ↓
Human Attention Queue only when required
```

## Два вида dependency control

### Main dependency drift

Стандартный auditor проверяет:

```text
main changed dependency since branch merge-base
                ∩
branch watched_paths
                ↓
review / RED if critical
```

### Directional cross-branch watch

Дополнительный gate закрывает старую blind spot:

```text
producer branch changed X
                ∩
consumer watched_paths
                ↓
consumer YELLOW

producer branch changed X
                ∩
consumer critical_watched_paths
                ↓
consumer RED
```

Это отличается от обычного same-file overlap: consumer сам может вообще не менять `X`.

`SOURCE_ACCEPTED_HANDOFF_COMPLETE` остаётся consumer evidence, но подавляется как active producer. Поэтому замороженная accepted ветка не создаёт новые изменения, однако новая ветка всё ещё может потребовать её targeted revalidation, если затрагивает watched dependency.

## Что обязан показывать live dashboard

Для каждой зарегистрированной ветки:

```text
Identity / intent
  branch + role
  short description
  purpose
  expected outcome

Progress
  current stage + stage_status
  progress note
  last accepted checkpoint
  next stage
  blockers + health

Harness / review
  active Project Epoch
  active Work Order
  risk class
  review state / exact reviewed head
  Evidence Map state
  open human-attention items

Validation evidence
  runtime tested head
  focused tested head
  full-regression tested head
  runtime freshness: FRESH / STALE / PENDING / NOT_APPLICABLE
  runtime files changed after the tested head, если есть

Architecture / convergence
  dependencies
  ownership claims: foundation -> canonical owner -> scope
  foundations which the branch must not own
  dependency drift / critical dependency drift
  cross-branch overlap
  directional watched-dependency hits

Git reality
  actual branch head
  main-only / branch-only divergence
  findings emitted by the auditors
```

## Registry/passport mirror rule

Correctness не зависит от byte-equivalence длинного человеческого текста.

Механически зеркалируются только operational поля:

```text
branch
program
role
current_stage
stage_status
blockers
health_declared
```

`short_description`, `purpose`, `expected_outcome`, `progress_note`, `last_accepted_checkpoint`, `next_stage` остаются обязательной информацией, но их небольшое редакционное расхождение не является blocking control failure.

## Validation/review freshness

Нельзя считать `branch HEAD` автоматически проверенным runtime head. Поэтому dashboard различает `tested_heads.runtime`, `tested_heads.focused`, `tested_heads.full_regression`.

Если после tested runtime head изменился хотя бы один `runtime_paths`, auditor поднимает `RUNTIME_VALIDATION_STALE`.

Для agent review действует дополнительное правило:

```text
reviewed head
  == evidence head
  == tested runtime head for the reviewed runtime scope
```

Если после review изменился runtime scope, review становится `REVIEW_STALE` и не поддерживает checkpoint proposal до повторной проверки.

## Почему dependencies и ownership должны быть прямо в dashboard

Для параллельной разработки недостаточно знать только название этапа. Нужно сразу видеть:

- какие foundations ветка переиспользует;
- кто является их каноническим owner;
- какие watched dependencies могут сделать локальное evidence устаревшим;
- какие foundation concepts ветке запрещено присваивать себе;
- не меняют ли две активные ветки один runtime/contract path одновременно;
- не изменяет ли producer путь, который другая ветка считает watched/critical dependency.

Это позволяет заметить архитектурное расхождение до merge, а не после появления второго Registry/Manager/Authority/Persistence/Interest слоя.

## Запуск контроля

```powershell
cd C:\Godot\<checkout>
git fetch origin --prune
.\CONTROL_PROJECT.ps1
```

`CONTROL_PROJECT.ps1` запускает оба auditor-а. По умолчанию любой RED возвращает exit code `2`.

Только посмотреть состояние:

```powershell
.\CONTROL_PROJECT.ps1 -NoFailOnRed
```

Без повторного fetch стандартным auditor-ом:

```powershell
.\CONTROL_PROJECT.ps1 -NoFetch -NoFailOnRed
```

## Запуск из active checkout

Feature-ветки используют bootstrap `CONTROL_PROJECT.ps1`, который получает central registry/policy truth из `origin/main`. Поэтому feature branch не должна становиться независимым владельцем project state.

Root `AGENTS.md` также не владеет roadmap: он только маршрутизирует любого агента к актуальному central control.

## Когда запускать

Обязательно:

```text
перед началом следующего major stage
после major acceptance
после изменения global architecture
после появления нового Manager/Registry/Authority/Region/Transaction/Material/Scheduler foundation concept
после существенного изменения main
перед merge/composition
после регистрации новой active branch
когда producer branch меняет чужую watched dependency
перед harness checkpoint proposal
при Project Epoch invalidation/recovery
при risk reclassification
при REVIEW_STALE
при unresolved human-attention item перед blocking checkpoint
```

Минимальное правило: нельзя пройти два последовательных крупных acceptance checkpoint одной программы без промежуточного Project Control audit.

## Source of truth

```text
Architecture:
  docs/plans/GLOBAL_PROGRAM_ARCHITECTURE_ROADMAP_RU.md
  config/architecture/global-program-roadmap.v1.json

Control policy:
  config/control/project-control-policy.v1.json

Architecture ownership:
  config/control/architecture-ownership.v1.json

Current operational project state:
  config/control/project-program-registry.v1.json   <-- MAIN ONLY OWNER

Harness goals/checkpoints/policy:
  config/control/harness/project-goals.v1.json
  config/control/harness/checkpoint-catalog.v1.json
  config/control/harness/harness-policy.v1.json
  config/control/harness/scheduler-policy.v1.json

Harness review/evidence contracts:
  config/control/harness/risk-policy.v1.json
  config/control/harness/review-policy.v1.json
  config/control/harness/repair-doctrine.v1.json
  config/control/harness/evidence-map.schema.v1.json
  config/control/harness/human-attention.schema.v1.json

Agent router:
  AGENTS.md

Human harness protocol:
  HARNESS_CONTROL.md
  docs/control/DEVELOPMENT_HARNESS_RU.md
  docs/control/HARNESS_REVIEW_AND_EVIDENCE_RU.md

Human current-frontier snapshot:
  docs/control/CURRENT_PROJECT_FRONTIERS_RU.md

Branch-local facts:
  config/control/branches/<branch>.v1.json

Current convergence execution order:
  docs/plans/PROJECT_CONVERGENCE_2026-08-11_RU.md

Detailed control instructions:
  docs/control/PROJECT_CONTROL_PLANE_RU.md
```

## Stop rule

Если конкретная программа получает `RED`, её следующий объявленный major stage/acceptance блокируется, пока причина не закрыта или явно не пересмотрена в `main`.

Если harness не может восстановить state из Git без истории чата, autonomous checkpoint блокируется до исправления recovery contract.

Если Reviewer выдаёт `FAIL`, `INSUFFICIENT_EVIDENCE`, review stale или существует blocking Human Attention item, соответствующий runtime checkpoint proposal блокируется.

`SOURCE_ACCEPTED` не означает автоматически `MAIN_INTEGRATED`, `COMPOSITION_VERIFIED`, `PRODUCTION_READY` или разрешение перейти на следующий stage.
