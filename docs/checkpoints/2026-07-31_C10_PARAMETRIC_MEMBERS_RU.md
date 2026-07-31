# Checkpoint C10 — Parametric Members

**Дата:** 2026-07-31
**Статус:** IMPLEMENTED CANDIDATE
**База:** принятый C9, C8 commit `6ec6fdb`
**Рекомендуемая ветка:** `feature/c10-parametric-members`

## Цель

Добавить строительные элементы, у которых геометрия, масса и материальный расход вычисляются из строгих параметров, а не зашиваются в prefab или mesh. C10 охватывает балки, панели, трубы, кабели и многослойные стены и связывает их с принятыми C3, C5, C8 и C9 контрактами.

## Архитектурная граница

```text
versioned material definitions
+ versioned parametric member definition
+ parameter overrides
        ↓ deterministic compiler
ParametricMemberInstance
├── canonical parameter values
├── geometry metrics
├── per-material volume/mass
├── stock unit requirements
├── item identity
└── immutable checksum/provenance
        ↓
normal ItemInstance projection
        ├── C8 fabrication recipe/output
        ├── C3 BuildPlan source
        ├── C5 semantic capability
        └── C9 split/repair lifecycle
```

Mesh, collision и renderer остаются производными представлениями. Каноническое состояние C10 — JSON-safe definition/instance DTO и обычный item-backed identity.

## Поддержанные семейства

| Kind | Параметры | Расчёт |
|---|---|---|
| `BEAM` | length, width, height | rectangular prism |
| `PANEL` | length, width, thickness | thin rectangular prism |
| `PIPE` | length, outer diameter, wall thickness | hollow cylinder |
| `CABLE` | length, diameter | solid cylinder |
| `LAYERED_WALL` | length, height + ordered layers | сумма layer volumes |

Все метрики канонизируются с точностью 9 десятичных знаков. `int` и integral `float` дают одинаковый canonical JSON.

## Материалы и расход

`ConstructionParametricMaterial` задаёт:

- density `kg/m³`;
- stock definition;
- массу одной stock unit;
- свойства материала;
- checksum.

Компилятор выводит для каждого материала:

```text
volume_m3
mass_kg
stock_definition_id
stock_units = ceil(mass / stock_unit_mass)
```

Для layered wall повторяющиеся material layers агрегируются по material identity. Instance отвергается, если сумма material usage не совпадает с общей массой или объёмом.

## Versioned definitions и catalog

`ConstructionParametricMemberDefinition` содержит exact parameter set, defaults, minimum/maximum limits, material binding или ordered layers, fabrication metadata и checksum.

Catalog обеспечивает:

- immutable material publication;
- последовательные definition versions;
- exact replay без generation increment;
- conflict/gap rejection;
- latest-version lookup;
- transactional state load и persistence.

Созданный instance pin-ит definition ID, version и checksum и не меняется после публикации новой версии.

## Item Graph и BuildPlan

`ConstructionParametricProjectionFactory` создаёт обычный `ConstructionItemProjection` с компонентом:

```text
components.parametric_member = ParametricMemberInstance
```

Из того же instance строится `ConstructionPartRecord`; mass и geometry provenance переходят в semantic part metadata. Изготовленная C8-балка успешно используется как единственный source item обычного C3 BuildPlan без альтернативного registry или prefab identity.

## C8 Fabrication

`ConstructionParametricFabricationCompiler` преобразует instance в versioned C8 recipe:

```text
material_usage
→ stock input requirements
→ authoritative reserve/consume
→ fabricated output ItemInstance
→ fabrication_origin + parametric_member
```

Контрольный S355 beam расходует рассчитанное число `steel_stock` units, создаётся в output container станка и сохраняет исходный parametric checksum.

## Capabilities

C10 компилирует C5 descriptors:

```text
BEAM         → LOAD_BEARING_MEMBER
PANEL        → STRUCTURAL_PANEL
PIPE         → FLUID_CONDUIT
CABLE        → SIGNAL_CONDUIT
LAYERED_WALL → ENCLOSURE_ASSEMBLY
```

Capability pin-ит concrete part ID и содержит geometry, mass и material usage. Это позволяет агентам и последующим structural/utility слоям работать по свойствам, а не по prefab name.

## Segmentation и repair

`ConstructionParametricSegmenter` режет member вдоль `length_m` на pinned child member/item identities.

Инварианты:

- offsets строго возрастают и лежат внутри parent length;
- segments образуют непрерывное покрытие без gap/overlap;
- definition checksum и member kind сохраняются;
- масса, объём и расход каждого материала сохраняются;
- exact int/float replay создаёт тот же plan checksum.

`ConstructionParametricRepairPlan` pin-ит parent instance и checksums всех сегментов. Parent восстанавливается только при наличии всех реальных segment identities; порядок подачи сегментов не влияет на результат.

## C9 совместимость

Контрольная parametric beam встроена в C9 bridge-arm. Damage transaction переносит её в split child aggregate, не меняя parametric checksum. Repair возвращает тот же item ID в исходный aggregate и восстанавливает исходные mass/geometry provenance.

## Focused проверки

```text
C10 contracts:    PASS — 155 assertions
C10 integration:  PASS — 84 assertions
C10 total:        PASS — 239 assertions
Editor parse:     PASS
```

Локальная совместимость:

```text
C1:  PASS — 66 assertions
C2A: PASS — 137 assertions
C3:  PASS — 194 assertions
C4:  PASS — 268 assertions
C5:  PASS — 204 assertions
C6:  PASS — 218 assertions
C7:  PASS — 225 assertions
C8:  PASS — 221 assertions
C9:  PASS — 204 assertions
```

Локальная сумма C1+C2A+C3+C4+C5+C6+C7+C8+C9+C10: **1976 assertions**.

Полный C2B, Network N0–M4, world regression и main-scene CLI должны быть повторены на полном checkout. Изолированный snapshot не содержит полного production item-domain dependency tree для C2B integration.

## Gate принятия

```text
C1–C9 compatibility PASS
C10 focused PASS — 239 assertions
C2B PASS — 258 assertions
Network N0–M4 PASS
World regression PASS — 121/121 tests, 124 steps
Main-scene CLI PASS — 6/6
git diff --check PASS
C10 manifest unique and complete
```

## За границей C10

- runtime mesh/collision generation;
- local holes, bevels, CSG/SDF edits — C11;
- structural stress solver and buckling;
- thermal expansion and pressure simulation;
- automatic nesting/cut optimisation across stock sheets;
- multiplayer parameter-edit acceptance.
