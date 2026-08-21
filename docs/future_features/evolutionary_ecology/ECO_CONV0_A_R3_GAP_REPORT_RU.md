# ECO.CONV0-A — R3 Global Alignment Gap Report

Статус: `RESEARCH DESIGN REVIEW COMPLETE / GLOBAL GAPS IDENTIFIED / NO RUNTIME CHANGE`.

## Контекст

ECO.PH закрыт как research track. Следующий вопрос — не как встроить ecology в runtime прямо сейчас, а какие canonical foundations должны существовать, чтобы future ecology integration не создала второй World Query, Spatial Fabric, Population Manager, Material Registry, Lifecycle Manager или Scheduler.

Fresh global facts при review:

- canonical `main`: `eefd75fa3badec10c6e7db959e2a3992dba30f0e`, normal merge H0.1 R8 / C22 PR #90;
- canonical architecture пока `GLOBAL-P0-2026-08-10-R2`;
- GLOBAL-P0 R3 остаётся candidate и требует exact-current-main refresh + human promotion;
- R3 candidate config blob: `0a7b5b322f9d928fd6ec295753b9b0e18d2fc464`;
- R3 candidate ownership blob: `9271ecc03f87fbb4f6a9ea1bd0889bdefc73f6a3`.

Main registry/current dashboard на момент review ещё отражали pre-C22 state, поэтому они не использовались как authorization для production ECO movement.

## Главный вывод

Существующая R3 foundation decomposition в целом хорошо соответствует потребностям evolutionary ecology:

```text
TF   simulation time
SD   WorldAddress / spatial domains
MAT  material identity/projections
WQ   world query planning
LIFE promotion/dormancy/demotion
WB   work budget / quality/defer/batch
POP  generic production population field
ENV  physical environment simulation
NX   interest/replication policy
WT   cross-domain world operation planning
```

То есть ECO **не нужен новый global foundation**.

Нужны явные intersection contracts и устранение нескольких ownership/name gaps до production convergence.

## Finding 1 — R3_ECO_PROGRAM_ID_COLLISION

Severity: `HIGH_ARCHITECTURE`.

Canonical Project Registry уже использует:

```text
ECO = Evolutionary Ecology Research
```

Но R3 candidate использует:

```text
p1_programs.ECO = physical resource economy / contracts / markets / production chains
WORLD_ECONOMY owner = ECO_FUTURE
```

Это два разных program meanings под одним ID.

### Required resolution

Сохранить:

```text
ECO = Evolutionary Ecology
```

и назвать future economy program:

```text
ECON = World Economy
```

Это также согласуется с более поздним R3 prepromotion control intent, где отдельно записано: future economy remains `ECON`.

### Gate

Исправить до `GLOBAL-P0 R3 promotion` / canonical program-ledger transition.

## Finding 2 — R3_ECO_POP_OWNERSHIP_INTERSECTION_UNSPECIFIED

Severity: `HIGH_ARCHITECTURE`.

R3 candidate правильно выделяет generic:

```text
POPULATION_FIELD -> POP_FUTURE
```

Но evolutionary ecology уже имеет population semantics как часть ecological truth.

Если это не разделить, легко получить два слоя:

```text
EcoPopulationManager
+
PopulationField
```

с конкурирующими identities/counts/lifecycle.

### Required boundary

```text
ECO
owns ecological population MODEL SEMANTICS:
lineage / heredity / recruitment / ecological density / biomass /
competition / selection / dispersal / biogeography

POP
owns generic PRODUCTION AGGREGATE/RUNTIME FABRIC:
compact spatial population container / simulation resolution /
LIFE promotion-demotion integration / runtime aggregate execution substrate
```

Связь должна быть adapter/projection boundary, не duplication.

## Finding 3 — R3_WQ_SYSTEM_DOMAIN_SCOPE_UNSPECIFIED

Severity: `MEDIUM_ARCHITECTURE`.

R3 определяет WQ как actor-scoped query planning. Это понятно для AI/gameplay/perception, но ecology является autonomous simulation domain и также требует deterministic non-authoritative projections.

Неясно, должна ли ecology делать:

```text
system/domain-scoped WQ query
```

или получать canonical derived environment projection через ENV/POP adapter.

### Required resolution

R3/WQ должен явно выбрать один supported shape:

1. WQ поддерживает system/domain-scoped query principal/context; или
2. autonomous simulations используют отдельный canonical domain-projection path, построенный на тех же WQ/domain-adapter semantics.

ECO-private query engine/database запрещён в обоих вариантах.

## Finding 4 — R3_ENV_ECO_PROJECTION_PATH_UNSPECIFIED

Severity: `MEDIUM_ARCHITECTURE`.

R3 ownership хорошо разделяет:

```text
ENV -> physical environment simulation
MAT -> canonical material identity
```

Но не фиксирует явный projection contract:

```text
ENV + MAT (+ WQ)
      ↓
Evolutionary ECO
```

ECO нужны минимум:

- temperature;
- moisture;
- sunlight;
- nutrient availability;
- flood/water stress;
- disturbance/history;
- substrate/material projection;
- source revisions/provenance.

### Required resolution

Добавить evolutionary ecology как explicit consumer environment/substrate projection, не отдавая ECO ownership ENV/MAT/WQ.

## Finding 5 — R3_WB_ECO_CONSUMER_UNSPECIFIED

Severity: `MEDIUM_ARCHITECTURE`.

WB candidate явно предусматривает POP/ENV как consumers, но evolutionary ECO не обозначен.

Production ecology всё равно потребует bounded multi-rate work:

```text
domain scope
simulation interval
input revisions
estimated cost
quality options
priority/relevance
```

### Required resolution

До production scheduling выбрать явный путь:

- ECO domain adapter напрямую предлагает работу WB; или
- ecology execution проходит через POP/ENV adapter, который предлагает work WB.

В обоих случаях:

```text
WB owns budget policy
ECO does not own global scheduler
```

## Consumer ownership matrix

| ECO need | Canonical owner | ECO role |
|---|---|---|
| simulation time/history | TF | consumer |
| WorldAddress/domain mapping | SD | consumer |
| physical environment | ENV | consumer |
| substrate/material identity | MAT | consumer |
| world query planning | WQ | consumer |
| generic population runtime field | POP | domain semantic producer/consumer via adapter |
| promotion/dormancy/demotion | LIFE | consumer |
| work quality/defer/batch | WB | work proposer |
| network interest/replication | NX | domain projection provider |
| cross-domain mutations | WT/M0 | intent/domain semantic provider |
| schema migration/versioning | COMPAT | domain schema owner under global governance |

## ECO output requirements

Future derived/domain output should be expressible without planet-wide individual objects:

```text
EcoPopulationProjection requirements
├─ ecological population / lineage reference
├─ canonical domain/spatial reference
├─ count / density
├─ biomass
├─ seed-bank / recruitment summary
├─ phenotype/development distribution
├─ health/stress distribution
├─ representation hints
├─ promotion/interaction relevance hints
└─ source revision/provenance
```

`visual sample != canonical organism`.

`Node3D existence != organism existence`.

`LOD != identity`.

## Что CONV0-A намеренно НЕ делает

Не реализуется:

- production EcoEnvironmentQuery adapter;
- WorldAddress;
- MaterialDefinition;
- generic PopulationField;
- LIFE manager;
- authority/persistence/transport;
- global work scheduler;
- replication protocol;
- P3/PH6 runtime.

## Decision

`CONV0-A REQUIREMENTS COMPLETE / GLOBAL GAPS IDENTIFIED`.

Следующая primary research задача ECO:

`ECO.CAL1 — Morphology Economics Calibration`.

CONV0-B остаётся frozen-waiting до canonical R3 + WQ/MAT/LIFE/WB/POP/ENV contract shapes, после чего эти requirements должны быть проверены на реальных canonical interfaces.
