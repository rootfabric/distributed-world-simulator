# T1A.0 — Complex Construct Demo Baseline and Fixture Contracts

**Дата:** 2026-08-08  
**Ветка:** `feature/t1-complex-construct-demo-lab`  
**Статус:** `IMPLEMENTED CANDIDATE`  
**Branch base:** `main @ 68085c9154a85a581226d08001f8e524b0992323`  
**C24 accepted:** `c18b3afaf0f2f078899be20d0529fa94d53adf90`

## Цель

Зафиксировать неизменяемый baseline будущей Complex Construct Demo до появления production asset adapter и реального D0 `ConstructSnapshot`.

T1A.0 не строит базу через альтернативную модель. Он определяет только data-only fixture contract, отдельную demo scene и deterministic identity surface, на которые будут опираться T1A.1 и T1A.2.

## Реализовано

### Machine-readable manifest

`config/construction/t1-complex-construct-demo.v1.json` закрепляет:

- branch/main baseline;
- принятый C24 checkpoint;
- fixture seed;
- demo scene и fixture builder paths;
- запрет изменения production contracts;
- D0/D1 expected part counts;
- room/utility/item IDs;
- initial fixture checksums.

### D0 baseline

```text
profile:       D0
construct:     construct/t1/lunar-outpost/d0
parts:         64
rooms:         1
utilities:     power + data
fixture SHA:   9e20be039011f6b94582dc4c7cffd2098fea0d145f3c08a3b053902764514d58
```

D0 item identities заранее закреплены для door, storage container, generator, battery, lamp и console.

### D1 baseline

```text
profile:       D1
construct:     construct/t1/lunar-outpost/d1
parts:         384
rooms:         habitat / airlock / workshop / storage / utility
utilities:     power + data + air
fixture SHA:   876cae0b17d8d508515ea2dafc577ad1b9389070d29d1102d3ad8565bd00b474
```

D1 также pin-ит doors, containers, generator, battery, lights, console, fabricator и workbench identities.

### Deterministic fixture builder

`T1ComplexConstructFixtureBuilder`:

- читает только T1 lab manifest;
- генерирует стабильные part IDs `part/t1/<profile>/pNNNN`;
- создаёт JSON-safe data descriptor;
- считает SHA-256 от стабильной ordered fixture signature;
- fail-closed отклоняет неизвестный profile или mismatch checksum;
- проверяет uniqueness identity arrays;
- не вызывает Item/Construction mutation path.

### Demo scene

Создана отдельная сцена:

`res://scenes/labs/t1_complex_construct_demo.tscn`

На T1A.0 она является только lab boundary. Root controller умеет получить D0/D1 fixture descriptor и сохранить diagnostic metadata. Реальный authoritative outpost появляется только в T1A.2.

## Authority boundary

T1A.0 специально фиксирует:

```text
fixture != authoritative state
fixture != ConstructSnapshot
fixture != Item Graph
fixture != network replication state
fixture != visual asset catalog
```

Production Item/Construction contracts этим checkpoint не меняются.

Canonical construct checksum отложен до `T1A.2`, когда D0 будет собран существующими production Construction contracts. Visual asset catalog отложен до `T1A.1`.

## Focused test

Добавлен:

`tests/construction/test_t1a0_complex_construct_demo_baseline.gd`

Он проверяет:

- baseline/C24 commit pins;
- authority policy;
- D0 = 64 parts;
- D1 = 384 parts;
- exact room/utility/item IDs;
- first/last deterministic part identity;
- exact initial fixture checksums;
- repeated generation equality;
- checksum sensitivity to identity mutation;
- rejection незакреплённого D2;
- загрузку отдельной demo scene;
- получение D0 descriptor через scene boundary без mutation path.

Focused runners:

```text
RUN_T1A0_COMPLEX_CONSTRUCT_DEMO_TESTS.ps1
RUN_T1A0_COMPLEX_CONSTRUCT_DEMO_TESTS.sh
```

## Ограничение текущей проверки

В connector environment отсутствует Godot binary, поэтому runtime/editor runner здесь не выполнялся. JSON/checksum reference был проверен отдельно при подготовке implementation. Перед переводом checkpoint в `ACCEPTED` обязателен Windows/Godot 4.7.1 double focused run и затем обычный project regression gate.

## Решение

```text
checkpoint: T1A0_BASELINE_AND_FIXTURE_CONTRACTS
decision:   IMPLEMENTED_CANDIDATE
next:       T1A.1 Part Visual Profile / Asset Adapter
```
