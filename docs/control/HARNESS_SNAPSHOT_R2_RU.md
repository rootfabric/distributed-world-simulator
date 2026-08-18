# Distributed World Simulator — Harness Snapshot R2

## 1. Назначение

Этот документ фиксирует второй исторический snapshot системы разработки/Harness проекта и делает его пригодным как исходную точку для будущего выделения универсальной Git-заготовки нового проекта.

Snapshot не заменяет `main`, не меняет runtime-семантику Distributed World Simulator и не создаёт новую ветку продуктовой разработки. Его задача — сохранить воспроизводимую точку состояния Harness вместе с происхождением и правилами извлечения.

## 2. Серия snapshot'ов

| Snapshot | Дата | Ветка | Exact head | Роль |
|---|---|---|---|---|
| HARNESS-SNAPSHOT-R1 | 2026-08-11 | `control/harness-development-protocol-r1` | `4b9e6c2c9428f59860368ccad6cf1a561f28206e` | Первый protocol snapshot: канонические Harness-контракты и правила автономной разработки |
| HARNESS-SNAPSHOT-R2 | 2026-08-18 | `control/harness-development-snapshot-r2` | snapshot metadata commit поверх source head | Второй snapshot: зрелый executable Harness + review/evidence + Project Control |

### R1 provenance

```text
snapshot id       HARNESS-SNAPSHOT-R1
branch            control/harness-development-protocol-r1
exact head        4b9e6c2c9428f59860368ccad6cf1a561f28206e
PR                #65 — H0: canonical restart-safe development harness protocol
merge commit      a578b2df4cd73bfd05379a81c574a7a5739b1030
```

R1 зафиксировал архитектурное ядро:

- Git как durable memory;
- Project Epoch;
- bounded Work Order;
- append-only execution events;
- checkpoint catalog;
- scheduler policy;
- Git-only recovery;
- запрет implementer self-acceptance;
- exact tested heads;
- human gates для merge/architecture promotion.

### Крупный промежуточный слой после R1

PR #67 / `control/harness-evidence-review-layer` добавил самостоятельный evidence-driven review layer:

```text
head         474c0552f2671d28dbfdff64a389ccd525364a5c
merge commit 790fd79f8055fefa19cf9d7263441fc9f4326ebd
```

Он добавил risk routing, Design Brief, Repair Doctrine, Evidence Map, независимого Reviewer, exact-head review freshness, post-build critique и Human Attention Queue.

## 3. Exact R2 source

R2 снят с exact состояния canonical `main`:

```text
source branch   main
source head     d9a1a3ca03016d6851a258ff93d5c260a86c5b4c
source tree     a5bf117c721605bbc8ab07ff7bcb8c7806405e23
captured at     2026-08-18T12:16:00+10:00
```

Исходный R1 head является прямым предком R2 source head. Между ними 307 коммитов; R2 — эволюция R1, а не альтернативная реализация.

Snapshot branch создаётся непосредственно от exact source head и поверх него содержит только snapshot metadata. Поэтому продуктовая истина R2 всегда однозначна: `main@d9a1a3ca03016d6851a258ff93d5c260a86c5b4c`.

## 4. Что появилось к R2

По сравнению с R1 система стала исполняемой и значительно жёстче fail-closed.

### 4.1 Executable Harness

Появились:

```text
CONTROL_DEVELOPMENT.ps1
scripts/harness/cli.py
scripts/harness/contracts.py
scripts/harness/checkpoint_planner.py
scripts/harness/epoch_validator.py
scripts/harness/event_reducer.py
scripts/harness/state_builder.py
scripts/harness/requirements.txt
```

Публичный control entry point поддерживает `-Status`, `-Plan`, `-Resume`. Execution state восстанавливается из Git и append-only ledger, а не из chat history.

### 4.2 Review / Evidence / Repair

Появились machine-readable контракты:

```text
config/control/harness/risk-policy.v1.json
config/control/harness/review-policy.v1.json
config/control/harness/repair-doctrine.v1.json
config/control/harness/evidence-map.schema.v1.json
config/control/harness/human-attention.schema.v1.json
```

Роли теперь явно разделяют `IMPLEMENTER`, `REVIEWER`, `VERIFIER`, `INTEGRATOR`, `PC0`, `DIRECTOR`, `HUMAN`.

### 4.3 Реальный durable execution ledger

`config/control/harness/executions/**` содержит реальные Project Epoch, Work Order, transition tables, append-only events, reviews, verifier evidence, audits, repair maps, critique и Evidence Maps.

### 4.4 Усиленный Project Control

К Harness добавились architecture compatibility, historical ownership compatibility, directional watches, reviewed-clearance fencing, cross-branch overlap и generation-specific safety guards.

### 4.5 Concurrency governance

До H0.3 по-прежнему действует максимум одного non-trivial runtime mutation worker, но review/verification-only работа может идти параллельно. Scheduler различает Harness pilot lane и product execution lane и умеет выдавать main-owned mutation lease.

## 5. Инварианты, которые должны пережить выделение шаблона

При создании отдельной заготовки проекта нельзя потерять следующие свойства:

1. Git остаётся единственной durable памятью execution state.
2. Chat history не требуется для `Resume`.
3. Main/default branch владеет целями, политиками, architecture/control truth.
4. Worker branches сообщают execution facts, но не переписывают глобальную истину.
5. Events append-only; derived state перестраивается reducer'ом.
6. Implementer не может сам принять свой checkpoint.
7. Review и runtime evidence привязаны к exact head.
8. Изменение runtime после review делает review stale.
9. Missing evidence не интерпретируется как PASS.
10. Failure фиксируется как `FIX_REQUIRED`, `BLOCKED`, `WAITING_HUMAN` или другой явный fail-closed state.
11. Main movement требует audit/refresh, а не молчаливого продолжения.
12. Architecture/ownership drift проверяется отдельно от unit/runtime tests.
13. Human gate остаётся явным для merge и высокорисковых архитектурных решений.

## 6. Как из R2 получить Git-заготовку нового проекта

R2 специально классифицирован на четыре слоя.

### A. Переносить как универсальное ядро

```text
CONTROL_DEVELOPMENT.ps1
scripts/harness/**
validation/harness/**
config/control/harness/event.schema.v1.json
config/control/harness/project-epoch.schema.v1.json
config/control/harness/evidence-map.schema.v1.json
config/control/harness/human-attention.schema.v1.json
config/control/harness/risk-policy.v1.json
config/control/harness/review-policy.v1.json
config/control/harness/repair-doctrine.v1.json
```

Также сохраняется сама event-sourced модель Work Order и exact-head review protocol.

### B. Переносить, но параметризовать под новый проект

```text
AGENTS.md
HARNESS_CONTROL.md
PROJECT_CONTROL.md
.github/workflows/project-control.yml
config/control/harness/harness-policy.v1.json
config/control/harness/work-order.schema.v1.json
config/control/project-control-policy.v1.json
scripts/control/project_control.py
scripts/control/project_control_core.py
scripts/control/project_control_architecture_compat.py
scripts/control/project_control_directional_watch.py
scripts/control/directional_watch_clearance.py
tests/harness/**
```

Здесь нужно убрать DWS-specific программы, пути, generation numbers, architecture owners и runtime predicates, сохранив общую fail-closed механику.

### C. В новом проекте создавать заново

```text
config/control/harness/project-goals.v1.json
config/control/harness/checkpoint-catalog.v1.json
config/control/harness/scheduler-policy.v1.json
config/control/project-program-registry.v1.json
config/control/architecture-ownership.v1.json
docs/control/CURRENT_PROJECT_FRONTIERS_RU.md
```

Эти файлы являются project model, а не универсальной Harness-реализацией.

### D. Не переносить в чистую заготовку

```text
config/control/harness/executions/**
config/control/branches/**
artifacts/**
DWS domain/runtime code
DWS domain tests
V0/NX/C22/ECO/MRPF-specific plans and checkpoints
исторические branch passports и project execution evidence
```

Исторические ledgers должны сохраняться в этом snapshot для provenance, но не должны попадать в новый пустой проект.

## 7. Рекомендуемый минимальный layout будущей заготовки

```text
AGENTS.md
CONTROL_DEVELOPMENT.ps1
HARNESS_CONTROL.md
PROJECT_CONTROL.md

.github/workflows/
    project-control.yml

config/control/
    project-control-policy.v1.json
    project-program-registry.v1.json
    architecture-ownership.v1.json
    harness/
        harness-policy.v1.json
        scheduler-policy.v1.json
        project-goals.v1.json
        checkpoint-catalog.v1.json
        work-order.schema.v1.json
        event.schema.v1.json
        project-epoch.schema.v1.json
        risk-policy.v1.json
        review-policy.v1.json
        repair-doctrine.v1.json
        evidence-map.schema.v1.json
        human-attention.schema.v1.json
        executions/

scripts/
    harness/
    control/

tests/
    harness/

validation/
    harness/

docs/control/
```

`executions/` в новой заготовке стартует пустым. Первый Project Epoch создаётся только после определения реальных project goals, checkpoint catalog, ownership и Project Control policy нового проекта.

## 8. Bootstrap порядок для нового проекта

1. Скопировать generic core из manifest R2.
2. Не переносить DWS execution history.
3. Определить реальные project goals нового проекта.
4. Определить checkpoint catalog.
5. Определить program registry и architecture ownership.
6. Настроить scheduler/concurrency policy.
7. Настроить Project Control workflow и project-specific checks.
8. Запустить Harness unit tests.
9. Проверить `CONTROL_DEVELOPMENT.ps1 -Status`, `-Plan`, `-Resume` на отсутствии active execution.
10. Только после этого создать первый Project Epoch и первый bounded Work Order.

## 9. Правило следующего snapshot

Следующий snapshot этой серии должен называться `HARNESS-SNAPSHOT-R3`, явно ссылаться на `HARNESS-SNAPSHOT-R2`, фиксировать exact source branch/head/tree и перечислять изменения относительно R2.

Нельзя переписывать R1 или R2 для отражения будущих изменений. История snapshot'ов append-only так же, как execution ledger Harness.

## 10. Статус

```text
HARNESS-SNAPSHOT-R1  HISTORICAL / PRESERVED
HARNESS-SNAPSHOT-R2  CURRENT SNAPSHOT
main                 CONTINUES DEVELOPMENT
snapshot branch      FROZEN REFERENCE, NOT PRODUCT DEVELOPMENT
```
