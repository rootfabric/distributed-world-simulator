# Distributed World Simulator — Development Harness Protocol

**Harness revision:** `H0-2026-08-11-R1`  
**Canonical owner:** `main`  
**Control dependency:** `PC0-2026-08-10-R1`  
**Architecture baseline:** `GLOBAL-P0-2026-08-10-R2`

Этот документ определяет, как автономные и полуавтономные агенты должны развивать проект через harness так, чтобы работа:

- продолжалась после обрыва сессии;
- не зависела от памяти чата;
- не расходилась между ветками;
- двигалась от checkpoint к checkpoint;
- постоянно фиксировала durable state в Git;
- не позволяла implementer-агенту самостоятельно объявить свой результат принятым.

Machine-readable политика находится в `config/control/harness/`.

---

## 1. Базовая модель

```text
main
  ├─ architecture
  ├─ PC0 policy
  ├─ project registry
  ├─ project goals
  ├─ checkpoint catalog
  ├─ harness/autonomy/scheduler policy
  └─ schemas
          ↓
      Director
          ↓
   select checkpoint
          ↓
      Project Epoch
          ↓
      Work Orders
          ↓
 worker branch/worktree
          ↓
 implementation/events/evidence
          ↓
 independent verifier
          ↓
 PC0 + directional audit
          ↓
 checkpoint proposal
          ↓
 human gate where required
          ↓
 main declares new project state
```

`main` владеет целями, политиками и глобальным project state. Feature/control branches сообщают факты исполнения.

---

## 2. Durable memory

Главное правило:

```text
GIT IS DURABLE MEMORY
CHAT IS NOT DURABLE MEMORY
```

После потери текущей сессии новый Director обязан восстановить:

- active Project Epoch;
- exact base SHA;
- registry generation;
- architecture revision;
- active branch/head;
- последний durable work-order state;
- завершённые predicates;
- открытый blocker;
- следующий разрешённый work order;
- verification commands;
- ожидаемые human gates.

Если для восстановления требуется содержание старого чата, harness checkpoint не считается пройденным.

Generated `artifacts/harness/**` — cache. Он должен пересоздаваться из Git.

---

## 3. Что хранится в main, а что в worker branch

### `main`

Хранит:

```text
project goals
checkpoint definitions
autonomy policy
scheduler policy
schemas
project-wide checkpoint declarations
registry/frontier state
architecture/ownership
```

### Worker branch

Хранит:

```text
branch passport
Project Epoch instance for this execution train
work-order instances
append-only execution events
implementation
validation summaries/evidence
checkpoint proposal
```

Высокочастотный execution ledger не пишется напрямую в `main`. Иначе параллельные агенты начнут конфликтовать за центральный журнал.

После принятия/merge в `main` переносится только итоговое project-state решение и долговечная необходимая evidence/documentation.

---

## 4. Project Epoch

Каждый автономный development train получает immutable execution baseline.

Пример:

```text
epoch_id: E2026-08-11-H0-1
base_sha: <exact canonical main SHA>
registry_generation: 63
architecture_revision: GLOBAL-P0-2026-08-10-R2
harness_revision: H0-2026-08-11-R1
eligible_checkpoints:
  - H0_1_CLOSED_LOOP_C22_PILOT
status: ACTIVE
```

Epoch проверяется:

```text
before dispatch
before significant implementation continuation
before verification
before checkpoint proposal
```

Если `main` изменился, это не означает автоматический reset.

Сначала:

```text
main moved
   ↓
PC0 + directional dependency audit
   ↓
CONTINUE
or
REFRESH_REQUIRED
```

При `REFRESH_REQUIRED` старый epoch получает immutable `EPOCH_INVALIDATED` event; работа не продолжается молча от устаревшей базы.

---

## 5. Work Order

Worker не получает команду вида:

```text
"продолжай NX"
```

Он получает bounded Work Order:

```text
Goal checkpoint
Exact epoch/base SHA
Allowed paths
Forbidden paths
Required predicates
Required outputs
Stop conditions
Human approvals
```

Work-order state machine:

```text
PLANNED
  ↓
DISPATCHED
  ↓
IN_PROGRESS
  ↓
IMPLEMENTED
  ↓
VERIFYING
  ↓
VERIFIED
  ↓
AUDITED
  ↓
CHECKPOINT_PROPOSED
```

Допустимые ответвления:

```text
FIX_REQUIRED
BLOCKED
WAITING_HUMAN
EPOCH_INVALIDATED
CANCELLED
```

Нельзя превращать failure в PASS редактированием summary.

---

## 6. Append-only events

История работы фиксируется immutable events.

Типичные события:

```text
WORK_ORDER_CREATED
DISPATCHED
IMPLEMENTATION_COMMITTED
VERIFICATION_STARTED
PREDICATE_VERIFIED
AUDIT_COMPLETED
FIX_REQUIRED
BLOCKED
WAITING_HUMAN
EPOCH_INVALIDATED
CHECKPOINT_PROPOSED
RECOVERY_RESUMED
```

Новый факт добавляется новым event-файлом. Старый event не переписывается для изменения истории.

Текущее состояние work order вычисляется из event sequence.

---

## 7. Git checkpoint discipline

Нельзя коммитить по таймеру и нельзя ждать один гигантский финальный commit.

Durable commit нужен после атомарного восстанавливаемого состояния, например:

```text
capability implemented within scope
meaningful focused test result recorded
blocker discovered / FIX_REQUIRED
fix verified
passport/tested heads updated
checkpoint proposal prepared
```

Микроскопическое внутреннее действие не обязано иметь отдельный commit.

Рекомендуемые trailers:

```text
Project-Epoch: E2026-08-11-H0-1
Work-Order: H0-C22-WO-001
Predicate: C22_FOCUSED_PASS
Work-State: VERIFIED
```

Правила активной harness-ветки:

```text
no force-push
no history rewrite
push after every durable atomic checkpoint
planned stop -> clean worktree
unfinished failing work -> FIX_REQUIRED/BLOCKED event before stop
```

---

## 8. Separation of duties

```text
IMPLEMENTER
  changes code

VERIFIER
  runs independent verification

PC0
  verifies project/architecture/convergence constraints

DIRECTOR
  decides whether checkpoint predicates are satisfied
```

Implementer не может сам перевести checkpoint в accepted state только своим утверждением.

Для H0.1 Director/Verifier должен быть независимым от worker implementation context хотя бы на уровне отдельной сессии/agent role и чистого verification checkout.

---

## 9. Autonomy ceiling

По умолчанию harness имеет ceiling:

```text
A3_INTEGRATE_CANDIDATE
```

Автоматически разрешено:

```text
fetch/audit/analyze
checkpoint selection
work-order generation
clean branch/worktree creation
implementation
tests
durable commit/push
passport updates
evidence recording
draft PR
checkpoint proposal
```

Human approval требуется для:

```text
runtime feature merge
TS0.4 activation after C22 integration
global architecture promotion
foundation ownership transfer
new global foundation
```

Control/docs-only merge может позднее получить whitelist, но только отдельным policy change.

---

## 10. Scheduler

Director выбирает не "интересную задачу", а eligible checkpoint.

Приоритет оценивается по:

```text
critical-path value
blocker removal
checkpoint closeness
parallelism gain
automation confidence
minus architectural risk
minus human dependency
minus stale/diverged branch cost
```

Однако до завершения H0.1 действует pilot override:

```text
max autonomous runtime workers = 1
target = H0_1_CLOSED_LOOP_C22_PILOT
```

G8.6/CH9.6 могут существовать параллельно как `HUMAN_OBSERVATION / WAITING_HUMAN`.

R3 analysis может идти параллельно, но не должен превращаться в autonomous architecture promotion.

Несколько runtime workers разрешаются только после H0.3 parallel scheduler checkpoint.

---

## 11. Escalation

Если worker дважды не закрывает один и тот же defect:

```text
worker model/context
      ↓
stronger model or Director takeover
```

Немедленная остановка/replan:

```text
unexpected scope expansion
architecture ownership ambiguity
new global Registry/Manager/Authority/Material/Transaction/Query foundation
critical PC0 RED
critical directional dependency hit
epoch invalidation requiring refresh
```

---

## 12. Human observation work orders

Manual graphical gates являются обычным типом work order:

```text
work_order_type: HUMAN_OBSERVATION
state: WAITING_HUMAN
```

Work order обязан содержать:

```text
exact checkout/head
exact launch command
observation checklist
screenshots/log paths
PASS/FAIL evidence format
continuation after result
```

Ожидание manual G/CH gate не блокирует другой eligible autonomous train.

---

## 13. Recovery drill

До H0.1 PASS требуется реальный recovery drill.

Новый чистый checkout/session должен выполнить будущий:

```powershell
.\CONTROL_DEVELOPMENT.ps1 -Resume
```

и получить без старого чата:

```text
active epoch
branch/head
last completed predicate
open blocker
next work order
verification commands
human approval requirement
```

Если это невозможно — `RECOVERY_DRILL_PASS` не выполнен.

---

## 14. Первый pilot

Ближайшая двойная цель:

```text
HARNESS:
H0.1 CLOSED-LOOP C22 PILOT

PROJECT:
C22 SOURCE_ACCEPTED_MERGE_READY
```

Почему C22:

```text
high Construction critical-path value
accepted legacy evidence exists
scope is bounded
current-main refresh is already required
most gates are automatic
architecture risk is lower than NX/R3
human merge gate gives safe stopping point
```

H0.1 обязан пройти:

```text
Project Epoch creation
C22 bounded Work Order
fresh current-main C22 branch
accepted capability transfer
production diff semantic equivalence
C22 focused PASS
C24 contracts PASS
C22 graphical PASS
full world/core regression PASS
exact tested heads
standard PC0 non-RED
directional PC0 without critical hits
critical overlap = 0
recovery drill PASS
draft PR
checkpoint proposal
```

STOP:

```text
before C22 runtime merge
before TS0.4
```

---

## 15. Expansion after H0.1

```text
H0.1 PASS
  ↓
H0.2 NX.C1 closed-loop pilot
  ↓
H0.3 parallel scheduler
  ↓
H1 multi-program autonomous development
```

Only H0.3 permits multiple autonomous runtime workers by default.

---

## 16. Canonical files

```text
config/control/harness/project-goals.v1.json
config/control/harness/checkpoint-catalog.v1.json
config/control/harness/harness-policy.v1.json
config/control/harness/scheduler-policy.v1.json
config/control/harness/work-order.schema.v1.json
config/control/harness/event.schema.v1.json
config/control/harness/project-epoch.schema.v1.json
```

Future executable entrypoint:

```text
CONTROL_DEVELOPMENT.ps1
scripts/harness/**
```

H0 scaffold implementation must conform to these canonical contracts rather than inventing a second state model.
