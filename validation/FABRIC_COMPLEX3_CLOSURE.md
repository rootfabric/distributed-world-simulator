# FABRIC COMPLEX3 — ADAPTIVE DAMAGE + LOCAL UNBAKE — RESEARCH EXACT CLOSED

**Status:** `CLOSED` for the bounded research-exact scope. This is not a main product-checkpoint acceptance or production merge.

## Exact subject

- Branch: `research/fabric-complex3-adaptive-damage-local-unbake-r1`
- Runtime HEAD: `4089b26dd1d56f3ab7bdee394cd1d5a7fbf150fa`
- Runtime TREE: `eb09719ad608aa9f3de5e9aeca39731450d1f4a1`
- Predecessor BRIDGE-3 closure: `d814a4135c5aea3d66148f037f89edf04444f063`
- Godot: `4.7.1.stable.double.custom_build.a13da4feb`
- Godot SHA-256: `bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7`
- Final fresh import: exit 0, fatal 0.

## What COMPLEX3 proves

The large canonical structure uses a frozen, addressable streaming recipe. The expensive physical lifecycle remains sparse:

```text
5k / 20k / 100k canonical parts
        ↓
certified STRUCTURAL_BAKE
        ↓
local guard
        ↓
20 FULL parts + 2 reduced residual bodies
        ↓
external canonical bond break / source revision
        ↓
old writer fenced
        ↓
settle
        ↓
2 fresh REBAKED components
```

FABRIC never mints canonical damage. The break is represented by a successor canonical source; stale execution is rejected. Restart capsules are derived/discardable, and stale/corrupt capsules cannot resurrect old ownership.

## Exact scale replay

Two fresh-process replay sets were run on the same runtime/test bytes. Every scale passed 40 assertions in both replays, and the per-scale deterministic hashes matched exactly.

| Canonical parts | FULL peak | Residual bodies | Final baked bodies | Local rebake validations | Metadata scanned | Global rebuilds | Duplicate owners | Observed wall time* |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 5,000 | 20 | 2 | 2 | 20 | 9,980 | 0 | 0 | ~1.10 s |
| 20,000 | 20 | 2 | 2 | 20 | 39,980 | 0 | 0 | ~3.44 s |
| 100,000 | 20 | 2 | 2 | 20 | 199,980 | 0 | 0 | ~16.52 s |

`*` Wall time is observational only and never participates in fidelity/safety decisions. Peak process RSS was about 129 MB in the recorded scale runs.

Per-scale hashes:

```text
5k      7d1ddf922cd3e3a7e61f83761be9f5a1a3ac0c35156c38825f5a11f8124982c1
20k     8762f4a2934d8d4ba31a46f697be895eb0b93d4e5c7ca639bc675ec488bbcea4
100k    2f2f11ad1e1694b0781fc8668e17795cd81ddac12c1af839f53974e84a353daf
REPLAY  d0a19061880c96ea262e75fa6e13b5debc8ca195510a3937c38b7650769d0c16
```

The 100k result therefore demonstrates the intended property: total canonical complexity grows by 20× from 5k to 100k while the active FULL island remains exactly 20 parts, with zero global physical rebuilds and zero duplicate ownership.

## Streaming source is not a weaker oracle

A separate 5,000-part explicit predecessor fixture was compiled with the existing structural aggregate compiler and compared against the streaming aggregate:

- 8/8 PASS
- mass error: `0`
- center-of-mass error: `0`
- max inertia-tensor error: `2.91038304567337e-11`
- reference hash: `34279a1ef04f4c4f4c6e1d8412c300793c050da277b626e0166d3c70a386acf4`

The streaming aggregate uses two passes (COM, then inertia about COM) to avoid catastrophic cancellation at long scale while keeping O(1) materialized memory and explicit O(N) metadata work.

## Source / benchmark contract

A0 passed twice with 26 assertions per replay:

```text
COMPLEX3_A0_HASH=73f632f3b8f10c412f1d769f695e854e707b78bf6bc8f0e0398f628a913764ef
```

The frozen source contract admits only 5k / 20k / 100k, preserves addressable identities, streams expanded part/bond digests, requires a one-revision canonical successor for the break, and rejects rehashed contradictory specifications.

## BRIDGE-3 boundary regression

Fresh boundary checks on the COMPLEX3 runtime candidate:

```text
BRIDGE3-A: 29 PASS
A_HASH=36d2da80dc6adda6f4ad998c2fd011add99dc8f718c9b1678f994d4f3cc72c30

BRIDGE3-F: 38 PASS
F_HASH=7eda96e277ef650f1f773630439502f095e666521378c0e740b577687d67aadb
F_CAPSULE_HASH=8f51c2eab36564a4f6060709fe582fc09ad7c1f09306063899454d9234e307fb
```

Git compare from the BRIDGE-3 closure head to the COMPLEX3 runtime subject contains only the nine new COMPLEX3 paths; predecessor runtime/test paths were not modified.

## Harness update

Large-scale work now follows `H0-SCALE-SHARD-2026-09-06-R1`, merged through PR #570. Required scale cases are independent durable predicates; a timeout may not shrink the required scale or cause already-green earlier cases to rerun. The timed-out case is profiled separately, and unchanged predecessor evidence may only be reused with blob-identity proof and honest attribution.

## Project Control attribution

The global standard PC0 currently reports `RED`, but the findings are outside this research work: an unrelated active product-checkpoint execution state and an unrelated ROAD-EXT-WAVE3 external/missing NF3 proof. The directional watch for the actual COMPLEX3 changed paths is `GREEN`, with zero critical watched-path intersections.

Therefore this record closes **COMPLEX3 research exact scope only**. It does not claim canonical main product acceptance and does not clear unrelated project-control blockers.

## Final hash

```text
COMPLEX3_CLOSURE_HASH=e69c756494e0e10c7cf4ad9be7fdc9182a3f85ef6e6f8b43bcee344f29ddcc2f
```

`B0.7 / Unseen Machine` remains not started.
