# FABRIC-BAKE B0.7 — UNSEEN MACHINE CHALLENGE — RESEARCH EXACT CLOSED

**Status:** `RESEARCH EXACT CLOSED`

This closes the bounded B0.7 research gate. It is not a main product-checkpoint acceptance and does not merge FABRIC research into `main`.

## Exact lineage

- predecessor COMPLEX3 closure: `b39bc28499f47d34c5a0b7c02f223baf9f373a00`
- generic kernel code head: `286b1a0c538910e68a8b4424e5bf59a1c5d47630`
- immutable kernel freeze head: `9dda6872081c19ce2add86bb590a9aa4925c6ac9`
- exact runtime/challenge candidate: `33b2405bd9962e530216721717dae6541109b17c`
- runtime tree: `a543c9c728f2fdf7fa9ad81ebba23a4c9a6ff005`
- Godot: `4.7.1.stable.double.custom_build.a13da4feb`
- Godot SHA-256: `bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7`

Final fresh import: `exit 0`, fatal markers `0`.

## Why the machines were actually unseen

The generic graph/compiler/protocol was published and exact-tested first. The freeze manifest was then committed at `9dda687...` while the challenge fixture did not exist.

Only after that freeze were the machine topologies created. Their identities and topology parameters are deterministic functions of the freeze SHA itself.

Git compare from the freeze to the exact challenge candidate contains exactly three files:

```text
RUN_FABRIC_B0_7_TESTS.sh
tests/research/fabric_bake0/fabric_bake_b0_7_unseen_machine_acceptance.gd
tests/research/fabric_bake0/unseen_machine_challenge_fixture_v1.gd
```

No frozen physical/compiler/protocol script changed after reveal.

Frozen runtime blobs:

```text
unseen_machine_generic_graph_v1.gd       61f93a0e53584545e7532e389f591b05a1a09a98
unseen_machine_generic_compiler_v1.gd    307eb564db9dd6208f3a4d972380a6d7bb35dff4
unseen_machine_challenge_protocol_v1.gd  1c12fd56afe485e36977854ccdbce3e6a3034bfd
```

## Generic kernel result

The frozen pre-challenge kernel was replayed again after the challenge reveal:

```text
22 / 22 PASS
FULL equations    = 132
REDUCED equations = 4
work ratio         = 1089x
KERNEL_HASH        = 9d117d310cc81eb84b6763c9daf1f08bb7ecbf5e31443c7ff2c81acb85b21d7b
```

It uses the existing B0.1 exact Schur reduction path rather than a per-machine bake class.

## Unseen challenge results

Each machine was generated from generic nodes/edges and then subjected to a canonical topology successor that removes one declared critical output edge. The old artifact must become non-executable immediately, the successor must rebake, and FULL/BAKE must remain equivalent.

| case | hidden states | FULL eq | BAKE eq | work ratio | max flow error | max power error | downstream flow delta |
|---|---:|---:|---:|---:|---:|---:|---:|
| alpha | 136 | 140 | 4 | 1225x | 1e-14 | 7e-14 | 1.74827114768009 |
| beta | 168 | 172 | 4 | 1849x | 1e-14 | 7e-14 | 3.48570642155629 |
| gamma | 192 | 196 | 4 | 2401x | 0 | 4e-14 | 1.20416685096602 |

So correctness and meaningful reduction coexist. The unknown topology grows, the automatic BAKE remains four boundary equations, and the reduction advantage increases with hidden-state size.

Every machine also proves:

- stale pre-failure artifact → `STALE_PHYSICAL_BAKE_EXECUTION_FORBIDDEN`;
- exactly one declared canonical edge-loss event;
- successor rebuild is deterministic by artifact and descriptor checksum;
- failure has a real downstream functional consequence, not merely a changed hash.

## Fail-closed guard

A structurally well-formed machine with an isolated hidden state produces:

```text
NO_SAFE_BAKE
reason = RANK_DEFICIENCY
```

A separately well-formed successor that secretly changes edge conductance is rejected with:

```text
B0_7_SUCCESSOR_EDGE_METADATA_CHANGED
```

The kernel therefore does not invent a bake for an unsafe graph and does not allow the challenge to smuggle in a changed physical law as a topology event.

## Fresh-process replay

The four sharded predicates (`alpha`, `beta`, `gamma`, `guard`) were executed in two complete fresh-process sets on byte-identical published fixture/test/runner files.

Per-set assertion count: `71`.

```text
alpha  749c3330d0f42aa04fb03d99528a4764a85b64607bf0280577f21a48487f2ea9
beta   d685797fd3b2d2cbb711d175fb5662fdea35e9053c71b2b19abbde38ed969963
gamma  bc9a7bc1b9cf4136f6cdcc30eda63a8886ca0264aaf342e1974eda4e9c19df22
guard  511250652cf907507b79576dffad39ea7dbbf09b64e1cdca021fd4618d795abe

REPLAY_EQUAL = true
B0_7_REPLAY_HASH = b48625f224522bfec3bac8234bc529fb7084b02d5474df92bcb0404407099cb7
```

## Predecessor regression

Fresh B0.1 regression after challenge reveal:

```text
B0.0: 33 PASS
B0.1: 64 PASS
FULL=132 REDUCED=4
internal_rank=128 reduced_rank=3
work_ratio=1089x
max_flow_error=9e-14
max_power_error=1.42e-12
```

The old exact reducer was not modified to fit the challenge.

## Metrics boundary

For this passive, steady generic-power family:

- effort/flow and power: measured;
- topology event/failure point: measured and asserted;
- validity/refinement: source-revision invalidation, stale fencing, deterministic successor rebake;
- states/equations/work ratio: recorded;
- CPU: compile/evaluation wall observations recorded but never used as correctness authority;
- memory: Godot `Performance.MEMORY_STATIC` observation recorded;
- solver iterations: not applicable because the reference path uses a direct dense exact solve;
- energy/momentum/nonlinear mode transitions: not applicable to this memoryless steady primitive family;
- local-unbake cost: not exercised here; bounded local-unbake is predecessor COMPLEX3 evidence.

This claim is intentionally bounded: B0.7 proves frozen-kernel generalization for previously absent passive steady generic-power machine topologies. It does **not** claim arbitrary nonlinear, dynamic or multi-domain machine synthesis.

## Closure

```text
frozen generic kernel
        ↓
freeze commit
        ↓
SHA-derived previously absent machines
        ↓
FULL FABRIC reference
        ↓
automatic exact BAKE
        ↓
boundary parity
        ↓
canonical topology failure
        ↓
stale artifact fenced
        ↓
deterministic successor rebake
        ↓
fresh replay equality
```

`B0.7 / Unseen Machine Challenge = RESEARCH EXACT CLOSED`

```text
B0_7_CLOSURE_HASH=3ed9d015cf4943fcf21c6ced514387a0e1162b5456e45051945693057a3392bb
```
