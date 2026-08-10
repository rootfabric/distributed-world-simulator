# Distributed World Simulator — Project Control Center

**Control plane:** `PC0-2026-08-10-R1`  
**Global architecture:** `GLOBAL-P0-2026-08-10-R2`  
**Canonical owner:** `main`

Это центральная точка для верхнеуровневого контроля всего проекта.

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

**Главное правило:** ветки сообщают локальные факты, но только `main` объявляет официальное состояние проекта и active frontier каждой программы.

## Что должно быть видно для каждой активной ветки

Dashboard обязан показывать не только имя ветки и commit, но и:

- что это за ветка;
- краткое описание;
- зачем она нужна;
- какой результат она должна получить;
- какую роль играет в общей программе;
- текущую стадию;
- статус стадии;
- что уже принято;
- что происходит сейчас;
- какой следующий этап;
- blockers;
- declared health GREEN / YELLOW / RED;
- actual Git divergence и validation freshness после запуска auditor.

Эти поля являются обязательной частью branch passport и central registry.

## Текущая зарегистрированная картина

| Program | Branch / mode | Что делает | Сейчас | Следом | Health |
|---|---|---|---|---|---|
| G | `feature/g7-semantic-field-fabric` | Semantic Field Fabric + visual proof | G7.4 candidate | G7 Full → G8 | YELLOW |
| T | `feature/t1a5-interactive-runtime-execution` | Executable Construction runtime | T1A.5 accepted, FIX1 required | FIX1 → T1A.6 | RED |
| TS | `feature/ts0-large-structural-visual-lab` | 10k/100k Construction scale evidence | TS0.1 candidate | TS0.1 accept → TS0.2 | YELLOW |
| CH | `feature/ch7-8-skinned-garment` | Character/garment presentation | CH7-8 active | focused acceptance | GREEN |
| Doctrine | `feature/world-building-doctrine` | Rules of interesting interconnected world simulation | active consolidation | evidence-driven updates | GREEN |
| NX | tracked foundation | Network realtime foundation | no PC0 frontier declared | declare before next NX acceptance | YELLOW |
| Matter | stable foundation | Mutable material/volume truth | MW10 stable | GM/composition later | GREEN |
| S1 | stable foundation | proposal-only distributed compute | stable | register when needed | GREEN |

Эта таблица — только human-readable snapshot central registry. **Фактический health всегда пересчитывается auditor-ом по Git refs, passports и validation.**

## Запуск контроля

Из любого актуального checkout:

```powershell
.\CONTROL_PROJECT.ps1
```

По умолчанию runner делает `git fetch origin --prune`, всегда читает central registry из `origin/main`, затем проверяет зарегистрированные активные ветки.

Без fetch:

```powershell
.\CONTROL_PROJECT.ps1 -NoFetch
```

Не падать процессом при RED, а только сформировать отчёт:

```powershell
.\CONTROL_PROJECT.ps1 -NoFailOnRed
```

Результаты:

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

Current project state:
  config/control/project-program-registry.v1.json   <-- MAIN ONLY OWNER

Branch-local facts:
  config/control/branches/<branch>.v1.json

Detailed control instructions:
  docs/control/PROJECT_CONTROL_PLANE_RU.md
```

## Stop rule

Если auditor показывает `RED`, следующий объявленный major stage блокируется, пока причина не закрыта или явно не пересмотрена в `main`.

`SOURCE_ACCEPTED` не означает автоматически `MAIN_INTEGRATED`, `COMPOSITION_VERIFIED`, `PRODUCTION_READY` или разрешение перейти на следующий stage.
