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
- что это за ветка;
- зачем она нужна;
- какой результат должна получить;
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
| G | `feature/g7-semantic-field-fabric` | Semantic Field Fabric + visual proof | G7.4 Fix2 focused PASS; full regression + manual visual pending | G7.4 accept → G7 Full → G8 | YELLOW |
| T | `feature/t1a7-runtime-recovery-interest-scale` | Construction runtime recovery + late interest + selective scale | T1A.7 architecture/reuse audit | T1A.7.1 recovery contract → interest/reconnect → selective scale | YELLOW |
| TS | `feature/ts0-large-structural-visual-lab` | 10k/100k Construction scale evidence | TS0.1 candidate/manual presentation review | TS0.1 accept → TS0.2 | YELLOW |
| CH | `feature/ch7-8-skinned-garment` | Character/garment presentation | CH7-8 active | focused acceptance | GREEN declared / auditor may raise YELLOW until fresh validation is registered |
| Doctrine | `feature/world-building-doctrine` | Rules of interesting interconnected world simulation | active consolidation | evidence-driven updates | GREEN declared / dependency sync may raise YELLOW |
| NX | tracked foundation | Network realtime foundation | no single PC0 frontier declared | declare before next NX acceptance | YELLOW |
| Matter | stable foundation | Mutable material/volume truth | MW10 stable | GM/composition later | GREEN |
| S1 | stable foundation | proposal-only distributed compute | stable | register when needed | GREEN |

Это human-readable snapshot central registry. **Фактический health всегда пересчитывается auditor-ом.**

## T: T1A.6 закрыт, T1A.7 открыт

PC0 blocker по T1A.5 transactional effects закрыт реальным Windows revalidation:

```text
C5B runtime contracts                  PASS 32
T1A.5 interactive runtime              PASS 67
T1A.5 transactional runtime effects    PASS 36
T1A.6 dedicated + 2 clients            PASS 25 / 0 failures
full world/core regression             6 PASS / 0 FAIL
NX4 final marker                       PASS
```

T1A.6 теперь имеет:

```text
SOURCE_ACCEPTED       true
MAIN_INTEGRATED       false
COMPOSITION_VERIFIED  true
PRODUCTION_READY      false
```

Новый frontier:

```text
feature/t1a7-runtime-recovery-interest-scale
```

T1A.7 начат не с нового runtime-кода, а с reuse/ownership audit. Уже проверены два важных существующих pattern-а:

```text
MW7 Matter interest:
  revisioned subscription
  active/pending interest
  reconnect/session fence
  bounded replay
  projection hash / ack
  regional snapshot fallback
  irrelevant changes filtered

Matter persistence:
  repository/coordinator split
  checkpoint identity validation
  validate-before-restore
  backup before restore
  rollback on partial restore failure
```

Construction может использовать эти architectural patterns и существующие owner boundaries, но не имеет права создавать собственные global interest identity, persistence foundation, authority registry или permanent spatial identity.

Текущий T blocker — только архитектурный convergence gate:

```text
T1A7_ARCHITECTURE_REUSE_AUDIT_PENDING
```

Это YELLOW, а не RED: разработка T1A.7 может продолжаться после явного выбора reuse boundary, но major acceptance нельзя проводить с неразрешённым foundation ownership.

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

Active branches используют bootstrap `CONTROL_PROJECT.ps1`, который читает auditor и registry из `origin/main`. Поэтому feature-ветка не должна хранить независимую копию project-control truth.

## Результаты

```text
artifacts/control/PROJECT_STATUS_RU.md
artifacts/control/project-control-report.json
```

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
