# T1 Complex Construct Demo — P0 alignment

**Global revision:** `GLOBAL-P0-2026-08-08-R1`  
**Branch:** `feature/t1-complex-construct-demo-lab`  
**Validation overlay:** `fix/t1-m5-convergence-finish-barrier`  
**Local role:** Construction composition / complex construct validation

## Зачем добавлен этот документ

T1 проверяет сложную композицию Construction поверх Item, network и HLOD. После глобального архитектурного аудита здесь явно фиксируется, какие решения T1 может принимать локально, а какие принадлежат общему foundation и не должны повторно реализовываться внутри Construction.

## Локальный план остаётся прежним

```text
T1A Complex Construct Demo
    ↓
T1B Construct Composition / Failure Demo
    ↓
T2 Construction Scale
    ↓
T5 Matter + Construction Composition
```

T1A/T1B разрешено развивать до завершения всех P0 implementations, если локальные эксперименты не замораживают конкурирующие global contracts.

## Текущий статус после Windows composition regression

Validation overlay `fix/t1-m5-convergence-finish-barrier` использовался для закрытия regression blockers, обнаруженных при полном T1 checkout. На head `280c6e24ef5b847f27be7099140832ddd7e23a25` подтверждено:

```text
World boot matrix                             PASS / exit 0
MW7 matter interest replication              PASS / 114 assertions / exit 0
RUN_WORLD_REGRESSION_TESTS.ps1                PASS
All world/core regression tests through NX4  PASS
```

Статусы T1A.0 и T1A.1 фиксируются раздельно по P0 vocabulary:

```text
SOURCE_ACCEPTED       = true
MAIN_INTEGRATED       = false
COMPOSITION_VERIFIED  = true
PRODUCTION_READY      = false
```

Это принципиально не означает `T1 ACCEPTED`: higher-level T0/T1 gates остаются отдельными.

## Классификация regression-enabling fixes

При полном Windows regression были обнаружены и исправлены проблемы в соседних уже существующих foundations/harnesses:

```text
M5 graphical acceptance finalization/publication
world persistence manifest JSON numeric normalization
MW7 test fixture lifecycle / exit cleanup
world regression runner coverage/packaging
```

Эти изменения допустимы в validation overlay только как исправления существующих contracts. Они **не передают T1 владение** соответствующими foundations:

```text
T1 != Network owner
T1 != Persistence owner
T1 != Matter interest owner
T1 != global regression framework owner
```

Перед интеграцией в `main` их scope должен оставаться явно описанным как общие regression fixes, а не как новые Construction semantics.

## P0 dependencies

### Spatial

Construction сохраняет собственные construct/local scopes и local frames. В будущем они должны отображаться через `Spatial Domain Fabric` в world/authority/interest адресацию.

Запрещено использовать Construction section/chunk/HLOD key как глобальный world identity.

До появления общего Spatial Domain Fabric T1A.2 может использовать существующие Construction/local identifiers только внутри уже определённого domain contract. Нельзя превращать их в permanent global addresses или server routes.

### Materials

Текущие construction `material_family` / visual profile IDs являются только presentation/fixture identifiers. Будущие физические, resource, fabrication и salvage свойства должны ссылаться на общий `MaterialDefinitionId`, а не создавать автономную material ontology Construction.

```text
presentation material_family != MaterialDefinitionId
render material               != canonical material definition
```

### Transactions

Следующие операции не должны становиться цепочкой best-effort RPC:

```text
consume item -> place part
remove part -> salvage item/material
construction damage -> debris/material output
```

До formal T5-like acceptance они должны подключаться к общему `WorldOperation / WorldTransactionPlan` contract.

T1A.2 может создать authoritative D0 construct по существующему Construction operation path. T1A.3 может использовать существующие Item Graph transactions для перемещений предметов. Но операция, которая одновременно меняет Item и Construction canonical state, является P0 cross-domain boundary и не должна получать private T1 bridge.

### Network

- NX7 задаёт physics authority policy поверх существующего authority foundation;
- NX8 поставляет interest/budget contract для C22/C24 adapters;
- NX9 не заменяет Construction/M0 durability новым persistence path;
- network delivery никогда не является заменой domain transaction semantics.

### Representation

```text
Construct canonical graph
    != C22 artifact
    != C24 ArrayMesh
    != HLOD selection
    != T1 PartVisualProfile
```

Эта граница остаётся неизменной. Presentation artifacts разрешено удалить и полностью перестроить из canonical state.

## Локальные задачи, разрешённые без P0 block

- D0/D1 complex outpost fixture;
- T1A.2 authoritative D0 builder через существующий Construction authority path;
- rooms/openings/utilities/machines composition;
- Item Graph transfer experiments, не создающие cross-domain commit chain;
- multiplayer convergence/reconnect experiments;
- C22/C24 near/mid/far representation;
- dirty-section rebuild measurements;
- representation backend routing research;
- scale experiments, если они не создают новый global interest identity.

## Explicit gate для T1A.2 / T1A.3

Перед добавлением нового contract необходимо проверить:

```text
[ ] identity не зависит от LOD/HLOD
[ ] local Construction scope не становится global world address
[ ] authority owner не кодируется в permanent identity
[ ] visual/material profile не становится physical material truth
[ ] Item + Construction mutation не полагается на порядок RPC
[ ] persistence/recovery использует существующий foundation
[ ] headless/server path не требует renderer assets
```

Если любой пункт требует нового общего понятия, T1 stage должен остановиться и вынести его в global P0 plan.

## Stop conditions

T1 должен остановить локальную реализацию и вынести вопрос в global plan, если потребуется:

- отдельный Construction authority registry;
- отдельный глобальный material namespace;
- Construction chunk как permanent world address;
- cross-domain correctness через порядок RPC;
- HLOD/proxy/PartVisualProfile как источник canonical state;
- собственный persistence model вместо существующих transaction/recovery foundations;
- server routing, встроенный в permanent construct/part identity.

## Merge gate

Перед formal merge/acceptance T1 head обязан иметь:

```text
[PASS] GLOBAL-P0-2026-08-08-R1 или более новая синхронная revision
[PASS] global config byte-equivalent main
[PASS] network NX7-NX9 boundaries синхронизированы
[PASS] local T1 roadmap не переопределяет P0 ownership
[PASS] regression-enabling fixes классифицированы по настоящим foundation owners
[PASS] SOURCE_ACCEPTED отделён от MAIN_INTEGRATED / PRODUCTION_READY
[PASS] branch regression / T1 focused tests
```

На текущем validation overlay первые, вторые, третьи, четвёртые, пятые, шестые и regression-пункты подтверждены. `MAIN_INTEGRATED` остаётся `false` до фактической интеграции соответствующих изменений в `main`.

Этот документ является локальным дополнением. Канонический общий план находится в `docs/plans/GLOBAL_PROGRAM_ARCHITECTURE_ROADMAP_RU.md`.
