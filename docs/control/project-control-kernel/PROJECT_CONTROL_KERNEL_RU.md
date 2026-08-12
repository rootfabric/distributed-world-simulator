# Project Control Kernel v1

**Тип:** переносимая модель управления software/R&D проектом с параллельными ветками и агентами  
**Назначение:** дать компактный ответ на вопросы `что происходит`, `куда движемся`, `кто над чем работает`, `что блокирует`, не превращая управление в отдельный бюрократический продукт.

Этот документ намеренно не зависит от Godot, Distributed World Simulator, конкретного CI или конкретной модели агентов.

# 1. Суть в восьми правилах

```text
BRANCHES REPORT FACTS
MAIN DECLARES INTENT
GIT PROVIDES REALITY
AUDITOR DERIVES HEALTH
CHECKPOINTS MOVE STATE
RISK SELECTS CEREMONY
HUMANS HANDLE EXCEPTIONS
DASHBOARD IS GENERATED
```

Эти восемь правил — ядро. Всё остальное является реализацией.

# 2. На какие вопросы обязан отвечать control plane

За один запуск control tool должны быть получены ответы:

```text
WHAT      Что сейчас делается?
WHY       Зачем это делается?
WHO       Кто / какой worker slot это выполняет?
WHERE     В какой ветке и на каком exact head?
STATE     Какой checkpoint и статус?
PROOF     На каком head есть тесты/review/evidence?
BLOCK     Что мешает двигаться дальше?
NEXT      Что является следующим допустимым действием?
GLOBAL    Не конфликтует ли работа с другими программами/владельцами?
```

Если для ответа нужно читать историю чата, десятки PR или вручную сравнивать несколько dashboard-документов, control plane не выполнил свою задачу.

# 3. Минимальные сущности

Kernel использует только пять обязательных сущностей и одну optional.

## 3.1 Policy / Constitution

Редко меняющийся набор правил:

```text
canonical branch
ownership boundaries
health predicates
risk routing
merge / promotion gates
human-only decisions
```

Policy отвечает на вопрос:

> Что в проекте разрешено и кто имеет право менять каноническую истину?

Она не должна содержать текущий progress.

## 3.2 Project Ledger

Main-owned оперативный индекс.

Для каждой программы достаточно хранить:

```text
program
frontier branch
role
checkpoint/disposition
priority
blocking gates
branch-card pointer
roadmap pointer
active-task pointer, если есть
```

Ledger отвечает:

> Куда проект официально направлен сейчас?

Не следует хранить в ledger длинные отчёты о тестах, hashes прошлых стадий и историю реализации.

## 3.3 Branch Card

Branch-local карточка текущего frontier.

Минимальный контракт:

```text
branch
program
role
intent
base_sha
checkpoint
state
owned_paths
watched_paths
critical_watched_paths
runtime_paths
evidence_heads
blockers
next_action
```

Допустимые короткие дополнительные поля:

```text
parent_checkpoint
risk_floor
architecture_revision
```

Branch Card отвечает:

> Что именно эта ветка делает и от чего зависит?

Она не является roadmap всей программы и не должна бесконечно накапливать историю.

## 3.4 Evidence Record

Immutable или append-only запись доказательства конкретного checkpoint.

Минимум:

```text
checkpoint
implementation_head
tested_head
reviewed_head
focused_validation
regression_validation
control_audit
review_verdict
remaining_risks
```

Для runtime/contract work применяется правило:

```text
implementation head
      == tested/relevant evidence head
      == reviewed head
```

или явно доказанная политика, почему metadata-only commits после implementation head не делают evidence stale.

Evidence Record отвечает:

> Почему мы считаем этот checkpoint доказанным?

## 3.5 Auditor / Resolver

Единственный executable interface контроля.

Он читает:

```text
policy
project ledger
branch cards
optional active tasks
evidence records
real Git refs
```

и только вычисляет состояние.

Auditor не должен становиться вторым местом ручного хранения project state.

## 3.6 Active Task — optional

Нужен только когда работа требует координации, автономного продолжения, bounded scope или нескольких worker slots.

Минимум:

```text
task_id
checkpoint
branch
base_sha
assigned_to
worker_slot
risk
allowed_paths
forbidden_paths
stop_conditions
state
last_durable_event
```

Active Task отвечает:

> Кто сейчас выполняет ограниченную работу и где её безопасно продолжить после потери сессии?

Для простой routine ветки отдельный Task не обязателен.

# 4. Один факт — один writable owner

Главное правило против control bloat:

```text
ONE FACT → ONE WRITABLE HOME
EVERY OTHER VIEW → DERIVED
```

Рекомендуемая ownership matrix:

| Факт | Writable owner |
|---|---|
| project priority / primary frontier | Project Ledger в canonical branch |
| architecture ownership | Policy / Constitution |
| branch intent / scope | Branch Card в самой ветке |
| actual branch head / divergence | Git, только derived |
| tests/review proof | Evidence Record |
| current task assignee | Active Task |
| health | derived Auditor result |
| dependency drift | derived Auditor result |
| overlap | derived Auditor result |
| dashboard | generated output |
| PR description | informational only |
| chat history | never authoritative |

Нельзя требовать синхронно менять `registry + passport + dashboard + PR body`, чтобы отразить одно и то же событие.

# 5. Минимальная state model

Kernel не требует одинакового state machine для всех сущностей.

Для human/project view достаточно семи состояний:

```text
PLANNED
ACTIVE
VERIFYING
BLOCKED
WAITING_HUMAN
ACCEPTED
FROZEN
```

`CANCELLED` используется для terminated work.

Более подробные внутренние состояния разрешены в конкретном Harness, но dashboard должен сворачивать их в эту модель.

Важно:

```text
BLOCKED != previous acceptance erased
```

Принятый checkpoint остаётся историческим фактом, даже если следующий checkpoint заблокирован.

# 6. Status dimensions

Для интеграционных проектов одного слова `ACCEPTED` недостаточно.

Рекомендуемый минимум:

```text
SOURCE_ACCEPTED
MAIN_INTEGRATED
COMPOSITION_VERIFIED
PRODUCTION_READY
```

Эти измерения независимы.

Пример допустимого состояния:

```text
SOURCE_ACCEPTED       true
MAIN_INTEGRATED       false
COMPOSITION_VERIFIED  true
PRODUCTION_READY      false
```

Такой state нельзя сокращать до «готово».

# 7. Dependency model

Branch Card объявляет четыре класса путей.

## owned_paths

То, что ветка ожидаемо меняет.

## watched_paths

Изменения здесь требуют review до следующего major checkpoint.

## critical_watched_paths

Изменения здесь блокируют следующий major checkpoint до явной revalidation.

## runtime_paths

Изменения после tested head делают runtime validation stale.

Это позволяет получить два типа защиты.

### Main → branch drift

```text
main changes X
X matches branch watched paths
        ↓
branch YELLOW / RED
```

### Branch → branch directional drift

```text
producer branch changes X
X matches consumer watched paths
        ↓
consumer YELLOW / RED
```

Directional dependency check обязателен для действительно параллельной разработки.

# 8. Ownership model

Каждый global foundation имеет одного canonical owner.

Branch может:

```text
consume
extend внутри своего domain
propose change
```

но не может молча создать конкурирующего владельца.

Auditor должен блокировать:

```text
duplicate global identity
duplicate authority registry
duplicate persistence truth
duplicate transaction coordinator
duplicate canonical material/domain registry
```

Конкретный список foundations зависит от проекта.

# 9. Health model

Health должен быть derived.

## GREEN

```text
No known blocking inconsistency.
Work may continue.
```

## YELLOW

```text
Work may continue locally.
A review/revalidation is required before the next major checkpoint.
```

Типовые причины:

```text
non-critical dependency drift
manual observation pending
metadata/control mismatch
non-critical overlap
review nearing stale boundary
```

## RED

```text
Next major checkpoint is blocked.
```

Типовые причины:

```text
critical dependency drift
runtime changed after tested head
review head stale
foundation ownership conflict
critical cross-branch overlap
invalid parent checkpoint
blocking evidence missing
```

`health_declared` может существовать как branch hint, но не должен побеждать derived health.

# 10. Resolver: как определяется работа

После audit resolver строит четыре очереди.

## CURRENT PRIMARY

Ровно один основной critical-path checkpoint либо явное `NONE`.

## EXECUTE_NOW

Работа, которая:

```text
eligible
unblocked
has required ownership
has available worker capacity
```

## PREPARE_NOW

Работа, полезная для primary path, но не переходящая запрещённый gate.

Примеры:

```text
read-only merge analysis
future Work Order design
fixture preparation
review checklist
architecture comparison
```

## BLOCKED_UNTIL_GATE

Работа, которую нельзя начинать, даже если она технически возможна.

Resolver обязан пересчитывать карту после:

```text
checkpoint acceptance
merge
canonical branch movement
architecture revision
human decision
critical dependency change
```

# 11. Кто над чем работает

Для multi-agent режима одного branch name недостаточно.

Dashboard должен выводить:

```text
worker_slot
assigned_to
task
program
branch
checkpoint
state
implementation head / latest durable event
blocking reason
```

Назначение записывается только при dispatch/reassignment/release.

Не нужен Git heartbeat каждую минуту. Если требуется live heartbeat, он должен быть ephemeral scheduler state и не создавать project-history noise.

# 12. Risk-scaled ceremony

Контроль должен быть пропорционален blast radius.

## LOW

Примеры:

```text
docs
simple tests
presentation-only wiring
generated mappings
```

Минимум:

```text
branch card
focused verification when relevant
Verifier or mechanical check
control audit before integration
```

## MEDIUM

Примеры:

```text
bounded internal behavior
local cache
non-authoritative optimization
local representation
```

Дополнительно:

```text
short design note when behavior changes
independent review
fresh evidence
```

## HIGH

Примеры:

```text
network protocol
persistence
canonical state mutation
public contract
recovery
authority behavior
```

Обязательно:

```text
bounded Active Task
exact base
explicit scope
Design Brief
Evidence Record
independent Reviewer + Verifier
fresh-head proof
control audit
Director disposition
```

## CRITICAL

Примеры:

```text
architecture ownership
global identity
security/auth
migration
new global foundation
cross-server authority
```

Дополнительно:

```text
explicit Human decision
```

Human gate не должен использоваться просто потому, что automation не знает, что делать. Это должно считаться control defect или insufficient evidence.

# 13. Checkpoint contract

Checkpoint должен отвечать на четыре вопроса:

```text
WHAT changed?
WHAT must be true?
WHAT evidence proves it?
WHAT becomes eligible after acceptance?
```

Хороший checkpoint bounded и проверяем.

Плохой checkpoint:

```text
Improve networking
Finish ecology
Make project stable
```

Хороший checkpoint:

```text
Owner-authoritative local movement survives defined latency/loss profile,
passes reconnect recovery,
and preserves server-owned canonical item state.
```

# 14. Evidence model

Evidence package должен быть коротким index, а не копией всех logs.

Он хранит pointers:

```text
implementation head
test command/result artifact
runtime/manual observation when required
review result
control result
known residual risks
```

Logs и screenshots могут быть большими, но Evidence Record остаётся компактным.

Правило:

```text
MISSING EVIDENCE != PASS
```

Допустимые reviewer verdicts:

```text
PASS
FAIL
INSUFFICIENT_EVIDENCE
```

# 15. Human Attention

Human получает только реальные решения.

Минимальная карточка:

```text
decision
why now
options
recommended option
blast radius
what remains blocked without decision
evidence pointers
```

Хорошие human gates:

```text
merge production runtime
promote architecture
transfer canonical ownership
accept irreversible migration
change product semantics
```

Плохие human gates:

```text
agent cannot find file
CI result was not parsed
status duplicated and disagrees
review evidence path is unknown
```

Последние случаи должны исправляться в control plane.

# 16. Agent instructions

Root agent instruction file должен быть router, а не второй policy document.

Целевой размер — достаточно короткий, чтобы агент реально прочитал его целиком.

Он должен говорить только:

```text
1. Run/read Project Control.
2. Resolve CURRENT PRIMARY or assigned task.
3. Read branch card + nearest scoped instructions.
4. Respect allowed/forbidden ownership and paths.
5. Use risk-selected validation/review.
6. Record durable evidence/checkpoint facts in their canonical homes.
7. Never use chat history as authorization.
```

Подробности должны жить в machine policy или scoped documentation.

# 17. Dashboard

Dashboard — pure projection.

Его нельзя вручную использовать как дополнительный source of truth.

Минимальные sections:

```text
PROJECT HEALTH
CURRENT PRIMARY
EXECUTE NOW
ACTIVE WORKERS
PROGRAM FRONTIERS
PREPARE NOW
BLOCKED UNTIL GATE
HUMAN ATTENTION
DRIFT / CONFLICTS
RECENT ACCEPTED CHECKPOINTS
```

Для программы показывается одна строка:

```text
PROGRAM | BRANCH | CHECKPOINT | NOW | NEXT | BLOCKER | HEALTH | WORKER
```

Подробности открываются по pointers, но не дублируются в dashboard.

# 18. Рекомендуемая структура репозитория

Переносимый минимальный layout:

```text
PROJECT_CONTROL.md                 # generated/short entrypoint
AGENTS.md                          # short router
control/
  policy.json
  project.json
  branches/
    ...                            # active branch cards
  tasks/
    ...                            # only controlled active tasks
  evidence/
    ...                            # checkpoint evidence indexes
scripts/control/
  control.py                       # single public audit/resolver command
artifacts/control/
  PROJECT_STATUS.md                # generated
  project-status.json              # generated
```

Архитектурные roadmap/docs могут лежать где угодно, но `project.json` содержит только pointers на них.

# 19. Что не должно быть частью Kernel

Kernel не должен владеть:

```text
product roadmap content
domain architecture details
test implementation
CI vendor specifics
IDE integration
chat protocol
agent model/provider
runtime scheduler/game scheduler
```

Он управляет разработкой, а не продуктом.

# 20. Антипаттерны

## Dashboard as database

Если dashboard редактируется вручную и содержит уникальный live state, он станет stale.

## Passport as diary

Если branch card растёт после каждого checkpoint, history находится не там.

## Registry as report

Если registry содержит многостраничные progress notes, любое движение ветки требует дорогой central sync.

## Every task is CRITICAL

Если docs change проходит тот же Harness, что persistence migration, разработчики начнут обходить Harness.

## Commit-count management

Количество commits не показывает прогресс и стимулирует noise.

## Chat as authorization

Фраза из старой сессии не может разрешать merge или runtime work после изменения canonical state.

## Parallel truths

Нельзя иметь два independently editable live dashboards, два ownership registries или два current-primary resolvers.

# 21. Минимальная проверка переносимости

Перед переносом Kernel в другой проект нужно определить только:

```text
canonical branch
programs
foundation owners
risk triggers
major checkpoints
human-only gates
branch-card path conventions
validation commands/evidence sources
```

После этого auditor должен уметь получить Git refs и построить dashboard без знания предметной области.

# 22. Формула компактного сильного контроля

```text
CONTROL STRENGTH
    = explicit ownership
    + Git-grounded evidence
    + dependency/freshness checks
    + deterministic next-action resolver
    + risk-scaled gates

CONTROL COST
    = duplicated writable state
    + manual synchronization
    + unnecessary lifecycle states
    + universal ceremony
    + control-specific commit churn
```

Цель Kernel:

```text
maximize CONTROL STRENGTH
minimize CONTROL COST
```

Самый важный practical test:

> Новый агент, не имея истории чата, должен после одного control command понять текущее состояние проекта, свою допустимую следующую работу и причины всех блокировок. При этом обычная low-risk разработка не должна требовать от него обслуживания control plane ради самого control plane.
