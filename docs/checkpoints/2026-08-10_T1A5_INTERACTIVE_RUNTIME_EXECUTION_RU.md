# T1A.5 — Interactive Runtime Execution

**Дата:** 2026-08-10  
**Ветка:** `feature/t1a5-interactive-runtime-execution`  
**Base:** T1A.4 accepted @ `a14e6f04c265467e1590106ace8439bddae19ddb`  
**Global revision:** `GLOBAL-P0-2026-08-08-R1`  
**Статус:** `ACCEPTED`

## Acceptance evidence

Exact Windows Godot `4.7.1.stable.double.custom_build.a13da4feb`.

Focused gate на tested head `01b6ee2364d949858f12f0562de09743795cbc7e`:

```text
Editor import                         PASS
T1A.4 interactive fixture binding    PASS 153
C5B affordance runtime contracts     PASS 32
C15 executable utilities contracts   PASS 92
T1A.5 interactive runtime execution  PASS 67
Focused total                         344 assertions PASS
```

После focused PASS runtime implementation не менялся; до full regression были только validation/checkpoint metadata commits.

Full composition gate на `c05b1a86f05d1c6562ebb0dad1bf6c161cc6a185`:

```text
main_scene_cli_all  6 PASS / 0 FAIL
All world/core regression tests through NX4 client prediction and reconciliation passed.
Report: artifacts/test-results/world-regression-summary.json
```

Итоговый статус:

```text
SOURCE_ACCEPTED       true
MAIN_INTEGRATED       false
COMPOSITION_VERIFIED  true
PRODUCTION_READY      false
```

## Что принято

T1A.5 добавляет первый исполняемый behavior-runtime слой поверх accepted T1A.4 bindings:

```text
C5 affordance
  -> runtime command
  -> expected revision + operation fingerprint
  -> replay/conflict fence
  -> runtime subject transition
  -> C15 utility recomputation when required
```

Canonical `ConstructSnapshot` и Item Graph не являются хранилищем transient runtime state.

## Generic C5B runtime foundation

Добавлены reusable contracts под владельцем Construction behavior:

```text
scripts/construction/behavior/
  construction_runtime_subject_state.gd
  construction_runtime_state_store.gd
  construction_affordance_runtime_executor.gd
```

Generic runtime subject содержит:

```text
runtime_id
construct_id
item_instance_id
capability_id
revision
state {}
checksum
```

Generic layer не знает D0-specific transitions. Replay/revision semantics переиспользуют существующие `ItemOperationFingerprint` и `ItemOperationLedger`; T1A.5 использует отдельный экземпляр ledger для behavior runtime, не загрязняя M0 assembly ledger.

## Принятые D0 runtime semantics

```text
DOOR       CLOSED <-> OPEN
GENERATOR  running true/false
LAMP       on true/false
CONSOLE    active + use_count
```

`OPEN_DOOR` / `CLOSE_DOOR` требуют FULL POWER и DATA allocations. `START_GENERATOR` / `STOP_GENERATOR` проецируют `running` в existing C15 POWER SOURCE `online`. `TOGGLE_LIGHT` управляет участием lamp demand в C15 POWER simulation. `USE_WORKSTATION` делает console active и увеличивает `use_count`; active console добавляет POWER demand.

Battery остаётся existing C15 storage state; focused acceptance подтвердил discharge при остановленном generator и recharge после повторного старта.

Container inventory execution не дублируется: `OPEN_CONTAINER / STORE_ITEM / TAKE_ITEM` остаются у existing Item/Container transfer foundation.

## Принятые инварианты

Runtime execution не меняет:

```text
ConstructSnapshot
64 part identities
112 bonds
construction revision 177
Item identities / relations
T1A.4 fixture binding components
C2B/M0 authoritative assembly state
```

Runtime state не включён в permanent item/construct identity, authority/server route, LOD/HLOD, presentation identity или material ontology.

P0 guards подтверждены: нет нового ItemRegistry, ConstructStore, authority registry, transaction coordinator, operation-ledger implementation, private T1 RPC bridge, private utility simulator или material ontology.

## Следующий checkpoint

`T1A.6 — Runtime Presentation + Multiplayer Binding`

Он должен связать accepted canonical runtime state с presentation и network replication, сохраняя:

```text
canonical runtime state != presentation != transport
```

Presentation не становится canonical truth, а transport не владеет gameplay semantics.
