# T1A.5 — Interactive Runtime Execution

**Дата:** 2026-08-10  
**Ветка:** `feature/t1a5-interactive-runtime-execution`  
**Base:** T1A.4 accepted @ `a14e6f04c265467e1590106ace8439bddae19ddb`  
**Global revision:** `GLOBAL-P0-2026-08-08-R1`  
**Статус:** `FOCUSED WINDOWS PASS — FULL REGRESSION REQUIRED`

## Exact Windows focused evidence

Проверено на `Godot 4.7.1.stable.double.custom_build.a13da4feb`, tested head `01b6ee2364d949858f12f0562de09743795cbc7e`:

```text
T1A.4 interactive fixture binding   PASS 153
C5B affordance runtime contracts    PASS 32
C15 executable utilities contracts  PASS 92
T1A.5 interactive runtime execution PASS 67
Focused total                       344 assertions PASS
```

Editor import также прошёл успешно. Runtime implementation после tested head не менялся; последующие commits этого checkpoint должны быть только validation/checkpoint metadata до полного regression gate.

Статусные измерения до полного world regression:

```text
SOURCE_ACCEPTED       false
MAIN_INTEGRATED       false
COMPOSITION_VERIFIED  false
PRODUCTION_READY      false
```

## Цель

T1A.4 закрепил интерактивные D0 fixtures как production Items с C5 affordances, item-owned storage и C15 POWER/DATA bindings, но намеренно не исполнял состояния двери, генератора, света и консоли.

T1A.5 добавляет первый исполняемый runtime слой:

```text
C5 affordance
  -> runtime command
  -> expected revision + operation fingerprint
  -> replay/conflict fence
  -> runtime subject transition
  -> C15 utility recomputation when required
```

Canonical `ConstructSnapshot` и Item Graph не становятся хранилищем transient runtime state.

## Generic C5B runtime foundation

Gap закрыт у владельца C5, а не внутри T1 lab.

Добавлены generic contracts:

```text
scripts/construction/behavior/
  construction_runtime_subject_state.gd
  construction_runtime_state_store.gd
  construction_affordance_runtime_executor.gd
```

Generic subject содержит только:

```text
runtime_id
construct_id
item_instance_id
capability_id
revision
state {}
checksum
```

Contract не содержит T1-specific transition logic.

Runtime state store обеспечивает register/replay, revisioned update, stale-revision rejection, canonical JSON state, checksum и export/load roundtrip.

Affordance runtime executor переиспользует существующие `ItemOperationFingerprint` и `ItemOperationLedger`:

```text
exact operation replay -> exact stored result
same operation_id + different fingerprint -> OPERATION_ID_CONFLICT
stale expected_revision -> terminal REJECTED
successful mutation -> revision + 1
read/no-op -> revision preserved
```

T1A.5 использует отдельный экземпляр существующего `ItemOperationLedger` для behavior runtime и не загрязняет M0 assembly ledger.

## D0 runtime subjects

Исполняются четыре binding-а:

```text
runtime/t1a5/d0/door
runtime/t1a5/d0/generator
runtime/t1a5/d0/lamp
runtime/t1a5/d0/console
```

Начальные состояния:

```text
DOOR       CLOSED
GENERATOR  running=true
LAMP       on=false
CONSOLE    active=false, use_count=0
```

### Door

`OPEN_DOOR` / `CLOSE_DOOR` требуют текущие C15 allocations:

```text
POWER door allocation == FULL
DATA  door allocation == FULL
```

State: `CLOSED <-> OPEN`.

### Generator

`START_GENERATOR` / `STOP_GENERATOR` меняют runtime `running`, который проецируется в existing C15 generator SOURCE property `online`. После перехода POWER network пересчитывается deterministic utility tick.

### Lamp

`TOGGLE_LIGHT` меняет `on`. При `on=false` lamp demand не участвует в runtime POWER demand set; при включении demand возвращается и C15 simulator пересчитывает allocation/flows/storage.

### Console

`USE_WORKSTATION` выставляет `active=true` и увеличивает `use_count`. При активности console POWER demand участвует в runtime demand set.

### Battery

Отдельная T1 battery state machine не создаётся. Используется existing C15 storage state (`stored_amount`, `capacity`, `tick`, `revision`). Focused acceptance подтвердил discharge при остановке generator и recharge после повторного старта.

## Container boundary

T1A.4 уже создал настоящий 24-slot item-owned Container. T1A.5 не дублирует `STORE_ITEM/TAKE_ITEM` runtime transitions:

```text
OPEN_CONTAINER / STORE_ITEM / TAKE_ITEM
  -> existing inventory + Item transfer foundation
```

## Инварианты

Focused PASS подтвердил, что runtime execution не меняет:

```text
ConstructSnapshot
64 part identities
112 bonds
construction revision 177
Item identities
Item relations
T1A.4 fixture binding components
C2B/M0 authoritative assembly state
```

Runtime state не входит в permanent item/construct identity, authority/server route, LOD/HLOD, render profile или material ontology.

## P0

T1A.5 не создаёт:

```text
new ItemRegistry
new ConstructStore
new authority registry
new transaction coordinator
new operation-ledger implementation
private T1 RPC bridge
private utility simulator
private material ontology
```

C5B является расширением существующего C5 behavior ownership, а не параллельной foundation.

## Focused gate — PASS

Runner:

```powershell
$Godot = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"

.\RUN_T1A5_INTERACTIVE_RUNTIME_EXECUTION_TESTS.ps1 `
    -GodotPath $Godot
```

Result:

```text
Editor import                         PASS
T1A.4 interactive fixture binding    PASS 153
C5B affordance runtime contracts     PASS 32
C15 executable utilities contracts   PASS 92
T1A.5 interactive runtime execution  PASS 67
Focused total                         344 assertions PASS
```

Acceptance также покрывает exact successful replay, operation-id conflict, stale revision terminal rejection + exact rejected replay, wrong capability/action rejection, C15 profile validity, неизменность ConstructSnapshot/C2B/M0/Item Graph и P0 forbidden identity leakage.

## Следующий gate

Для source acceptance остаётся полный:

```powershell
$env:GODOT_BIN = $Godot
.\RUN_WORLD_REGRESSION_TESTS.ps1
```

После PASS можно выставить:

```text
SOURCE_ACCEPTED       true
COMPOSITION_VERIFIED  true
```

`MAIN_INTEGRATED` и `PRODUCTION_READY` при этом остаются false.

## Следующий checkpoint

После acceptance:

`T1A.6 — Runtime Presentation + Multiplayer Binding`

Он должен связать accepted runtime state с видимым состоянием двери/лампы/консоли и сетевой доставкой, сохраняя:

```text
canonical runtime state != presentation != transport
```
