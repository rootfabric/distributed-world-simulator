# RTA0 — Realtime Action Temporal Foundation — Candidate R1

Статус: **CONTROL / DESIGN CANDIDATE — NOT ACCEPTED**

Exact base:

`main @ 5b44068d80439deb0f16597ddd36b546d68eebfa`

Назначение: зафиксировать минимальные temporal/action foundations до появления любого combat/history runtime.

## Frozen foundations

```text
TIME_IDENTITY
ACTION_IDENTITY
OBSERVED_STATE_IDENTITY
ROUTE_PRESERVATION
AUTHORITY_BOUNDARY
READ_ONLY_HISTORICAL_QUERY_CONCEPT
```

## Non-authority

Этот candidate:

```text
DOES NOT grant P6 runtime authority
DOES NOT activate SM1
DOES NOT activate EG runtime
DOES NOT implement combat
DOES NOT implement damage
DOES NOT implement weapons
DOES NOT allocate historical state buffers
DOES NOT implement server rewind
DOES NOT implement anti-cheat runtime
```

## Integration intent

- reuse/adapt accepted `InteractionTime` semantics rather than introduce competing time truth;
- keep `RealtimeActionId` bounded/ephemeral and distinct from durable `OperationId`;
- allow optional read-only observed-state evidence;
- preserve semantic action/time evidence across RoutePort/Gateway;
- keep client claims as evidence while authorities resolve canonical truth;
- reserve a read-only/non-canonical historical-query boundary without implementing storage.

## Machine evidence

Focused regression:

```text
python3 -m unittest tests.harness.test_rta0_realtime_action_temporal_foundation
```

Project Control is wired to parse the RTA0 machine contract and execute the focused regression on exact PR HEAD.

## Exit target

```text
RTA0_TEMPORAL_ACTION_FOUNDATION_CONTROL_PASS
```

Fresh exact-head review remains required before this control/design foundation can be treated as accepted architecture.
