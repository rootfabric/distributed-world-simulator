# SM0-P3.1 — work log

Status: **IMPLEMENTED / WINDOWS RUNTIME DEFAULT PENDING**.

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

## Runtime gate now required

The next source of truth is the exact Windows runtime on the pinned double Godot build. DEFAULT must be run before any FINAL/matrix extension or runtime evidence is declared.

Expected user command is the P3.1 runner with `-Restart -RequireHandoffs 10`. The operator should manually cross at least ten times, note whether the boundary transfer becomes perceptible under the controlled profile, close the graphical window, and preserve the emitted summary.

If DEFAULT reveals a compile/runtime/harness defect, record the exact tested SHA and repair as a new atomic branch commit before re-running. Do not reinterpret a harness defect as protocol evidence.
