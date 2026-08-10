# T1A.7.2 — Late-Interest Baseline + Reconnect — Implemented Candidate

**Дата:** 2026-08-10  
**Ветка:** `feature/t1a7-runtime-recovery-interest-scale`  
**Base:** T1A.7.1 ACCEPTED on runtime head `a1d856de348268c45eccfb1c4646720bc4a996db`  
**Candidate runtime head:** `f3d1b3fe49f8a42ca797eecb64b599c7fef92806`  
**Статус:** `IMPLEMENTED_CANDIDATE_WINDOWS_FOCUSED_PENDING`

## Reuse audit

T1A.7.2 не создаёт новый global interest manager и не вводит клиентский self-authoritative interest protocol.

Переиспользуются:

```text
MW7 pattern
  logical client interest revision
  transport session fence отдельно от logical state
  late authoritative baseline
  retained selection across reconnect
  stale/same-revision conflict rejection

M3/NX
  compatibility handshake
  peer -> logical player
  peer -> transport session
  RESYNC / RELIABLE_ORDERED

T1A.6
  ConstructionRuntimeSnapshot
  ConstructionRuntimeReplicaStore
  reliable full runtime baseline

T1A.7.1
  recoverable canonical runtime
```

Selection source остаётся внешним authoritative world/query/interest input. T1A.7.2 хранит только Construction-domain binding projection:

```text
logical client id
interest revision
selected construct ids
active peer + session transport binding
```

Это не permanent spatial identity.

## Implementation

Принятый T1A.6 server adapter получил только два default-safe extension hook:

```text
_create_t1_runtime()
_should_send_runtime_snapshot_to_peer(peer_id, reason)
```

Default T1A.6 остаётся:

```text
base T1 runtime
ALLOW_ALL runtime snapshot targets
```

T1A.7.2 override:

```text
recoverable T1A.7 runtime
interest-filtered runtime snapshot targets
```

`construction_runtime_interest_binding.gd` задаёт revision/session semantics. При late enter и reconnect используется существующий full `ConstructionRuntimeSnapshot` по `RESYNC / RELIABLE_ORDERED`.

Новый network message, channel или protocol-manifest entry не добавлялся.

## Focused acceptance scenario

```text
A joins gameplay
A has no D0 interest -> no Construction runtime snapshot
upstream selects D0 for A -> authoritative CLOSED baseline
A opens door -> A receives OPEN

B joins late
B has no D0 interest -> no D0 snapshot
upstream selects D0 for B -> B receives current OPEN baseline

B leaves D0 interest
A closes door
B receives no runtime mutation and retains cached OPEN replica

B re-enters D0
B receives current CLOSED baseline

B disconnects
logical interest state remains
B reconnects with new transport session
B receives current CLOSED baseline automatically
old session is not an active selected transport
```

Отдельный unit gate проверяет:

```text
same revision + same selection -> replay
same revision + different selection -> reject
older revision -> reject
stale disconnect session -> reject
logical selection survives disconnect
new session rebinds retained logical state
```

## Validation

Focused runner:

```powershell
.\RUN_T1A7_2_LATE_INTEREST_RECONNECT_TESTS.ps1 -GodotPath $Godot
```

Runner повторно включает accepted T1A.4/T1A.5/T1A.7.1, NX0, M3, C5C и T1A.6 graphical multiplayer acceptance, потому что T1A.7.2 добавляет extension hooks в принятый T1A.6 server adapter.

После focused PASS обязателен свежий:

```powershell
.\RUN_WORLD_REGRESSION_TESTS.ps1
```

## Не входит в T1A.7.2

```text
multi-construct dirty stream
bounded Construction delta replay
bandwidth optimization
world spatial query implementation
presentation eviction ownership
new network channel
```

Это оставлено T1A.7.3 / existing foundation owners.
