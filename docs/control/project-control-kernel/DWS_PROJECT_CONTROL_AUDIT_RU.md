# Distributed World Simulator — аудит управляющих механизмов

**Статус:** research / portability analysis  
**Ветка:** `docs/project-control-kernel-r1`  
**Snapshot canonical main:** `4a42c2fb6befb386f5c3eb48d9ba070745e25bbb`  
**Snapshot registry generation:** `77`  
**Не является:** runtime authorization, checkpoint acceptance, изменением PC0/Harness policy или заменой canonical registry.

## 1. Зачем сделан этот аудит

В проекте уже появился зрелый control plane, но его развитие прошло несколько итераций:

```text
PC0 project control
      ↓
branch passports + registry + auditor
      ↓
restart-safe Harness
      ↓
Work Orders / Epochs / event ledger
      ↓
risk / Evidence Map / independent review
      ↓
directional dependency watch
      ↓
CURRENT PRIMARY / EXECUTE_NOW / PREPARE_NOW resolver
```

Каждая итерация закрывала реальную проблему. Одновременно выросло число файлов, состояний и мест, где похожая информация записывается повторно.

Цель этого документа — отделить:

```text
СИЛЬНЫЕ ИНВАРИАНТЫ
от
ИСТОРИЧЕСКИ НАРОСШЕЙ ЦЕРЕМОНИИ
```

и определить, какие части следует сохранить в будущем компактном Project Control Kernel.

## 2. Эволюция механизма

### 2.1 PC0 — исходное сильное ядро

Исходная формализация была сделана в:

```text
branch: infra/pc0-project-control-plane
PR:     #57 — PC0: add main-owned project control plane
```

Она ввела правильное разделение:

```text
GLOBAL ROADMAP     = архитектурная конституция
PROJECT REGISTRY   = официальное оперативное состояние
BRANCH PASSPORT    = локальные факты ветки
VALIDATION         = доказательство
AUDITOR            = сравнение деклараций с Git reality
DASHBOARD          = human-readable projection
```

Это по-прежнему наиболее важная архитектурная идея всей системы.

### 2.2 H0 — restart-safe development Harness

Дальше появились:

```text
PR #65  canonical restart-safe development harness protocol
PR #66  H0.0 scaffold gate before runtime pilot
PR #67  evidence-driven review + human attention control
```

Добавлены:

```text
Project Epoch
Work Order
append-only Event
checkpoint catalog
risk classification
Design Brief
Repair Doctrine
Evidence Map
Reviewer / Verifier separation
Human Attention Queue
exact-head review freshness
Git-only recovery
```

Это закрыло важную задачу: агентная разработка больше не должна зависеть от истории чата, а implementer не может сам объявить свой checkpoint принятым.

### 2.3 Directional watch

Обычный overlap обнаруживает только ситуацию:

```text
branch A changes X
branch B changes X
```

Directional auditor добавил более сильную проверку:

```text
branch A changes X
branch B watches X
branch B itself does not change X
        ↓
B becomes YELLOW / RED
```

Для многоветочной разработки это один из наиболее ценных механизмов проекта.

### 2.4 Executable project map

Позднее PR #87 добавил resolver для общего запроса `продолжай работу над проектом`:

```text
CONTROL_PROJECT
      ↓
CURRENT PRIMARY
      ↓
EXECUTE_NOW
      │
      ├─ executable → execute
      └─ waits gate → PREPARE_NOW
                       ↓
                 do not touch BLOCKED_UNTIL_GATE
```

Это важное улучшение: dashboard стал отвечать не только «что существует», но и «что делать сейчас».

### 2.5 R7 → R8 как проверка fail-closed свойства

H0.1 R7 / PR #88 был отменён, когда выяснилось, что вычисление `implementation_head_sha` не включало bounded C22 runtime surface. Это означало, что exact-head review мог бы подтверждать не тот implementation head.

Система не пропустила checkpoint и закрылась fail-closed.

R8 / PR #90 исправил fence: review target теперь выводится из заранее объявленного Work Order scope и отделяет implementation surface от append-only control evidence.

Это одновременно показывает две вещи:

1. exact-head freshness действительно защищает от ложной acceptance;
2. сам control plane уже достаточно сложен, чтобы иметь собственные correctness bugs.

## 3. Что сейчас существует

### 3.1 Main-owned control

```text
PROJECT_CONTROL.md
config/control/project-control-policy.v1.json
config/control/project-program-registry.v1.json
config/control/architecture-ownership.v1.json
```

### 3.2 Branch-local control

```text
config/control/branches/<branch>.v1.json
```

Passport хранит identity, intent, stage, status, dependencies, owned/watched/runtime paths, tested heads, ownership claims, blockers и descriptive progress.

### 3.3 Mechanical audit

```text
scripts/control/project_control.py
scripts/control/project_control_directional_watch.py
CONTROL_PROJECT.ps1
```

Standard auditor проверяет:

```text
branch exists
passport exists
registry/passport identity
architecture revision
registry/passport mirror drift
foundation ownership
main → branch watched dependency drift
runtime tested-head freshness
cross-branch same-file overlap
```

Directional auditor проверяет:

```text
producer branch changed path
               ∩
consumer watched / critical watched paths
               ↓
consumer YELLOW / RED
```

### 3.4 Human dashboard

```text
docs/control/CURRENT_PROJECT_FRONTIERS_RU.md
artifacts/control/PROJECT_STATUS_RU.md
artifacts/control/project-control-report.json
```

Здесь важно различать:

```text
CURRENT_PROJECT_FRONTIERS_RU.md = вручную поддерживаемая operational prose
PROJECT_STATUS_RU.md            = derived auditor output
project-control-report.json     = derived machine output
```

### 3.5 Agent router

```text
AGENTS.md
```

Root `AGENTS.md` правильно является router, а не отдельным roadmap.

### 3.6 Harness

```text
HARNESS_CONTROL.md
docs/control/DEVELOPMENT_HARNESS_RU.md
docs/control/HARNESS_REVIEW_AND_EVIDENCE_RU.md
config/control/harness/*
scripts/harness/*
CONTROL_DEVELOPMENT.ps1
```

Harness вводит checkpoint-driven автономную работу и recovery.

## 4. Что работает особенно хорошо и должно быть сохранено

### KEEP-1 — main declares project intent/state

Официальный project state имеет одного владельца.

Это предотвращает ситуацию, когда каждая feature branch объявляет собственную версию roadmap.

Сохраняем принцип:

```text
MAIN DECLARES PROJECT INTENT
```

### KEEP-2 — branches report local facts

Branch passport хранится внутри самой ветки. Поэтому параллельные ветки не дерутся за один общий mutable manifest.

Сохраняем:

```text
BRANCHES REPORT LOCAL FACTS
```

### KEEP-3 — Git reality сильнее декларации

Auditor не доверяет одному `health_declared`: он смотрит реальный branch ref, merge-base и diff.

Сохраняем:

```text
GIT PROVIDES REALITY
```

### KEEP-4 — health должен вычисляться

GREEN/YELLOW/RED полезны только когда являются результатом механических predicates, а не мнением автора ветки.

Сохраняем:

```text
AUDITOR DERIVES HEALTH
```

### KEEP-5 — owned / watched / critical watched paths

Это компактный способ описать ownership и dependency graph без построения сложной IDE-scale semantic database.

Особенно ценен directional watch.

### KEEP-6 — tested head freshness

Связь validation с SHA защищает от классической ошибки:

```text
tests passed
   ↓
code changed
   ↓
old PASS mistakenly reused
```

Это один из обязательных переносимых инвариантов.

### KEEP-7 — checkpoint, а не commit, является единицей прогресса

Commit нужен для recovery. Пользовательский прогресс — это закрытый checkpoint, снятый blocker или достигнутый gate.

Сохраняем:

```text
COMMITS ARE RECOVERY UNITS
CHECKPOINTS ARE PROGRESS/CONTROL UNITS
```

### KEEP-8 — status dimensions не должны смешиваться

Полезно отдельно хранить:

```text
SOURCE_ACCEPTED
MAIN_INTEGRATED
COMPOSITION_VERIFIED
PRODUCTION_READY
```

Иначе локальный PASS быстро превращается в ложное «готово».

### KEEP-9 — risk-based review

LOW/MEDIUM/HIGH/CRITICAL — правильная идея, потому что одинаковая церемония для документации и authority/persistence кода была бы вредна.

### KEEP-10 — independent acceptance для опасной работы

Implementer не должен сам быть единственным источником `PASS` для HIGH/CRITICAL изменения.

### KEEP-11 — Human Attention только для решений

Человеку нужно показывать не поток agent commits, а:

```text
что требуется решить
почему
варианты
рекомендацию
blast radius
что блокируется
```

Это правильное направление для масштабирования multi-agent разработки.

### KEEP-12 — CURRENT PRIMARY resolver

В любой момент должен существовать однозначный ответ:

```text
что главное сейчас?
что можно делать прямо сейчас?
что подготовлено?
что заблокировано?
```

Это нужно сделать частью machine-derived dashboard, а не большой вручную редактируемой статьи.

## 5. Где система стала слишком тяжёлой

### FRICTION-1 — один факт записывается несколько раз

Например current stage / progress / next / blockers могут встречаться в:

```text
central registry
branch passport
CURRENT_PROJECT_FRONTIERS_RU.md
Work Order
checkpoint document
Evidence Map
PR body
Harness event history
```

Не все копии формально authoritative, но человеку приходится различать их вручную.

Результат — reconciliation drift.

### FRICTION-2 — registry стал слишком текстовым

Registry generation 77 содержит длинные `project_summary`, `progress_note`, `next_stage`, acceptance hashes и исторические детали.

Это превращает ledger из компактного state index в постоянно переписываемую документацию.

Registry должен хранить **решения и pointers**, а не историю исполнения.

### FRICTION-3 — passports стали мини-roadmaps

На длинных research branches passport включает:

```text
большие progress narratives
десятки validation paths
длинные blocker lists
planned cross-tracks
историю предыдущих acceptance
```

Passport должен быть карточкой текущего frontier, а не энциклопедией программы.

### FRICTION-4 — manually maintained current dashboard неизбежно стареет

На snapshot `main @ 4a42c2fb... / registry 77` canonical registry всё ещё описывает более раннее состояние CH/ECO, тогда как branch-local facts уже ушли вперёд.

Это не нарушение принципа `MAIN DECLARES PROJECT STATE`, но human dashboard без явного reconciliation view может выглядеть как live truth, хотя фактически является snapshot.

Главный dashboard должен генерироваться.

### FRICTION-5 — несколько state machines описывают одно движение

Сейчас существуют отдельно:

```text
branch lifecycle
Work Order lifecycle
Project Epoch lifecycle
checkpoint state
review state
human gate state
```

Они нужны как разные аспекты, но не должны все вручную зеркалить общий progress.

### FRICTION-6 — universal Harness ceremony слишком дорогая

Полный путь:

```text
Epoch
Work Order
risk
Design Brief
implementation
post-build critique
Evidence Map
Reviewer
Verifier
PC0
directional PC0
checkpoint proposal
```

оправдан для runtime, authority, persistence, network и architecture work.

Он слишком тяжёл для большинства docs/research/low-risk changes.

### FRICTION-7 — main movement создаёт control churn

Exact epoch pinning полезен для high-risk runtime work, но попытка применять его слишком широко приводит к repin/recreate/cancel даже при безопасном изменении unrelated metadata.

Epoch должен быть специальным режимом controlled execution, а не базовой единицей любой разработки.

### FRICTION-8 — два auditor-а увеличивают поверхность контроля

Standard и directional проверки концептуально являются одним dependency/overlap audit.

Они могут оставаться отдельными модулями реализации, но пользовательский interface и report должны быть едиными.

### FRICTION-9 — actual worker assignment недостаточно явен

Append-only event имеет `actor`, однако Work Order schema фиксирует required roles, но не требует durable назначения конкретного worker slot.

Для multi-agent dashboard нужен простой факт:

```text
task → assigned_to / worker_slot
```

Он должен меняться только при dispatch/release, без heartbeat commits.

### FRICTION-10 — control system способен создавать собственные bugs

R7 freshness-fence defect — полезный пример. Чем больше special-case path filters, derived heads, transition artifacts и state reducers, тем больше вероятность, что control plane сам станет причиной остановки production work.

Поэтому правило для control code должно быть тем же, что для runtime:

```text
prefer derivation
prefer one source
prefer fewer states
prefer explicit invariants
```

## 6. Решение по каждому механизму

### Оставить как core

```text
architecture / ownership constitution
main-owned project ledger
branch-local cards
Git-ref based auditor
owned/watched/critical dependency model
runtime/tested-head freshness
directional watch
checkpoint model
status dimensions
single CURRENT PRIMARY resolver
risk routing
independent review for HIGH/CRITICAL
human exception queue
Git-only recovery for autonomous work
```

### Сжать

```text
project registry prose
branch passport prose
AGENTS mandatory read surface
Work Order fields
Evidence Map required fields
number of lifecycle states
checkpoint documents
```

### Сделать derived, а не manually maintained

```text
current dashboard
program health
Git divergence
validation freshness
overlap
directional dependency hits
active worker table
EXECUTE_NOW / PREPARE_NOW / BLOCKED queue
```

### Сделать optional / risk-triggered

```text
Project Epoch
append-only execution ledger
Design Brief
Repair Map
post-build critique
full Evidence Map
independent Reviewer
human gate
```

При этом HIGH/CRITICAL runtime и architecture work по-прежнему должны fail closed.

## 7. Целевая модель для DWS

Минимальная цепочка:

```text
POLICY / OWNERSHIP
        ↓
MAIN PROJECT LEDGER
        ↓
BRANCH CARDS + optional ACTIVE TASKS
        ↓
REAL GIT + TEST/REVIEW EVIDENCE
        ↓
ONE AUDITOR / RESOLVER
        ↓
GENERATED PROJECT DASHBOARD
```

И правило записи:

```text
ONE FACT → ONE WRITABLE HOME
EVERY OTHER VIEW → DERIVED
```

### Что должен хранить main ledger

Только:

```text
program identity
canonical frontier branch
role
current checkpoint/disposition
priority / primary flag
blocking gates
pointers to branch card / task / roadmap
```

Не должен хранить длинную execution history.

### Что должен хранить branch card

Только текущий локальный контракт:

```text
branch
program
intent
role
base
current checkpoint/state
owned paths
watched paths
critical watched paths
runtime paths
latest evidence heads
blockers
next local action
```

История acceptance живёт в checkpoint/evidence records, а не растёт внутри passport.

### Что должен хранить active task

Только если работа действительно требует coordination:

```text
task id
checkpoint
branch
base SHA
assigned_to / worker_slot
risk
allowed scope
stop conditions
state
latest durable event
```

### Что должен вычислять auditor

```text
actual head / divergence
passport/ledger drift
dependency drift
directional watch hits
ownership conflicts
runtime validation freshness
review freshness
cross-branch overlap
worker/task occupancy
program health
project health
CURRENT PRIMARY
EXECUTE_NOW
PREPARE_NOW
BLOCKED_UNTIL_GATE
```

## 8. Предлагаемый режим нагрузки

### ROUTINE

Для docs, research notes, simple tests, presentation-only work:

```text
branch card
focused verification if relevant
Git audit
```

Без Epoch/ledger/Evidence Map ceremony.

### CONTROLLED

Для runtime behavior, public contracts, non-trivial integration:

```text
active task
risk
bounded scope
fresh evidence head
independent review when required
PC0
checkpoint
```

### CRITICAL

Для ownership, global identity, authority, security, migrations:

```text
controlled mode
+
exact base/epoch fence
+
full evidence package
+
Director
+
Human decision
```

Таким образом сила контроля растёт вместе с blast radius, а не вместе с количеством файлов проекта.

## 9. Как мигрировать без риска для текущей разработки

Нельзя переписывать active H0.1 control plane во время текущего runtime epoch только ради чистоты.

Безопасный порядок:

### Phase A — extraction only

Этот документ + переносимый kernel документ. Никаких policy/runtime изменений.

### Phase B — shadow resolver

На безопасной control boundary добавить новый read-only resolver, который читает существующие PC0/Harness данные и строит компактный dashboard.

Сравнивать его вывод с текущим PC0, ничего не авторизуя через него.

### Phase C — generated dashboard

Когда эквивалентность доказана, сделать human current dashboard generated-only.

Удалить ручное дублирование live state из prose.

### Phase D — slim registry/passport v2

Ввести компактные v2 contracts и adapter, который некоторое время читает v1 + v2.

Не выполнять big-bang migration всех веток.

### Phase E — risk-scaled Harness

Routine work перестаёт создавать полный Epoch/Work Order/Evidence stack.

Controlled/Critical сохраняют строгий fail-closed path.

### Phase F — unified audit surface

Standard + directional проверки получают один CLI/report/status interface.

Внутренняя реализация может оставаться модульной.

## 10. Критерии успеха

Новый control plane можно считать лучше текущего, если одновременно выполняются условия:

```text
1. Один CONTROL command отвечает, что происходит в проекте.
2. Видно ровно один CURRENT PRIMARY или явное отсутствие primary.
3. Видно, кто/какой worker slot занят каждой active controlled task.
4. Для каждой программы видны NOW / NEXT / BLOCKER.
5. Dashboard нельзя сделать stale ручным редактированием.
6. Один факт не надо менять в registry + passport + dashboard одновременно.
7. Low-risk работа почти не замечает control plane.
8. HIGH/CRITICAL работа по-прежнему fail closed.
9. Потеря chat history не мешает восстановить active controlled work.
10. Audit объясняет каждую YELLOW/RED конкретным predicate и Git evidence.
```

## 11. Итог

Текущая система не требует демонтажа. Её сильная часть уже найдена экспериментально.

Суть, которую нужно сохранить:

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

Всё остальное должно оправдывать своё существование тем, что помогает одному из этих инвариантов. Если артефакт только повторяет уже известный state, он кандидат на удаление или генерацию.
