# Project Control Kernel — research extraction

**Branch:** `docs/project-control-kernel-r1`  
**Base:** `main @ 4a42c2fb6befb386f5c3eb48d9ba070745e25bbb`  
**Mode:** docs-only / research / portability  
**Runtime authorization:** none

Эта папка отделяет управляющую систему разработки от предметной архитектуры Distributed World Simulator.

Цель:

```text
понять существующий control plane
        ↓
оставить доказавшие ценность механизмы
        ↓
убрать duplicated writable state и лишнюю ceremony
        ↓
получить компактное переносимое ядро
```

## Документы

### `DWS_PROJECT_CONTROL_AUDIT_RU.md`

Аудит текущей системы DWS:

```text
PC0
branch passports
registry
ownership
standard + directional auditors
dashboard
AGENTS router
Harness
Epoch / Work Order / events
risk / review / Evidence Map
Human Attention
CURRENT PRIMARY resolver
```

Документ объясняет, что уже работает, где появился control bloat и какой migration path безопасен без вмешательства в активный H0.1 runtime epoch.

### `PROJECT_CONTROL_KERNEL_RU.md`

Независимая переносимая модель.

Главная формула:

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

## Источники эволюции, учтённые в extraction

```text
PR #57  PC0 main-owned project control plane
PR #65  restart-safe Harness protocol
PR #66  H0.0 scaffold gate
PR #67  evidence/review/human-attention layer
PR #87  CURRENT PRIMARY / EXECUTE_NOW / PREPARE_NOW project map
PR #88  H0.1 R7 fail-closed freshness-fence finding
PR #90  H0.1 R8 corrected exact implementation/review target
```

Также проверена механическая реализация:

```text
scripts/control/project_control.py
scripts/control/project_control_directional_watch.py
config/control/project-control-policy.v1.json
config/control/project-program-registry.v1.json
config/control/harness/work-order.schema.v1.json
config/control/harness/event.schema.v1.json
config/control/harness/project-epoch.schema.v1.json
config/control/harness/evidence-map.schema.v1.json
config/control/harness/risk-policy.v1.json
config/control/harness/review-policy.v1.json
```

## Ключевой вывод

Не нужен новый большой framework поверх PC0/Harness.

Нужна редукция к следующей модели:

```text
POLICY / OWNERSHIP
        ↓
MAIN PROJECT LEDGER
        ↓
BRANCH CARDS + optional ACTIVE TASKS
        ↓
REAL GIT + EVIDENCE
        ↓
ONE AUDITOR / RESOLVER
        ↓
GENERATED DASHBOARD
```

Основное правило против бюрократии:

```text
ONE FACT → ONE WRITABLE HOME
EVERY OTHER VIEW → DERIVED
```

## Что эта ветка не делает

Она не изменяет:

```text
PROJECT_CONTROL.md
CURRENT_PROJECT_FRONTIERS_RU.md
project-program-registry.v1.json
project-control-policy.v1.json
Harness contracts
checkpoint catalog
architecture ownership
runtime/domain code
```

Она также не авторизует merge, architecture promotion, новую runtime ветку или новый agent worker.

Следующий разумный эксперимент после безопасной control boundary — read-only shadow resolver, который строит компактный dashboard из существующих PC0/Harness данных и сравнивается с текущим control output до любых contract migrations.
