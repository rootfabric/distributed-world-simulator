# C19 — Agent Construction and Automation API

**Статус:** IMPLEMENTED CANDIDATE
**База:** принятый C18 Streaming, LOD and Dormant Constructs
**Рекомендуемая ветка:** `feature/c19-agent-construction-automation-api`

## Цель

Дать AI-агенту и автоматизированному gameplay-процессу единый семантический API, который превращает цель высокого уровня в проверяемый BOM, последовательность работ и реальные authoritative команды. C19 не создаёт второй строительный домен и не позволяет агенту напрямую менять Item Graph или `ConstructSnapshot`.

```text
AgentGoal
→ deterministic planner
→ BOM + fabrication/procurement decisions
→ reservation batch
→ work queue
→ C8 fabrication / logistics
→ C12 command
→ C17 owner routing
→ authoritative C3/C9 process
→ outcome verification
```

## Поддержанные цели

- `BUILD_COMPOSITE` — создание C4 composite через реальный C3 BuildPlan;
- `REPAIR_CONSTRUCT` — восстановление по C9 RepairPlan и точным item identities;
- `SALVAGE_CONSTRUCT` — применение C9 DamageRequest/salvage policy.

## Основные инварианты

1. BOM ссылается на конкретные `ItemProjection`, recipe checksums и output item IDs.
2. Недостающая часть может быть изготовлена через C8 recipe; synthetic projection используется только как заранее назначенная identity будущего authoritative output.
3. Tools, workspaces, items и budget резервируются одной атомарной batch-операцией.
4. Один operation ID имеет один terminal result; failed reservation также не может позднее превратиться в другой результат.
5. Build, repair и salvage выполняются только через валидные C12 команды, обёрнутые C17 distributed route.
6. Executor не получает прямой доступ к C3/C9/C11 process или Item Graph adapter.
7. Work queue хранит checksum шага и receipt каждого terminal результата.
8. Persistence сохраняет goals, plans, queue, reservations и terminal submissions; restart не повторяет fabrication или domain commit.

## Реализованный vertical slice

### Build

Для пользовательского C4-стола агент:

- находит доступные реальные детали и материалы;
- обнаруживает отсутствующую structural leg;
- выбирает C8 recipe для `wood_beam`;
- резервирует inventory, raw stock, tool, workspace и budget;
- изготавливает один новый `ItemInstance`;
- доставляет все source items;
- регистрирует C3 BuildPlan;
- выполняет три stage-команды через C12/C17;
- проверяет итоговый semantic outcome.

### Repair

- C9 RepairPlan задаёт точный набор исходных item IDs;
- BOM показывает AVAILABLE/MISSING для каждой детали;
- при отсутствии части план блокируется или переходит в procurement;
- готовый plan создаёт C12 `APPLY_REPAIR` и маршрутизируется к C17 owner.

### Salvage

- C9 DamageRequest проверяется до постановки работы;
- tools/workspace резервируются;
- C12 `APPLY_DAMAGE` выполняется через owner-server;
- итог подтверждается verifier-шагом.

## Граница этапа

C19 не реализует рынок поставщиков, транспортный pathfinding, оплату подрядчиков или распределённую производственную экономику. Эти функции относятся к C20. Procurement в C19 является формальным unresolved BOM mode.

## Локальная проверка

```text
C19 contracts:    PASS — 97 assertions
C19 integration:  PASS — 57 assertions
C19 total:        PASS — 154 assertions
Editor parse:     PASS
```

Повторно проверенная локальная линия C1–C8 и C10–C19: **3087 assertions, PASS**. Полные C2B/C9/Network/world проверки остаются внешним acceptance gate.

## Ожидаемый внешний профиль

```text
C19 focused:      PASS — 154 assertions
C2B regression:   PASS — 258 assertions
C9 regression:    PASS — 204 assertions
C17/C18:          PASS
Network N0–M4:    PASS
World regression: PASS — 139/139 тестов, 142 шага
Main-scene CLI:   PASS — 6/6
git diff --check: PASS
```
