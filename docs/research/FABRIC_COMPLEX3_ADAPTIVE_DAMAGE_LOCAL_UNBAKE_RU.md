# FABRIC COMPLEX3 — ADAPTIVE DAMAGE + LOCAL UNBAKE

## Status

**RESEARCH EXACT CLOSED.** This line opened only after exact BRIDGE-3 closure and is now closed for its bounded 5k → 20k → 100k research scope.

Runtime subject: `4089b26dd1d56f3ab7bdee394cd1d5a7fbf150fa`, TREE `eb09719ad608aa9f3de5e9aeca39731450d1f4a1`.
Predecessor BRIDGE-3 closure head: `d814a4135c5aea3d66148f037f89edf04444f063`.
Exact Godot: `4.7.1.stable.double.custom_build.a13da4feb`, SHA-256 `bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7`.
Closure hash: `e69c756494e0e10c7cf4ad9be7fdc9182a3f85ef6e6f8b43bcee344f29ddcc2f`.

This is research exact closure only. It does not merge simulation runtime to `main`, change production authority, clear unrelated Project Control blockers, or activate B0.7.

## Proven result

COMPLEX3 proves that canonical complexity can grow while expensive physical detail remains sparse and causal:

```text
5k / 20k / 100k canonical addressable parts
        ↓
mostly BAKED / reduced
        ↓
local certified guard
        ↓
exactly 20 LOCAL FULL parts
+ 2 residual reduced bodies
        ↓
external canonical bond break / source revision
        ↓
stale writer fenced
        ↓
settle
        ↓
2 fresh REBAKED components
```

Canonical Construction/Matter remains the truth. FABRIC owns only derived physical execution representations and never mints canonical damage.

## Scale closure

Each scale ran twice in fresh processes on the same runtime/test bytes. Each case passed 40 assertions in both replays.

| Canonical parts | FULL peak | Residual bodies | Final baked bodies | Local rebake validations | Global rebuilds | Duplicate owners | Case hash |
|---:|---:|---:|---:|---:|---:|---:|---|
| 5,000 | 20 | 2 | 2 | 20 | 0 | 0 | `7d1ddf922cd3e3a7e61f83761be9f5a1a3ac0c35156c38825f5a11f8124982c1` |
| 20,000 | 20 | 2 | 2 | 20 | 0 | 0 | `8762f4a2934d8d4ba31a46f697be895eb0b93d4e5c7ca639bc675ec488bbcea4` |
| 100,000 | 20 | 2 | 2 | 20 | 0 | 0 | `2f2f11ad1e1694b0781fc8668e17795cd81ddac12c1af839f53974e84a353daf` |

Fresh replay aggregate:

```text
COMPLEX3_REPLAY_HASH=d0a19061880c96ea262e75fa6e13b5debc8ca195510a3937c38b7650769d0c16
```

The key scaling property is therefore explicit: from 5k to 100k canonical parts (20× growth), the hot physical reveal stays at exactly 20 FULL parts. Metadata/index work remains explicitly O(N); hot reconstruction and local rebake validation do not grow with total part count in this experiment.

Observed wall times were approximately 1.10 s / 3.44 s / 16.52 s for 5k / 20k / 100k, with recorded process peak RSS around 129 MB. Wall time is observation only and never authorizes safety/fidelity decisions.

## Source / benchmark contract

The large source is a frozen deterministic streaming recipe for exactly 5k / 20k / 100k addressable canonical parts. It preserves stable part/bond/region IDs and expanded streaming digests without materializing every record simultaneously.

A0 passed twice, 26 assertions each:

```text
COMPLEX3_A0_HASH=73f632f3b8f10c412f1d769f695e854e707b78bf6bc8f0e0398f628a913764ef
```

A separate explicit 5,000-part predecessor fixture was compiled with the established structural aggregate compiler and compared with the streaming aggregate:

```text
8/8 PASS
mass error    = 0
COM error     = 0
max inertia error = 2.91038304567337e-11
reference hash = 34279a1ef04f4c4f4c6e1d8412c300793c050da277b626e0166d3c70a386acf4
```

The streaming aggregate therefore does not replace the physical reference with a weaker oracle. It uses two passes — first COM, then inertia about COM — to avoid catastrophic cancellation at long scale while retaining O(1) materialized memory.

## Lifecycle invariants closed

All declared COMPLEX3 predicates are satisfied:

1. one canonical source truth; no derived canonical writes;
2. one active physical owner per region;
3. stale execution rejected after canonical mutation;
4. local guard reveals only the 20-part causal island;
5. BAKE → LOCAL FULL continuity is checked for boundary, mass, momentum and energy;
6. topology/damage mutation is external to the representation controller;
7. settled fragments rebake into two executable reduced components;
8. no lost/duplicated lifecycle event;
9. restart capsules are derived/discardable; stale/corrupt capsules cannot resurrect old ownership;
10. two fresh-process scale replays produce identical deterministic hashes.

Fresh BRIDGE-3 boundary regressions also passed on the COMPLEX3 subject: A = 29 PASS, F = 38 PASS, with the original BRIDGE-3 deterministic hashes preserved.

## Harness changes used by this campaign

`H0-STALL-GUARD-2026-09-06-R1` prevents silent long retry loops. `H0-SCALE-SHARD-2026-09-06-R1`, merged through PR #570, makes 5k / 20k / 100k independent durable predicates. A timeout cannot reduce the required scale or cause already-green earlier cases to rerun; only the timed-out case is profiled/retried, and unchanged predecessor evidence may be reused only with exact blob-identity proof and honest attribution.

## Project Control

Directional watch for the actual COMPLEX3 changed paths is **GREEN**, with zero critical watched-path intersections.

The global standard PC0 is currently **RED** because of unrelated product-control state outside this research work (an active checkpoint execution-state issue and an external/missing ROAD-EXT-WAVE3 NF3 proof). COMPLEX3 does not claim to clear those blockers and does not claim main product acceptance.

## Durable evidence

- `validation/FABRIC_COMPLEX3_CLOSURE.md`
- `validation/fabric_complex3/exact-replay.v1.json`

## Roadmap

```text
B0.6 Adaptive Physical Fidelity       ✅ CLOSED
        ↓
BRIDGE-3 Full/Bake/Local-Unbake       ✅ CLOSED
        ↓
COMPLEX3 5k → 20k → 100k             ✅ RESEARCH EXACT CLOSED
        ↓
B0.7 Unseen Machine Challenge          ⏸ NOT STARTED
```

B0.7 remains downstream and is not started by this closure.
