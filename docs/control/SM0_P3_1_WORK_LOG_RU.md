# SM0-P3.1 — work log

Status: **FINAL WAN MATRIX PASS / STOP-AND-WAIT MOVEMENT LIMIT IDENTIFIED / P4 DESIGN READY FOR HUMAN GATE**.

Branch-local experimental work only. No production/global/canonical acceptance is implied.

## Input evidence

P3 healthy localhost measurement was executed at exact HEAD `a3cd79a5688c5123a487406d0c539a0ee05e6a3c` on Godot `4.7.1.stable.double.custom_build.a13da4feb`.

Result: 25/25 measured manual crossings, total min/p50/p95/max = `12/18/25/25 ms`, average `19.2 ms`, `identity_changes=0`, `player/a` unchanged, movement magnitude `0.25`. Operator reported no perceptible transfer hitch.

Evidence commit:

- `880fcdc479587a527906019caf0b6fc657e067db` — `docs(sm0): record P3 healthy handoff latency evidence`.

## P3.1 implementation

Design:

- `17e263d76179b393a6ebcf23fbb1c0369715ebf7` — `docs(sm0): define P3.1 controlled network latency lab`.

Test-only transport shaping:

- `5aae145b624ef19cc6db0b386fb76fdb6491b21d` — deterministic authority egress delay node;
- `1650ab503e14ac652037a6ba713a8f8e2a390b3f` — deterministic graphical client egress delay node;
- `0ed575678a3f5e5e64803bd52d2b00bbedabee60` — authority process routing for explicit P3.1 profile;
- `eebf9de719a8d88cee27b2dbf5a4aad2b6cfa928` — graphical client routing for explicit P3.1 profile;
- `00c87b046ffdd28e1308aa95603fd97ec8b50ae2` — graphical runner profile wiring;
- `921785da8d2738f34dc28d5599dd734c75b670fd` — `RUN_V0_SM0_CONTROLLED_NETWORK_LATENCY_LAB.ps1` acceptance/measurement runner.

Default profile is `p31-controlled-latency-v1`, one-way `30 ms`, jitter `+/-5 ms`, seed `431`, intentional loss/duplicate/reorder all zero. Both authority and client UDP egress are delayed. Per-channel FIFO is retained.

The implementation does not insert frame sleeps, does not change authority mutation/persistence order, and does not modify the healthy handoff decision algorithm. The shaper is selected only by explicit network profile arguments.

## DEFAULT Windows observation

The operator ran the DEFAULT command on exact HEAD `4e961898a7418c9d14a167df7f789502f4d2c250` with Godot `4.7.1.stable.double.custom_build.a13da4feb` and reported that the example completed normally.

Subjective result: the authority-boundary transition has a small perceptible delay at `30 ms` one-way (`~60 ms` configured RTT), while movement after the transition remains normal and stable.

The pasted runtime excerpt contains six complete measured handoffs with total client-observed handoff latency:

```text
146 ms
171 ms
146 ms
176 ms
146 ms
153 ms
```

For those visible samples, `identity_changes=0`, `player_entity_id=player/a`, and canonical movement magnitude remains `0.25`.

## P3.1 FINAL WAN matrix implementation

Risk classification: **LOW**. This is a test/measurement-runner extension only. It does not modify the authority algorithm, canonical state, production networking, persistence, ownership, or runtime transport implementation.

Implementation commit:

- `7835362d18d36a26aa9b88af0377c85b1dbd5c59` — `test(sm0): add controlled WAN latency matrix runner`.

New runner:

```text
RUN_V0_SM0_CONTROLLED_NETWORK_LATENCY_MATRIX.ps1
```

The matrix executes four deterministic profiles in increasing order:

```text
WAN-10  one-way=10 ms  jitter=+/-2 ms  seed=431  configured RTT=20 ms
WAN-20  one-way=20 ms  jitter=+/-3 ms  seed=431  configured RTT=40 ms
WAN-30  one-way=30 ms  jitter=+/-5 ms  seed=431  configured RTT=60 ms
WAN-45  one-way=45 ms  jitter=+/-7 ms  seed=431  configured RTT=90 ms
```

Each profile runs the existing P3.1 acceptance runner in a separate PowerShell child process. Objective matrix PASS deliberately does not claim subjective seamlessness.

## P3.1 FINAL Windows runtime evidence

The operator executed the full matrix on exact runtime HEAD:

```text
2a5cbfa4488e1f6a6171f7c9ae0874b8b1379e1a
```

Godot:

```text
4.7.1.stable.double.custom_build.a13da4feb
```

Final machine result:

```text
SM0-P3.1 FINAL controlled WAN latency matrix: OBJECTIVE PASS
```

Measured summaries:

```text
WAN-10: one-way=10ms RTT=20ms jitter=+/-2ms | p50=73ms  p95=80ms  | phases=38+35ms   | A->B=73ms  B->A=73ms
WAN-20: one-way=20ms RTT=40ms jitter=+/-3ms | p50=110ms p95=130ms | phases=61+53ms   | A->B=109ms B->A=110ms
WAN-30: one-way=30ms RTT=60ms jitter=+/-5ms | p50=152ms p95=165ms | phases=75+76ms   | A->B=152ms B->A=158ms
WAN-45: one-way=45ms RTT=90ms jitter=+/-7ms | p50=213ms p95=243ms | phases=117+104ms | A->B=207ms B->A=231ms
```

Machine aggregate summary was written to:

```text
%LOCALAPPDATA%\DistributedWorldSimulator\SM0GraphicalLab\matrix\20260816-135556\controlled-network-latency-matrix-summary.json
```

All four profiles preserved the objective correctness gates enforced by the child runner. The matrix contains no authority/identity failure. Crossing samples preserve `player_entity_id=player/a`, `identity_changes=0`, and movement magnitude `|v|=0.25`.

### Handoff latency scaling

Across the four measured p50 points, a simple linear fit is approximately:

```text
handoff_p50_ms ~= 31 ms + 4.02 * one_way_latency_ms
```

This is diagnostic, not a protocol contract. It shows that the current post-crossing critical path behaves like roughly four additional serialized one-way network legs plus a localhost/processing baseline. That is consistent with the current PREPARE/COMMIT/REDIRECT/ACTIVATE sequencing and confirms that removing the post-crossing PREPARE round trip is the correct first P4 protocol optimization target.

At `WAN-30`, removing approximately one PREPARE RTT (`~60 ms`) gives an expected order of magnitude around `~90 ms`, matching the P4 design expectation. At `WAN-45`, the same reasoning gives roughly `~120-130 ms` before any presentation-side masking or prediction-through-handoff.

### Directional observation

Directional medians remain nearly symmetric through WAN-30. WAN-45 shows a larger branch-local difference:

```text
A->B p50 = 207 ms
B->A p50 = 231 ms
```

The `24 ms` difference is diagnostic only in this deterministic localhost shaper run. It did not produce a correctness failure and does not justify changing authority semantics by itself.

## Important new finding: ordinary movement becomes RTT-bound

The operator reported that movement in the final `WAN-45` graphical window was noticeably slower.

This is expected from the current SM0 graphical lab client implementation and is separate from the handoff pause.

Current loop behavior in `sm0_automated_client_node.gd` is stop-and-wait:

```text
send CLIENT_MOVE
wait until the single outstanding request receives MOVE_ACK
clear outstanding
only then allow the next CLIENT_MOVE
```

The nominal local send interval is `MOVE_INTERVAL_MS = 50`, but a new MOVE is allowed only when `_outstanding.is_empty()`.

The manual client also uses a fixed displacement per accepted command:

```text
MANUAL_MOVE_STEP = 0.25 m
```

Therefore effective movement speed is directly coupled to network RTT whenever MOVE RTT exceeds the nominal 50 ms cadence.

Approximate consequence:

```text
WAN-10  RTT~20ms  -> 50ms cadence can mostly dominate
WAN-20  RTT~40ms  -> near the 50ms cadence limit
WAN-30  RTT~60ms  -> movement starts becoming network-bound
WAN-45  RTT~90ms  -> movement is necessarily much slower with one outstanding MOVE
```

Ignoring processing/jitter, the current theoretical maximum fixed-step rate at WAN-45 is only about `1 / 0.09 ~= 11.1` moves/s, or about `2.8 m/s` for `0.25 m` commands, versus the nominal `20` moves/s / `5.0 m/s` at the 50 ms local cadence. Processing, jitter and handoff intervals reduce it further.

This explains the operator observation without implying an authority defect.

## Relationship to NX4

This finding must **not** be solved by inventing a second SM0-specific movement prediction architecture.

The repository already contains the accepted NX4 client prediction/reconciliation foundation:

- owner prediction enabled;
- server authority preserved;
- shared movement kernel `PlayerMovementService.apply_fixed_tick`;
- prediction at 60 Hz;
- server-tick keyed history;
- authoritative reconciliation with replay of unacknowledged ticks;
- no client transform authority.

Therefore the convergence direction is:

```text
SM0 authority handoff correctness
    + P4 prewarmed fast authority transfer
    + existing NX4 owner prediction/reconciliation semantics
```

not:

```text
SM0 bespoke stop-and-wait movement made increasingly complex
```

P4 solves the discrete authority-transfer stall. NX4-style local prediction/input buffering solves ordinary WAN movement responsiveness. These are separate latency layers and both are needed for genuinely seamless multiplayer.

## Next gate

P3.1 measurement is complete.

The next protocol-level candidate remains P4 prewarmed fast handoff, but P4 is a CRITICAL cross-server authority change and remains behind its documented human/reviewer gate before runtime mutation.

In parallel, the graphical SM0 convergence plan must explicitly replace the branch-local stop-and-wait presentation behavior with the existing NX4 prediction/reconciliation path rather than treating WAN-45 movement slowdown as a P4 defect.
