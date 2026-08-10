# Distributed World Simulator — Project Control Center

**Control plane:** `PC0-2026-08-10-R1`  
**Global architecture:** `GLOBAL-P0-2026-08-10-R2`  
**Canonical owner:** `main`

Это центральная точка верхнеуровневого контроля проекта. Быстро меняющееся состояние программ не дублируется здесь вручную: live dashboard строится из main-owned registry, branch passports, validation heads и реальных Git refs.

## Главное правило

```text
BRANCHES REPORT FACTS
MAIN DECLARES PROJECT STATE
AUDITOR CHECKS CONSISTENCY
GLOBAL ARCHITECTURE DEFINES WHAT IS ALLOWED
```

Оперативный active frontier берётся из:

```text
config/control/project-program-registry.v1.json
```

Поля `active_frontiers` внутри старого `GLOBAL-P0 R2` считаются advisory legacy state до следующей global architecture revision. Это отделяет быстро меняющееся движение веток от медленно меняющейся архитектурной конституции.

## Как читать проект

```text
GLOBAL architecture / rules
        ↓
main-owned Project Registry
        ↓
registered active branch passports
        ↓
validation + actual Git refs
        ↓
CONTROL_PROJECT.ps1
        ↓
artifacts/control/PROJECT_STATUS_RU.md
artifacts/control/project-control-report.json
```

## Что обязан показывать live dashboard

Для каждой зарегистрированной активной ветки:

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

Git reality
  actual branch head
  main-only / branch-only divergence
  findings emitted by the auditor
```

Поля validation/dependencies/ownership уже являются частью branch passport. PC0 R1 dashboard только делает их видимыми; новый schema или architecture revision для этого не нужен.

## Почему validation heads показываются отдельно

Нельзя считать `branch HEAD` автоматически проверенным runtime head. После успешного теста в ветку часто добавляются documentation/control commits, а иногда — новый runtime code.

Поэтому dashboard различает:

```text
tested_heads.runtime
  последний SHA, на котором проверялся runtime scope

tested_heads.focused
  SHA focused acceptance
tested_heads.full_regression
  SHA полного regression

runtime freshness
  сравнение tested_heads.runtime с runtime_paths после этого SHA
```

Если после tested runtime head изменился хотя бы один `runtime_paths`, auditor поднимает `RUNTIME_VALIDATION_STALE` независимо от текста progress note.

## Почему dependencies и ownership должны быть прямо в dashboard

Для параллельной разработки недостаточно знать только название этапа. Нужно сразу видеть:

- какие foundations ветка переиспользует;
- кто является их каноническим owner;
- какие watched dependencies могут сделать локальное evidence устаревшим;
- какие foundation concepts ветке запрещено присваивать себе;
- не меняют ли две активные ветки один runtime/contract path одновременно.

Это позволяет заметить архитектурное расхождение до merge, а не после появления второго Registry/Manager/Authority/Persistence/Interest слоя.

## Запуск контроля из main

```powershell
cd C:\Godot\<checkout>
git fetch origin --prune
.\CONTROL_PROJECT.ps1
```

По умолчанию `RED` возвращает exit code `2`.

Только посмотреть состояние:

```powershell
.\CONTROL_PROJECT.ps1 -NoFailOnRed
```

Без повторного fetch:

```powershell
.\CONTROL_PROJECT.ps1 -NoFetch -NoFailOnRed
```

## Запуск из active checkout

Feature-ветки используют bootstrap `CONTROL_PROJECT.ps1`, который получает auditor и registry из `origin/main`. Поэтому active branch не хранит независимую копию project-control truth и после `git fetch origin --prune` автоматически использует актуальный renderer dashboard.

## Результаты

```text
artifacts/control/PROJECT_STATUS_RU.md
artifacts/control/project-control-report.json
```

Markdown предназначен для быстрого human review. JSON содержит те же сведения в machine-readable виде, включая tested heads, freshness, dependencies и ownership claims.

## Когда запускать

Обязательно:

```text
перед началом следующего major stage
после major acceptance
после изменения global architecture
после появления нового Manager/Registry/Authority/Region/Transaction/Material/Scheduler foundation concept
после существенного изменения main
перед merge/composition
когда нужно понять текущее движение всего проекта
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

Branch-local facts:
  config/control/branches/<branch>.v1.json

Detailed control instructions:
  docs/control/PROJECT_CONTROL_PLANE_RU.md
```

## Stop rule

Если конкретная программа получает `RED`, её следующий объявленный major stage/acceptance блокируется, пока причина не закрыта или явно не пересмотрена в `main`.

`SOURCE_ACCEPTED` не означает автоматически `MAIN_INTEGRATED`, `COMPOSITION_VERIFIED`, `PRODUCTION_READY` или разрешение перейти на следующий stage.
