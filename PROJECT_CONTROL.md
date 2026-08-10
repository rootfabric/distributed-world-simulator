# Distributed World Simulator — Project Control Center

**Control plane:** `PC0-2026-08-10-R1`  
**Global architecture:** `GLOBAL-P0-2026-08-10-R2`  
**Canonical owner:** `main`

Это центральная точка для верхнеуровневого контроля всего проекта.

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

Поля `active_frontiers` внутри старого `GLOBAL-P0 R2` считаются advisory legacy state до следующей global architecture revision. Это специально отделяет быстро меняющееся движение веток от медленно меняющейся архитектурной конституции.

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

## Что видно для каждой активной ветки

Dashboard обязан показывать:

- имя и роль ветки;
- **что это за ветка**;
- **зачем она нужна**;
- **какой результат должна получить**;
- текущую стадию и stage status;
- последний принятый checkpoint;
- что происходит прямо сейчас;
- следующий этап;
- blockers;
- declared health;
- actual Git head/divergence;
- dependency drift;
- validation freshness;
- cross-branch overlap.

Эти descriptive поля обязательны и в central registry, и в branch passport. Auditor сверяет их между собой.

## Текущая зарегистрированная картина

| Program | Branch / mode | Что делает | Сейчас | Следом | Health |
|---|---|---|---|---|---|
| G | `feature/g7-semantic-field-fabric` | Semantic Field Fabric + visual proof | G7.4 candidate | G7 Full → G8 | YELLOW |
| T | `feature/t1a6-runtime-presentation-multiplayer-binding` | Runtime presentation + multiplayer binding | focused PASS, full regression pending; inherited T1A.5 transactional gap remains | FIX1 + full regression → T1A.6 accept → T1A.7 | RED |
| TS | `feature/ts0-large-structural-visual-lab` | 10k/100k Construction scale evidence | TS0.1 candidate/manual presentation review | TS0.1 accept → TS0.2 | YELLOW |
| CH | `feature/ch7-8-skinned-garment` | Character/garment presentation | CH7-8 active | focused acceptance | GREEN declared / auditor may raise YELLOW until fresh validation is registered |
| Doctrine | `feature/world-building-doctrine` | Rules of interesting interconnected world simulation | active consolidation | evidence-driven updates | GREEN declared / dependency sync may raise YELLOW |
| NX | tracked foundation | Network realtime foundation | no single PC0 frontier declared | declare before next NX acceptance | YELLOW |
| Matter | stable foundation | Mutable material/volume truth | MW10 stable | GM/composition later | GREEN |
| S1 | stable foundation | proposal-only distributed compute | stable | register when needed | GREEN |

Это human-readable snapshot central registry. **Фактический health всегда пересчитывается auditor-ом.**

## Почему T сейчас RED

PC0 фиксирует реальное движение, даже если оно опередило архитектурную коррекцию:

```text
T1A.5 functional acceptance
        ↓
architecture audit finds transactional side-effect gap
        ↓
T1A.6 branch already exists and focused multiplayer gate passes
        ↓
PC0 records actual T1A.6 as frontier
        ↓
T1A.6 acceptance remains BLOCKED
until T1A.5 transactional-effects FIX1 + full regression are closed
```

То есть контроль не переписывает историю и не скрывает уже выполненную работу; он показывает, что следующий formal acceptance нельзя считать безопасным.

## Запуск контроля из main

```powershell
cd C:\Godot\<checkout>
git fetch origin --prune
.\CONTROL_PROJECT.ps1
```

По умолчанию `RED` возвращает exit code `2`, что удобно как локальный acceptance/convergence gate.

Только посмотреть состояние, не падать по RED:

```powershell
.\CONTROL_PROJECT.ps1 -NoFailOnRed
```

Без повторного fetch:

```powershell
.\CONTROL_PROJECT.ps1 -NoFetch -NoFailOnRed
```

## Запуск из G/T/TS/CH/Doctrine checkout

В active branches есть маленький `CONTROL_PROJECT.ps1` bootstrap. Он не хранит собственную копию логики контроля, а делает:

```text
git fetch origin
        ↓
git show origin/main:scripts/control/project_control.py
        ↓
temporary local auditor
        ↓
reads registry/policy from origin/main
        ↓
audit all registered branches
```

Поэтому одна старая feature-ветка не может незаметно продолжать пользоваться старой control policy.

## Результаты

```text
artifacts/control/PROJECT_STATUS_RU.md
artifacts/control/project-control-report.json
```

`PROJECT_STATUS_RU.md` содержит общую таблицу динамики и отдельную карточку каждой программы с описанием, purpose, expected outcome, current progress, blockers и Git findings.

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
