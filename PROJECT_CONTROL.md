# Distributed World Simulator — Project Control Center

**Control plane:** `PC0-2026-08-10-R1`  
**Global architecture:** `GLOBAL-P0-2026-08-10-R2`  
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

## Как читать проект

```text
GLOBAL architecture / rules
        ↓
main-owned Project Registry
        ↓
registered branch passports
        ↓
validation + actual Git refs
        ↓
standard PC0 auditor
        +
directional watched-dependency auditor
        ↓
CONTROL_PROJECT.ps1
        ↓
artifacts/control/PROJECT_STATUS_RU.md
artifacts/control/project-control-report.json
artifacts/control/DIRECTIONAL_WATCH_STATUS_RU.md
artifacts/control/directional-watch-report.json
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
```

Если после tested runtime head изменился хотя бы один `runtime_paths`, auditor поднимает `RUNTIME_VALIDATION_STALE` независимо от текста progress note.

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

`SOURCE_ACCEPTED` не означает автоматически `MAIN_INTEGRATED`, `COMPOSITION_VERIFIED`, `PRODUCTION_READY` или разрешение перейти на следующий stage.
