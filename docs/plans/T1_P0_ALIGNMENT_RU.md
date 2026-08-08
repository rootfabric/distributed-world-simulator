# T1 Complex Construct Demo — P0 alignment

**Global revision:** `GLOBAL-P0-2026-08-08-R1`  
**Branch:** `feature/t1-complex-construct-demo-lab`  
**Local role:** Construction composition / complex construct validation

## Зачем добавлен этот документ

T1 уже проверяет сложную композицию Construction поверх Item, network и HLOD. После глобального архитектурного аудита нужно явно зафиксировать, какие решения T1 может принимать локально, а какие принадлежат общему foundation и не должны быть повторно реализованы внутри Construction.

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

## P0 dependencies

### Spatial

Construction сохраняет собственные construct/local scopes и local frames. В будущем они должны отображаться через `Spatial Domain Fabric` в world/authority/interest адресацию.

Запрещено использовать Construction section/chunk/HLOD key как глобальный world identity.

### Materials

Текущие construction material/profile IDs остаются допустимыми presentation/fixture identifiers. Будущие физические и производственные свойства должны ссылаться на общий `MaterialDefinitionId`, а не создавать автономную material ontology Construction.

### Transactions

Следующие операции не должны становиться цепочкой best-effort RPC:

```text
consume item -> place part
remove part -> salvage item/material
construction damage -> debris/material output
```

До T5 они должны подключаться к общему `WorldOperation / WorldTransactionPlan` contract.

### Network

- NX7 задаёт physics authority policy поверх существующего authority foundation;
- NX8 поставляет interest/budget contract для C22/C24 adapters;
- NX9 не заменяет Construction/M0 durability новым persistence path.

### Representation

```text
Construct canonical graph
    != C22 artifact
    != C24 ArrayMesh
    != HLOD selection
```

Эта граница остаётся неизменной.

## Локальные задачи, разрешённые без P0 block

- D0/D1 complex outpost fixture;
- rooms/openings/utilities/machines composition;
- multiplayer convergence/reconnect experiments;
- C22/C24 near/mid/far representation;
- dirty-section rebuild measurements;
- representation backend routing research;
- scale experiments, если они не создают новый global interest identity.

## Stop conditions

T1 должен остановить локальную реализацию и вынести вопрос в global plan, если потребуется:

- отдельный Construction authority registry;
- отдельный глобальный material namespace;
- Construction chunk как permanent world address;
- cross-domain correctness через порядок RPC;
- HLOD/proxy как источник canonical state;
- собственный persistence model вместо существующих transaction/recovery foundations.

## Merge gate

Перед formal merge/acceptance T1 head обязан иметь:

```text
[PASS] GLOBAL-P0-2026-08-08-R1 или более новую синхронную revision
[PASS] global config byte-equivalent main
[PASS] network NX7-NX9 boundaries синхронизированы
[PASS] local T1 roadmap не переопределяет P0 ownership
[PASS] branch regression / T1 focused tests
```

Этот документ является локальным дополнением. Канонический общий план находится в `docs/plans/GLOBAL_PROGRAM_ARCHITECTURE_ROADMAP_RU.md`.
