# Checkpoint C9 — Damage, Split, Repair

**Дата:** 2026-07-31
**Статус:** ACCEPTED
**База:** C8 @ `6ec6fdb`
**Рекомендуемая ветка:** `feature/c9-damage-split-repair`

## Цель

Сделать повреждение конструкций частью той же authoritative модели, что parts, bonds и Item Graph: разрушать связи, детерминированно вычислять связные компоненты, создавать новые aggregates для крупных обломков, возвращать мелкие части в мир или контейнер как salvage и собирать конструкцию обратно из тех же реальных `ItemInstance`.

## Архитектурная граница

```text
DamageRequest pinned to ConstructSnapshot checksum
        ↓
apply part conditions + bond states
        ↓ deterministic connected components
retained component | split constructs | salvage items
        ↓
one multi-aggregate transaction
├── UPDATE source ConstructSnapshot
├── CREATE child ConstructSnapshot(s)
├── UPDATE item relations/conditions
├── CREATE split root item(s)
└── shared operation ledger + M0 batch
        ↓
RepairPlan pinned to original snapshot
        ↓
one inverse multi-aggregate transaction
├── UPDATE source construct
├── DELETE temporary child constructs
├── DELETE split root items
├── REATTACH real parts
└── restore original bonds and OPERATIONAL state
```

C9 не создаёт копии частей. Все retained, split и salvage outcomes используют исходные item identities. Repair возвращает именно эти identities.

## Контракты

- `ConstructionDamageRequest` закрепляет source checksum, retained part, broken/degraded bonds, part conditions, split identities и salvage policy;
- `ConstructionDamageComponent` описывает канонический outcome `RETAINED`, `SPLIT_CONSTRUCT` или `SALVAGE`;
- `ConstructionDamageTransactionPlan` содержит несколько construct mutations и item mutations в одной атомарной границе;
- `ConstructionRepairPlan` закрепляет original snapshot, требуемые item IDs, split construct/root IDs и checksum;
- `ConstructionDamageRecord` и history store поддерживают exact replay, conflict, mark repaired и transactional persistence;
- `ConstructionRepairGhostState` показывает AVAILABLE/MISSING parts и готовность ремонта.

## Split algorithm

1. Применяются новые conditions частей и состояния bonds.
2. `BROKEN` bonds и `DESTROYED` parts исключаются из графа связности.
3. Компонента с `retained_part_id` остаётся исходным aggregate.
4. Компоненты размером не меньше `minimum_split_parts` получают заранее закреплённые construct/root IDs.
5. Меньшие компоненты переводятся в salvage relation.
6. Списки components, item mutations и construct mutations сортируются канонически.

## Authoritative transaction

C2A расширен purposes:

```text
APPLY_CONSTRUCTION_DAMAGE
REBIND_SPLIT_PART
SALVAGE_CONSTRUCTION_PART
REPAIR_CONSTRUCTION_PART
```

C2B adapter применяет C9 через общий candidate/validate/commit path. M0 translator строит batch с Item Graph, operation ledger и каждой затронутой construct aggregate row. Ошибка до commit не оставляет частичного split.

## Replay и recovery

Source snapshot хранит rebuildable damage metadata:

```text
damage_request_checksum
damage_components
damage_salvage_item_ids
damage_split_construct_ids
damage_repair_plan
```

Поэтому exact process replay после commit возвращает тот же outcome и repair plan, не перепланируя против уже изменённого snapshot. Repair replay аналогично возвращает terminal result. Payload conflict с тем же operation ID отклоняется.

## Контрольный объект

Шестикомпонентный bridge-arm:

```text
anchor — core — joint — arm — tool
             └── sensor
```

Damage ломает `joint—arm` и `core—sensor`:

```text
anchor/core/joint → retained source
arm/tool          → child construct
sensor            → salvage item
```

Repair удаляет child root, возвращает arm/tool/sensor, восстанавливает 6 parts, 5 bonds и `OPERATIONAL` state.

## Локальные проверки

```text
C1:              PASS — 66 assertions
C2A:             PASS — 137 assertions
C3:              PASS — 194 assertions
C4:              PASS — 268 assertions
C5:              PASS — 204 assertions
C6:              PASS — 218 assertions
C7:              PASS — 225 assertions
C8:              PASS — 221 assertions
C9 contracts:    PASS — 96 assertions
C9 integration:  PASS — 108 assertions
C9 total:        PASS — 204 assertions
Editor parse:    PASS
```

Локально проверенная сумма C1+C2A+C3+C4+C5+C6+C7+C8+C9: **1737 assertions**.

Production C2B scripts проходят Godot parse, а multi-aggregate M0 batch покрыт contract-test. Полный C2B focused, Network N0–M4, world regression и main-scene CLI должны быть повторены на полном checkout.

## Gate принятия

```text
C1/C2A/C2B/C3/C4/C5/C6/C7/C8 compatibility PASS
C9 focused PASS — 204 assertions
Network N0–M4 PASS
World regression PASS — 119/119 tests, 122 steps
Main-scene CLI PASS — 6/6
git diff --check PASS
```

## За границей C9

- физическое образование debris bodies и импульс разрушения;
- progressive fracture по stress/temperature;
- сетевой damage command endpoint и permissions;
- visual repair animation;
- автоматическое назначение новых spatial authorities;
- parametric material members — C10.


## Внешняя приёмка

```text
branch:            feature/c9-damage-split-repair
SHA-256:           1db35602564d6a3f77cbd7b49770839e36c7705c7e6ef40f33c073f20e4582fb
C9 contracts:      PASS — 96 assertions
C9 integration:    PASS — 108 assertions
C9 total:          PASS — 204 assertions
C1–C8:             PASS
C2B:               PASS — 258 assertions
Network N0–M4:     PASS
World regression:  PASS — 119/119 tests, 122 steps
Main-scene CLI:    PASS — 6/6
git diff --check:  PASS
manifest:          46/46 unique
```

C9 принят как база C10.
