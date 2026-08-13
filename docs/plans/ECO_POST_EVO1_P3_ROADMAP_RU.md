# ECO — Post-EVO1 P3 Research Roadmap

Статус: `ACTIVE RESEARCH ROUTE / P3.1..P3.8 IMPLEMENTED`.

Ветка: `feature/eco-evolutionary-ecology`.

Frozen EVO1 foundation: P2.8 aggregate `ba4e4bcef779764c86b20f1a76b452e0a2edcc88d351a1f9b4d2d41e10c420d6`.

## Sequence

1. P3.1 Resource Competition
2. P3.2 Density & Carrying Capacity
3. P3.3 Spatial Dispersal
4. P3.4 Environmental Gradient
5. P3.5 Seasonal World
6. P3.6 Disturbance & Succession
7. P3.7 Multi-Niche / Stable Coexistence
8. P3.8 Deterministic Ecosystem Persistence

## Current lifecycle — 2026-08-13

```text
P2.8 = ACCEPTED
P3.1 = ACCEPTED_EXACT_WINDOWS_CANONICAL
P3.2 = ACCEPTED_EXACT_WINDOWS_CANONICAL
P3.3 = ACCEPTED_EXACT_ATTACHED_GODOT_CANONICAL
P3.4 = ACCEPTED_EXACT_ATTACHED_GODOT_CANONICAL
P3.5 = ACCEPTED_EXACT_ATTACHED_GODOT_CANONICAL
P3.6 = CANDIDATE / targeted exact-Godot PASS / own canonical gate READY
P3.7 = CANDIDATE / targeted exact-Godot PASS / blocked on P3.6 ACCEPTED
P3.8 = CANDIDATE / targeted exact-Godot PASS / blocked on P3.7 ACCEPTED
```

## P3.3 → P3.5 Human-directed attached-Godot acceptance

Human directed execution of the next three lifecycle points with verification on the Godot attached to the project. For exactly these three points, the previous Windows-only execution requirement was superseded. No Windows PASS is claimed for P3.3/P3.4/P3.5.

Exact engine:

```text
Godot 4.7.1.stable.double.custom_build.a13da4feb
```

Frozen accepted identities:

```text
P3.3 aggregate=37342327500b79f71ff2f5adbab51b659015311039ae5105eb00bb1705ac6c41
kernel=43a25eb0e6677749162de99c251231c94d243dc1
test=9911c9197663098e1efa8875332b9d7c88ca34c6
full evidence: P3.2 regression PASS 79; P3.3 A/B/C PASS 66

P3.4 aggregate=a4464e5d42fb4a9e29c4a6ddfcb4c338ecbb4547bcd8bd80f430a7565df90813
kernel=11e2b281c48d378da906f0739c739eecf9aa8465
test=f3412bd53ebe7d647b83266e4945d758924ab66b
full evidence: P3.3 regression PASS 66; P3.4 A/B/C PASS 56

P3.5 aggregate=255912c4da9f1296d11f9e64bf91812ae3d32dff2726b4866c4ba761be8b8c83
kernel=649d26457ac8383f890f0dfca890353cc200ee7e
test=c91ed0c25c418be1a7c7c4352423b7214c8706f8
full evidence: P3.4 regression PASS 56; P3.5 A/B/C PASS 74
```

Fresh current-head integration recheck on the attached engine used byte-identical current P3.3/P3.4/P3.5 kernels. A strict minimal P3.2 validator was used only at the P3.3 parent boundary; the kernels under test were unchanged GitHub blobs. Result:

```text
P3.3-5 ATTACHED GODOT INTEGRATION: PASS
checks_per_run=21
total_checks=43
P3.3 fixture=b248455bccd179065f11b8a86d9c8d3d0c39100265f967b5ad5850f98498d135
P3.4 fixture=6c4da52f0ca5da551236df7c8c2051545d60ef62a9751ae0a40e86b48ecbc720
P3.5 fixture=a28031d525fed077b23023d04fbe005e355eb6b77b3d06af7a731836324275dd
```

Those fixture hashes are supplemental smoke identities; they do not replace the frozen aggregates above.

## Remaining critical path

```text
P3.6 own canonical gate
-> accept P3.6
-> P3.7 own canonical gate
-> accept P3.7
-> P3.8 own canonical gate
-> accept P3.8
-> P3 route canonically complete
```

The attached-Godot Human override above applies only to the requested P3.3/P3.4/P3.5 steps. P3.6 onward must satisfy their own lifecycle authorization before acceptance.

## Research/production boundary

P3 remains research ecology. Production integration is separate and must later prove region/chunk ownership, persistence, catch-up and server handoff without changing ecological history when ownership moves between servers.

Observer rule remains:

```text
simulation state != visual state != network transport
```
