# PC0 — Project Control Plane

**Control revision:** `PC0-2026-08-10-R1`  
**Architecture revision:** `GLOBAL-P0-2026-08-10-R2`  
**Canonical owner:** `main`

## 1. Назначение

Project Control Plane нужен для ответа в любой момент на четыре вопроса:

```text
1. Какие программы и ветки сейчас реально активны?
2. Что каждая ветка делает, зачем она нужна и на какой стадии находится?
3. Не разошлись ли ветки с main, зависимостями, validation или global architecture?
4. Нужно ли продолжать локальную разработку, делать convergence review или остановиться для global correction?
```

PC0 реализует уже существующий `P0_PROGRAM_LEDGER`; поэтому его собственная revision меняется независимо от GLOBAL-P0, пока world architecture не меняется.

## 2. Разделение ответственности

```text
GLOBAL ROADMAP
    архитектурная конституция; меняется редко

PROJECT REGISTRY
    оперативное состояние программ; меняется часто

BRANCH PASSPORT
    локальные факты конкретной ветки

VALIDATION
    доказательство тестов/checkpoint

AUDITOR
    сверяет Git + registry + passport + validation

DASHBOARD
    человекочитаемая сводка
```

Только `main` изменяет официальный `project-program-registry.v1.json`.

Рабочая ветка может изменить только свой паспорт и свои domain files. Самостоятельное объявление себя новым global frontier не считается принятым до обновления registry в `main`.

## 3. Обязательный branch passport

Каждая активная или долговременная experimental/fix ветка обязана иметь уникальный файл:

```text
config/control/branches/<normalized-branch-name>.v1.json
```

Нельзя использовать один общий `branch-manifest.json`, потому что это создаст постоянные merge conflicts между параллельными линиями.

Passport обязан отвечать на вопрос пользователя без чтения кода:

```text
Что это за ветка?
Зачем она нужна?
Что должна закончить/доказать?
Какую роль играет в программе?
Где она сейчас?
Что уже принято?
Что происходит сейчас?
Что будет следующим?
Что её блокирует?
```

Обязательные descriptive поля:

```text
short_description
purpose
expected_outcome
current_stage
stage_status
progress_note
last_accepted_checkpoint
next_stage
blockers
health_declared
```

Обязательные control поля:

```text
branch
program
role
parent_branch_or_checkpoint
base_commit
architecture_revision
control_plane_revision
dependencies
owned_paths
watched_paths
critical_watched_paths
runtime_paths
validation_paths
tested_heads
ownership_claims
forbidden_foundation_ownership
```

## 4. Branch lifecycle

```text
PLANNED
   ↓
ACTIVE
   ↓
IMPLEMENTED_CANDIDATE
   ↓
FIX_REQUIRED ─────┐
   ↓              │
ACCEPTED <────────┘
   ↓
SUPERSEDED
   ↓
FROZEN
```

`BLOCKED` оформляется через `blockers` и health `RED`, а не стирает исторический acceptance предыдущего checkpoint.

## 5. Health

### GREEN

Работа может продолжаться. Нет известного blocking divergence.

### YELLOW

Работа может продолжаться, но до следующего major acceptance нужен convergence/control review. Типичные причины:

```text
manual graphical acceptance pending
main изменил watched dependency
branch далеко ушла по ancestry
metadata/passport требует синхронизации
non-critical overlap двух веток
```

### RED

Следующий major stage запрещён до исправления:

```text
architecture revision mismatch
runtime changes newer than tested runtime head
critical dependency drift
один production/contract file одновременно меняют две active branches
unregistered foundation ownership
unaccepted required parent
declared blocker of next stage
```

## 6. Watch model

`owned_paths` — область, которую ветка ожидаемо меняет.

`watched_paths` — зависимости, изменения которых в `main` требуют review.

`critical_watched_paths` — зависимости, изменения которых требуют blocking review до следующего acceptance.

`runtime_paths` — файлы, изменение которых после `tested_heads.runtime` делает runtime validation stale.

Пример:

```text
T owns:
  scripts/construction/behavior/**
  scripts/labs/t1/**

T watches:
  scripts/items/**
  scripts/construction/authoritative/**
  scripts/network/contracts/**

T critical watches:
  scripts/construction/authoritative/**
  scripts/items/services/item_operation_ledger.gd
```

## 7. Tested-head rule

Самая важная механическая проверка:

```text
runtime tested at A
        ↓
runtime file changed at B
        ↓
current branch head = C

=> VALIDATION STALE / RED
```

Metadata-only commits после runtime-tested head допустимы, если они не затронули `runtime_paths`.

## 8. Cross-branch overlap

Auditor сравнивает активные ветки попарно.

```text
same runtime/contract file touched by G and T -> RED
same docs/validation file -> YELLOW
same control-plane bootstrap files -> ignored
```

Это не заменяет semantic review, но рано показывает места, где две ветки начинают независимо переделывать один foundation.

## 9. Ownership control

`architecture-ownership.v1.json` — центральная ownership matrix.

Branch passport обязан перечислить `ownership_claims` и `forbidden_foundation_ownership`.

Если T/G/TS/CH пытаются стать владельцем `WorldAddress`, global material registry, authority registry, WorldTransaction coordinator, global persistence или scheduler foundation — stage останавливается и вопрос возвращается в `main`.

## 10. Frontier rule

Одна программа имеет один primary frontier.

Разрешён parallel track только если он зарегистрирован в main.

Пример:

```text
Construction
    PRIMARY:  T composition
    PARALLEL: TS scale/visual evidence
```

Случайная долговременная ветка без registry/passport должна рассматриваться как untracked и не может получить formal acceptance.

## 11. Convergence rule

Обязательный audit:

```text
major checkpoint accepted
        ↓
CONTROL_PROJECT.ps1
        ↓
GREEN/YELLOW/RED
        ↓
если GREEN -> next stage
если YELLOW -> review + explicit disposition
если RED -> fix/global correction
```

Нельзя проходить два major acceptance подряд без промежуточного control audit.

## 12. Global correction rule

Если ветка обнаруживает необходимость нового общего foundation:

```text
branch discovers need
        ↓
branch marks GLOBAL_DECISION_REQUIRED / RED
        ↓
main updates global architecture
        ↓
GLOBAL-P0 revision bump only if architecture changed
        ↓
relevant frontiers synchronize
        ↓
branch resumes
```

Обычный переход `G7.3 -> G7.4` или `T1A.5 -> FIX1` не требует GLOBAL-P0 bump, если ownership/invariants не меняются. Меняется project registry generation.

## 13. Как запускать

```powershell
.\CONTROL_PROJECT.ps1
```

Полезные варианты:

```powershell
.\CONTROL_PROJECT.ps1 -NoFetch
.\CONTROL_PROJECT.ps1 -NoFailOnRed
```

Output:

```text
artifacts/control/PROJECT_STATUS_RU.md
artifacts/control/project-control-report.json
```

Auditor всегда пытается читать central registry/policy/ownership из `origin/main`, независимо от текущего checkout.

## 14. Как использовать с ChatGPT на верхнем уровне

Запрос пользователя:

```text
проверь развитие проекта
```

Правильный порядок:

```text
1. inspect main Project Control registry
2. inspect active branch passports
3. compare actual branch refs and divergence
4. inspect generated/validation evidence for YELLOW/RED only
5. report architecture drift, dependency drift, stale validation, cross-branch overlap
6. update main registry when frontier officially moves
7. synchronize only common control-plane contract changes where needed
```

То есть глобальный аудит больше не начинается с ручного поиска сотен commits.

## 15. Первый PC0 monitored set

Generation 1 детально контролирует active branches:

```text
G
T
TS
CH
DOCTRINE
```

А также отображает stable/tracked programs:

```text
NX
MATTER
S1
```

При возобновлении активной разработки NX/Matter/S1 сначала объявляется конкретный frontier в `main`, затем создаётся branch passport.
