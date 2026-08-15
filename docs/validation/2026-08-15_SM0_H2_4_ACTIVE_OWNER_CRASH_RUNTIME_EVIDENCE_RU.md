# SM0-H2.4 — ACTIVE OWNER CRASH RUNTIME EVIDENCE

Date: 2026-08-15

Branch: `feature/sm0-two-authority-seamless-handoff-lab`

Exact tested HEAD:

`884ca425bae514a40f1a8fa67f3af8975d3247b4`

Runtime:

`Godot 4.7.1.stable.double.custom_build.a13da4feb`

Windows gate:

`RUN_V0_SM0_ACTIVE_OWNER_CRASH_ACCEPTANCE.ps1 -Final -Restart`

## Result

PASS.

The final process-level run used six requested handoffs and forced an actual process crash of the currently active authority before the successful MOVE acknowledgement was allowed to reach the client.

Observed final-run evidence:

- healthy preflight: PASS;
- compile smoke: PASS;
- handoff motion import regression: PASS (22 assertions);
- active-owner durable ACK regression: PASS (41 assertions);
- crashed authority A PID: `17280`;
- restarted authority A PID: `19132`;
- crash recovery generation: `2`;
- durable input sequence at the crash boundary: `1`;
- durable position X at the crash boundary: `-4.5`;
- ownership epoch transition after recovery rebind: `1 -> 2`;
- completed handoffs after recovery: `6 / 6`;
- identity changes: `0`;
- SM0 log analysis: PASS;
- total analyzed events in final process run: `154`.

The non-final process run also passed with `2 / 2` handoffs, crashed PID `3320`, restarted PID `13644`, the same durable sequence/position boundary, and zero identity changes.

## Proven ordering

The runtime demonstrated the required durability ordering:

1. the active owner accepted MOVE sequence `1` and changed canonical position to `x=-4.5`;
2. an `ACTIVE_OWNER` recovery snapshot was persisted;
3. `SM0_H2_CRASH_POINT` was emitted before the corresponding successful MOVE ACK was delivered;
4. the authority process was force-killed externally;
5. a new process restored the exact `ACTIVE_OWNER` generation;
6. durable player state was restored disconnected from transport;
7. the outstanding exact input retry rebound the client session with ownership epoch incremented;
8. the retry was classified as `duplicate_durable_input=true` and did not apply movement twice;
9. normal movement and subsequent cross-authority handoffs continued.

The focused runtime regression additionally demonstrated that after the exact retry kept `seq=1` and `x=-4.5`, the next input `seq=2` advanced the player exactly once to `x=-4.0`.

## Interpretation

H2.4 closes the initial-owner arbitrary-crash durability boundary for acknowledged movement. An acknowledged canonical MOVE is no longer allowed to exist only in volatile process memory when active-owner recovery is enabled.

This is a correctness implementation. The current write-before-ACK snapshot strategy is intentionally conservative and may later be replaced by WAL/group commit without weakening the externally proven ordering contract.

This evidence is bounded to the SM0 two-authority seamless handoff lab. It does not by itself declare a global V0/main checkpoint accepted.
