# T1A.5 — Interactive Runtime Execution

**Дата:** 2026-08-10  
**Ветка:** `feature/t1a5-interactive-runtime-execution`  
**Base:** T1A.4 accepted @ `a14e6f04c265467e1590106ace8439bddae19ddb`  
**Global revision:** `GLOBAL-P0-2026-08-08-R1`  
**Статус:** `IMPLEMENTED CANDIDATE`

## Цель

T1A.4 закрепил шесть интерактивных D0 fixtures как production Items с C5 affordances, item-owned storage и C15 POWER/DATA bindings, но намеренно не исполнял состояния двери, генератора, света и консоли.

T1A.5 добавляет первый исполняемый runtime слой:

```text
C5 affordance
  -> runtime command
  -> expected revision + operation fingerprint
  -> replay/conflict fence
  -> runtime subject transition
  -> C15 utility recomputation when required
```

При этом canonical `ConstructSnapshot` и Item Graph не становятся хранилищем transient runtime state.

## Generic C5B runtime foundation

Выявленный gap закрыт у владельца C5, а не внутри T1 lab.

Добавлены generic contracts:

```text
scripts/construction/behavior/
  construction_runtime_subject_state.gd
  construction_runtime_state_store.gd
  construction_affordance_runtime_executor.gd
```

### Runtime subject

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

Contract не знает слов `DOOR`, `GENERATOR`, `LAMP`, `CONSOLE` и не содержит T1-specific transitions.

### Runtime state store

Store обеспечивает:

```text
register / replay
revisioned update
stale revision rejection
canonical JSON state
checksum
export / load roundtrip
```

Это behavior-runtime state, а не новый ItemRegistry, ConstructStore или authority registry.

### Affordance runtime executor

Executor использует существующие:

```text
ItemOperationFingerprint
ItemOperationLedger
```

Command envelope:

```text
operation_id
action_kind
runtime_id
expected_revision
payload
```

Семантика:

```text
exact operation replay -> exact stored result
same operation_id + different fingerprint -> OPERATION_ID_CONFLICT
stale expected_revision -> terminal REJECTED
successful mutation -> revision + 1
read/no-op -> revision preserved
```

T1A.5 создаёт отдельный **экземпляр** существующего `ItemOperationLedger` для behavior runtime. Это сознательно не M0 assembly ledger: runtime actions не должны менять уже committed Item+Construct transaction ledger без отдельного cross-domain transaction.

Новой реализации ledger нет.

## D0 runtime subjects

Исполняются четыре binding-а:

```text
runtime/t1a5/d0/door
runtime/t1a5/d0/generator
runtime/t1a5/d0/lamp
runtime/t1a5/d0/console
```

Каждый subject ссылается на global fixture Item ID и capability_id из accepted T1A.4 profile.

Начальные состояния:

```text
DOOR       CLOSED
GENERATOR  running=true
LAMP       on=false
CONSOLE    active=false, use_count=0
```

## Door execution

Исполняются:

```text
OPEN_DOOR
CLOSE_DOOR
```

Перед переходом проверяются текущие T1A.4/C15 allocations:

```text
POWER door allocation == FULL
DATA  door allocation == FULL
```

State:

```text
CLOSED <-> OPEN
```

T1A.5 пока не моделирует промежуточную animation state `OPENING/CLOSING`; presentation interpolation относится к следующему checkpoint.

## Generator execution

Исполняются:

```text
START_GENERATOR
STOP_GENERATOR
```

Runtime state `running` проецируется в существующий C15 generator SOURCE node через property `online`.

После изменения C15 POWER network пересчитывается новым deterministic utility tick.

## Lamp execution

Исполняется:

```text
TOGGLE_LIGHT
```

При `on=false` lamp demand не участвует в runtime POWER demand set.

При включении demand возвращается и C15 simulator повторно рассчитывает allocation/flows/storage.

Renderer/light emission пока не являются canonical state и не исполняются этим checkpoint.

## Console execution

Исполняется:

```text
USE_WORKSTATION
```

State:

```text
active=true
use_count += 1
```

При active console его POWER demand включается в runtime demand set. DATA source остаётся T1A.4 C15 binding.

UI самой консоли относится к следующему presentation/runtime integration checkpoint.

## Battery behavior

Battery не получает отдельную T1 state machine.

Используется существующий C15 storage state:

```text
stored_amount
capacity
tick
revision
```

При остановленном генераторе батарея реально разряжается через `construction_utility_simulator.gd`; после запуска генератора surplus снова может её заряжать.

`INSPECT_BATTERY` как отдельный runtime command в T1A.5 не материализуется: состояние уже доступно из C15 profile, а inspection UI не должен создавать лишнюю canonical mutation.

## Container boundary

T1A.4 уже создал настоящий 24-slot item-owned Container.

T1A.5 **не** реализует отдельные `STORE_ITEM/TAKE_ITEM` runtime transitions, потому что это дублировало бы production Item transfer semantics.

```text
OPEN_CONTAINER / STORE_ITEM / TAKE_ITEM
  -> existing inventory + Item transfer foundation
```

Это сознательная ownership boundary.

## Что остаётся неизменным

Runtime actions не должны менять:

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

Runtime state не записывается в:

```text
permanent item identity
construct identity
LOD/HLOD
server/authority route
render profile
MaterialDefinitionId
```

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

Новый C5B runtime слой является расширением существующего C5 behavior ownership, а не параллельной foundation.

## Focused acceptance

Runner:

```powershell
$Godot = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"

.\RUN_T1A5_INTERACTIVE_RUNTIME_EXECUTION_TESTS.ps1 `
    -GodotPath $Godot
```

Gate:

```text
Editor import
T1A.4 acceptance
C5B generic runtime contracts
C15 executable utilities
T1A.5 D0 runtime acceptance
```

T1A.5 acceptance проверяет:

```text
4 runtime subjects
runtime store checksums/revisions
OPEN/CLOSE door
exact success replay
operation-id conflict
STOP/START generator
battery discharge/recharge
TOGGLE_LIGHT
USE_WORKSTATION
stale revision rejection + rejected replay
wrong capability/action rejection
C15 profile validity after transitions
ConstructSnapshot unchanged
C2B/M0 authoritative state unchanged
Item Graph unchanged
P0 forbidden identity leakage absent
```

## Status gate

До exact Windows focused + full world regression:

```text
SOURCE_ACCEPTED       false
MAIN_INTEGRATED       false
COMPOSITION_VERIFIED  false
PRODUCTION_READY      false
```

## Следующий checkpoint

После acceptance:

`T1A.6 — Runtime Presentation + Multiplayer Binding`

Он должен привязать accepted runtime state к видимому состоянию двери/лампы/консоли и сетевой доставке, сохраняя принцип:

```text
canonical runtime state != presentation != transport
```
