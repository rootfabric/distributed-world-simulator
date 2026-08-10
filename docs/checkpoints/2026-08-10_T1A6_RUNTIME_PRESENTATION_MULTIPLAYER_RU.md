# T1A.6 — Runtime Presentation + Multiplayer Binding

**Дата:** 2026-08-10  
**Ветка:** `feature/t1a6-runtime-presentation-multiplayer-binding`  
**Base:** T1A.5 accepted @ `7e6b83a0df8c509374af21e70615dafa66330846`  
**Global revision:** `GLOBAL-P0-2026-08-08-R1`  
**Статус:** `FOCUSED ACCEPTED / FULL REGRESSION PENDING`

## Цель

T1A.5 закрепил canonical behavior-runtime state для D0, но состояние ещё не было связано с реальной сетевой репликацией и derived graphical presentation.

T1A.6 строит первую полную цепочку:

```text
server canonical runtime state
  -> construction runtime snapshot DTO
  -> existing M3 transport boundary/channels
  -> client runtime replica store
  -> derived presentation
```

Ключевой invariant:

```text
canonical runtime state != presentation != transport
```

Presentation не является authority, transport не владеет gameplay semantics.

## Network ownership

Базовые production M3 server/client runtime не переписываются. T1A.6 добавляет stacked adapters:

```text
T1A6M3RuntimeServerAdapter
  extends accepted M3 dedicated server

T1A6M3RuntimeClientAdapter
  extends accepted M3 graphical client
```

Все обычные M3 сообщения передаются в `super`; adapter перехватывает только новые construction-runtime message types.

Нового transport boundary, ENet implementation или channel namespace нет. После Windows compile fix1 оба adapter используют унаследованный `RealtimeChannelPolicy` accepted M3/NX6 runtime и не объявляют локальную копию transport policy.

## Wire contract

Добавлен generic DTO:

```text
planet_simulator.construction_runtime_snapshot.v1
```

Поля:

```text
construct_id
authority_epoch
server_tick
revision
runtime_state
state_checksum
checksum
```

`revision` — generation существующего C5B runtime state store. `runtime_state` валидируется исходным C5B store contract.

DTO добавлен в существующий `NetworkProtocolManifest`, поэтому protocol hash меняется осознанно и compatibility handshake обнаружит несовместимый клиент/сервер.

## Delivery policy

Runtime commands:

```text
CONTROL / RELIABLE_ORDERED
```

Полный runtime state:

```text
RESYNC / RELIABLE_ORDERED
```

На этом checkpoint full snapshot редкий и дискретный. Корректность не должна зависеть от того, произойдёт ли после потерянного пакета ещё одно событие. Поэтому full canonical runtime state намеренно не отправляется через lossy movement-style `SNAPSHOT` channel.

Delta/unreliable optimization можно добавить позже как scale optimization при обязательном reliable resync path.

## Session fence

Runtime command принимается только если:

```text
peer compatible
peer joined
_peer_to_session[peer_id] == current session_id
```

Это сохраняет существующую M3 transport-session boundary и запрещает применять команду старой reconnect-сессии.

## Client replica

Generic `ConstructionRuntimeReplicaStore` поддерживает:

```text
initial snapshot
exact replay
clock-only newer server_tick
stale epoch/revision ignore
same revision + different semantic state -> reject
authority_epoch reset
```

Presentation читает только accepted replica state.

## Derived D0 presentation

`T1D0RuntimePresenter` — Node3D adapter, а не canonical state.

```text
DOOR       CLOSED/OPEN -> target hinge yaw
LAMP       on          -> OmniLight visible
GENERATOR  running     -> indicator visible
CONSOLE    active      -> indicator visible
```

Door presentation плавно движется к target yaw. Acceptance может вызвать `force_sync()` для deterministic final comparison.

Presenter ничего не записывает назад в C5B runtime, Item Graph или ConstructSnapshot.

## Multiplayer acceptance scenario

Два graphical клиента + dedicated server:

```text
server starts D0 canonical runtime
A joins
A OPEN_DOOR
A sees OPEN presentation
B joins after door is already OPEN
B must receive OPEN as authoritative join baseline
B sees OPEN presentation
B TOGGLE_LIGHT
A and B receive lamp ON
A CLOSE_DOOR
A and B converge on final state
```

Финал:

```text
DOOR       CLOSED
LAMP       ON
GENERATOR  RUNNING
CONSOLE    INACTIVE
runtime generation >= 7
```

Проверяется одинаковый `state_checksum` у server/A/B и одинаковая derived presentation у обоих graphical clients.

## C5C replication contracts

Focused gate отдельно проверяет generic runtime snapshot/replica semantics:

```text
snapshot validation
initial accept
exact replay
clock-only update
stale update
new revision
same-revision mutation rejection
authority epoch reset
```

## Windows focused acceptance

Первый Windows прогон на `cd249458d7bb2964007a129910164a63d0533f65` дошёл до запуска dedicated server и выявил compile-time shadowing `RealtimeChannelPolicy` в T1A.6 adapter. Runtime semantics до этого места не падали.

Fix1:

```text
5f83dcb3ca3f7043fa3c205260e7e24d891ba32f  server adapter
 afeea2789d319bcb0bd384c97bd31d4e133a8ff8  client adapter
```

Повторный focused gate после fix1 полностью прошёл:

```text
T1A.5 interactive runtime execution    PASS 67
NX0 observability baseline             PASS 150
M3 graphical multiplayer contracts     PASS 77
C5C runtime replication contracts      PASS 29
T1A.6 graphical multiplayer            PASS 25 / 0 failures
```

Дополнительно подтверждено:

```text
client A graphical                     PASS
client B graphical                     PASS
A/B final runtime revision             PASS
server final runtime revision          PASS
A/B state checksum convergence         PASS
server/client checksum convergence     PASS
A presentation == canonical runtime    PASS
B presentation == canonical runtime    PASS
A replica rejections                   0
B replica rejections                   0
server runtime commands                3
server runtime command rejections      0
join + mutation snapshots              PASS
A/B/server clean shutdown              PASS
```

Финальный focused marker:

```text
T1A.6 runtime presentation multiplayer: 25 assertions, 0 failures
T1A.6 runtime presentation + multiplayer focused gate passed.
```

Focused acceptance доказал реальную цепочку `canonical runtime -> transport -> replica -> presentation` на dedicated server + двух graphical clients, включая late join после открытия двери.

## Visual lab

Standalone visual lab:

```powershell
$Godot = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"
& $Godot --path . --script res://tools/runtime/t1a6_visual_lab.gd
```

Управление:

```text
1   door open/close
2   lamp on/off
3   generator start/stop
4   use console
Esc exit
```

UI показывает runtime state, POWER status и battery amount. Это диагностическая presentation scene, canonical truth остаётся C5B runtime.

## P0 guards

T1A.6 не создаёт:

```text
new authority registry
new network transport
new channel namespace
new ItemRegistry
new ConstructStore
new transaction coordinator
private T1 persistence
presentation-as-authority
transport-as-gameplay-state
LOD/HLOD in runtime identity
MaterialDefinitionId/private material ontology
```

Единственное существующее production-file изменение — регистрация нового wire schema в `NetworkProtocolManifest`; base M3 server/client files не изменяются.

## Acceptance state

Focused gate теперь принят. До полного composition regression статус остаётся:

```text
SOURCE_ACCEPTED       false
MAIN_INTEGRATED       false
COMPOSITION_VERIFIED  false
PRODUCTION_READY      false
```

Последний gate T1A.6:

```powershell
$Godot = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"
$env:GODOT_BIN = $Godot
.\RUN_WORLD_REGRESSION_TESTS.ps1
```

Целевой marker:

```text
All world/core regression tests through NX4 client prediction and reconciliation passed.
```

При полном PASS T1A.6 может перейти в:

```text
SOURCE_ACCEPTED       true
MAIN_INTEGRATED       false
COMPOSITION_VERIFIED  true
PRODUCTION_READY      false
```

## Следующий checkpoint

После acceptance T1A.6 следующий логичный слой:

`T1A.7 — Runtime Recovery / Interest / Scale`

Он должен решить durable recovery runtime state, late-interest resync, selective replication и scale policy, не меняя принятую границу canonical/presentation/transport.
