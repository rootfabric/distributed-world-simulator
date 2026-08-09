# T1A.2 — D0 Authoritative Outpost Builder

**Дата:** 2026-08-09  
**Ветка:** `feature/t1a2-d0-authoritative-outpost-builder`  
**Global revision:** `GLOBAL-P0-2026-08-08-R1`  
**Статус:** `ACCEPTED`

## Результат

D0 materialized через существующий production Construction kernel:

```text
T1A.0 D0 fixture
  -> T1D0AuthoritativeOutpostBuilder
  -> ConstructAggregate.add_part/add_bond/set_build_state
  -> ConstructSnapshot v1
  -> ConstructionConstructStore CREATE
```

Canonical D0:

```text
construct_id:       construct/t1/lunar-outpost/d0
fixture checksum:   9e20be039011f6b94582dc4c7cffd2098fea0d145f3c08a3b053902764514d58
parts:              64
bonds:              112
state_revision:     177
build_state:        OPERATIONAL
rigid islands:      1
```

Все `part/t1/d0/p0000..p0063` identity сохранены. Reserved `item/t1/d0/construct-root` и `item/t1/d0/structural/pXXXX` остаются references до T1A.3; шесть gameplay fixture item IDs также не материализованы в Item Graph на T1A.2.

## Acceptance evidence

Exact Windows Godot:

```text
Godot 4.7.1.stable.double.custom_build.a13da4feb
T1A.0 PASS 58
T1A.1 PASS 67
C1 PASS 40
C2B PASS 64
T1A.2 PASS 186
```

Полный world regression после M4 final-report harness fix:

```text
declared_test_count   203
discovered_test_count 203
passed                true
M4                     PASS exit 0
M5/M6                  PASS
MW7-MW10               PASS
RL3                     PASS
main_scene_cli_all      PASS exit 0
```

## P0 status

```text
SOURCE_ACCEPTED       = true
MAIN_INTEGRATED       = false
COMPOSITION_VERIFIED  = true
PRODUCTION_READY      = false
```

Не введены новые spatial identity, authority registry, material ontology, persistence format или private Item+Construction transaction chain.

## Следующий checkpoint

`T1A.3 — Item Graph Materialization` должен материализовать root, 64 structural part-items и 6 D0 interactive fixture items в production Item Graph. Связка construct + item attachment обязана использовать существующий C2B/M0 transaction foundation, а не прямой T1 RPC bridge.
