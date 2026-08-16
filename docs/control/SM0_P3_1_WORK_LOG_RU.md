# SM0-P3.1 — work log

Status: **DEFAULT OPERATOR OBSERVED / FINAL WAN MATRIX IMPLEMENTED / WINDOWS MATRIX PENDING**.

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

The pasted excerpt does not contain the final runner summary after all required crossings. Therefore this work log does **not** fabricate a machine `10/10 PASS` claim from the partial transcript. The FINAL matrix intentionally re-runs the `30 ms` profile and will produce a fresh exact-head machine summary.

## P3.1 FINAL WAN matrix

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

The range is intentionally concentrated around the first observed perceptible point instead of jumping directly to extreme WAN conditions.

Each profile runs the existing P3.1 acceptance runner in a separate PowerShell child process. This is required because the child runner intentionally terminates with `exit`; direct in-process invocation would terminate the whole matrix after the first profile.

For every profile the matrix requires the child summary to match:

- exact Git HEAD;
- expected latency/jitter/seed;
- expected summary schema;
- minimum measured handoff count;
- all identity, movement, route-continuity, latency-accounting and invariant gates already enforced by the child runner.

The aggregate summary records objective p50/p95 latency, phase medians, direction medians, configured RTT, p50/RTT ratio and the delta from the previous profile.

Aggregate output:

```text
%LOCALAPPDATA%\DistributedWorldSimulator\SM0GraphicalLab\matrix\<timestamp>\controlled-network-latency-matrix-summary.json
```

Objective matrix PASS deliberately does not claim subjective seamlessness. The operator must report the first profile where the boundary transition becomes perceptible.

## Runtime gate now required

Run on the exact current branch HEAD:

```powershell
.\RUN_V0_SM0_CONTROLLED_NETWORK_LATENCY_MATRIX.ps1 -Restart -RequireHandoffs 10
```

For each of the four graphical windows, cross the A/B boundary at least ten times and then close the window. The next profile starts automatically.

Required operator result after the runner finishes:

1. the final `SM0-P3.1 FINAL controlled WAN latency matrix: OBJECTIVE PASS` block;
2. the first profile where the boundary transition becomes perceptible (`WAN-10`, `WAN-20`, `WAN-30`, or `WAN-45`), plus whether normal movement away from the boundary remains smooth.

If any profile reveals a compile/runtime/harness defect, record the exact tested SHA and repair it as a new atomic branch commit before re-running. Do not reinterpret a harness defect as protocol evidence.

After a clean matrix, the next protocol-level step is a separate P4 latency-hiding design/implementation candidate (pre-warmed target route / overlap or equivalent). That step is authority-protocol work and must be treated as HIGH/CRITICAL according to the canonical review route; it must not be smuggled into this LOW-risk measurement commit.
