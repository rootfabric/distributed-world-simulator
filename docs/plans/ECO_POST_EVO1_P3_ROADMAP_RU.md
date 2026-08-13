# ECO — Post-EVO1 P3 Research Roadmap

Статус: `P3 RESEARCH ROUTE COMPLETE / P3.1..P3.8 ACCEPTED`.

Ветка: `feature/eco-evolutionary-ecology`.

Frozen EVO1 foundation: P2.8 aggregate `ba4e4bcef779764c86b20f1a76b452e0a2edcc88d351a1f9b4d2d41e10c420d6`.

## Completed sequence

1. P3.1 Resource Competition — ACCEPTED
2. P3.2 Density & Carrying Capacity — ACCEPTED
3. P3.3 Spatial Dispersal — ACCEPTED
4. P3.4 Environmental Gradient — ACCEPTED
5. P3.5 Seasonal World — ACCEPTED
6. P3.6 Disturbance & Succession — ACCEPTED
7. P3.7 Multi-Niche / Stable Coexistence — ACCEPTED
8. P3.8 Deterministic Ecosystem Persistence — ACCEPTED

## Final lifecycle — 2026-08-13

```text
P2.8 = ACCEPTED
P3.1 = ACCEPTED_EXACT_WINDOWS_CANONICAL
P3.2 = ACCEPTED_EXACT_WINDOWS_CANONICAL
P3.3 = ACCEPTED_EXACT_ATTACHED_GODOT_CANONICAL
P3.4 = ACCEPTED_EXACT_ATTACHED_GODOT_CANONICAL
P3.5 = ACCEPTED_EXACT_ATTACHED_GODOT_CANONICAL
P3.6 = ACCEPTED_EXACT_ATTACHED_GODOT_CANONICAL
P3.7 = ACCEPTED_EXACT_ATTACHED_GODOT_CANONICAL
P3.8 = ACCEPTED_EXACT_ATTACHED_GODOT_CANONICAL
```

For P3.3..P3.8 the Human-directed execution gate used the exact Godot build attached to the project. These records do not claim Windows execution where Windows was not run.

Exact engine used for attached-Godot acceptance:

```text
Godot 4.7.1.stable.double.custom_build.a13da4feb
```

## Frozen identities

```text
P3.1  f3e5ff9efbdee004cde58bc7de4a971cc9a17b51a13060cfc98df548c7cc425a
P3.2  172ff809b1442fc43c2534c46f1fe59363efda7d04a3f128832d61e39e144639
P3.3  37342327500b79f71ff2f5adbab51b659015311039ae5105eb00bb1705ac6c41
P3.4  a4464e5d42fb4a9e29c4a6ddfcb4c338ecbb4547bcd8bd80f430a7565df90813
P3.5  255912c4da9f1296d11f9e64bf91812ae3d32dff2726b4866c4ba761be8b8c83
P3.6  a7abcc49c2b9e7d473ceefb147996cb2febf6248bafe7004e3d5da01827cc5cc
P3.7  ef05ffb15d33819d3a6c4a1d534670e570ecb2ec674ad4a232e151e680a0e53a
P3.8  6132820a5c6597765b4f3abeeb8cf9fc9e6aaffb90ba83a1263997b17fc6f3a0
```

P3.8 persistence identity:

```text
checkpoint_sha256=1722f3ce96a8244bfaf2f8295c162b51552c6c5cc4cfd1126b40691a37bab367
final_state_hash=1395e6cdfc6dc5ea963b0d077fc00c618645c8866a7e47e822bcbdd98e429cf9
```

## Final P3.6 → P3.8 verification

Frozen exact-Godot evidence already committed before lifecycle promotion:

```text
P3.6: parent P3.5 regression PASS; A/B/C PASS, 33 assertions each, byte-identical
P3.7: A/B/C PASS, 64 assertions each, byte-identical
P3.8: parent P3.7 regression PASS; A/B/C PASS, 52 assertions each, byte-identical
P3.8: real writer process generation 5 PASS
P3.8: separate resume process generation 5 -> 12 PASS with exact uninterrupted final state
```

Fresh current-live-kernel integration smoke on the same exact attached Godot was also run twice after P3.5 acceptance and before P3.6/P3.7/P3.8 lifecycle promotion:

```text
P3.6-8 ATTACHED GODOT INTEGRATION: PASS
process_runs=2
checks_per_run=32
logs_byte_identical=true
log_sha256=18a21dfbc585326d971d88fda568d77e1a54ba84cef538c532ae73babfb03318
P3.6 fixture=388fc9500345691bd5fa4064787206de331b5cc862b3ed92dfb23fac819c64f5
P3.7 fixture=d8f47dc9c8f363d2bdf495b8279d4ee95f6f382032657a6b6bead081f95661ab
P3.8 initial fixture state=4935a05b3cce4a20c5bb293f71185d54ef7de48741b27af2b16cced789c85735
P3.8 final fixture state=1027eda45de0749ca30a0c49963a638e07277e191939c6ce10f78db806035412
P3.8 fixture serialization=58c251bf77a66793aa6a16e3dc42243372314e9b3c452f4ef4b539292d94b77e
```

The fixture hashes are supplemental current-head integration identities. They do not replace the frozen checkpoint aggregates.

## Research boundary

P3 completion proves deterministic research ecology mechanisms and deterministic persistence of the complete P3 research state. It does **not** by itself authorize production simulation ownership, production save/database format, distributed region/chunk ownership, server handoff, gameplay authority or networking policy.

The next route must be opened explicitly and must preserve the boundary:

```text
research ecology state != visual observer state != production/network authority
```
