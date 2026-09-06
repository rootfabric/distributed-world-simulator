# FABRIC-BAKE B0.7 — UNSEEN MACHINE CHALLENGE

## Status

`RESEARCH EXACT CLOSED`

Predecessor: `FABRIC COMPLEX3 — RESEARCH EXACT CLOSED`.

Exact closure evidence:

- runtime candidate: `33b2405bd9962e530216721717dae6541109b17c`;
- runtime tree: `a543c9c728f2fdf7fa9ad81ebba23a4c9a6ff005`;
- kernel freeze: `9dda6872081c19ce2add86bb590a9aa4925c6ac9`;
- replay hash: `b48625f224522bfec3bac8234bc529fb7084b02d5474df92bcb0404407099cb7`;
- closure hash: `3ed9d015cf4943fcf21c6ced514387a0e1162b5456e45051945693057a3392bb`.

This line is research-only. It does not change Construction/Matter canonical ownership and does not authorize a main product merge.

## Purpose

B0.7 answers a generalization question that earlier fixed fixtures cannot answer:

```text
Can a frozen generic FABRIC/BAKE kernel accept a machine topology that did not exist when
that kernel was frozen, reduce it automatically, survive canonical topology failure, and
still reproduce the FULL boundary physics without adding a device-specific solver?
```

Result: **yes for the bounded passive steady generic-power family exercised by B0.7**. This does not claim arbitrary nonlinear, dynamic or multi-domain machine synthesis.

## Frozen physical mechanisms

The challenge reuses existing mechanisms rather than inventing a new per-machine law:

- generic conservation-compatible graph semantics;
- B0.1 `exact_boundary_reducer_v1.gd` / exact Schur reduction;
- B0.1 `exact_boundary_bake_compiler_v1.gd` / source, authority, validity and conservation contracts;
- `exact_boundary_runtime_v1.gd` / stale-artifact execution gate;
- B0.7 generic graph contract/compiler — deterministic topology → passive linear boundary system only;
- B0.7 challenge protocol — FULL/reduced comparison, successor validation, stale fencing, deterministic rebuild and metrics only.

The B0.7 generic layer has no machine-name switch, device-specific equation, or hand-written bake class.

## Unseen protocol — executed

B0.7 was split into two Git phases.

### Phase U0 — kernel freeze

The generic graph/compiler/protocol was published and exact-tested first. Two fresh kernel runs produced:

```text
22 / 22 PASS
FULL=132
REDUCED=4
WORK_RATIO=1089x
KERNEL_HASH=9d117d310cc81eb84b6763c9daf1f08bb7ecbf5e31443c7ff2c81acb85b21d7b
```

The durable freeze manifest is `9dda6872081c19ce2add86bb590a9aa4925c6ac9`. At that commit, the challenge fixture path did not exist.

### Phase U1 — challenge reveal

Only after U0 existed remotely:

1. challenge seeds were derived from the immutable U0 commit SHA;
2. three previously absent machine topologies were added;
3. acceptance and sharded runner were added;
4. frozen solver/compiler/protocol bytes were not edited.

Git compare `9dda687... → 33b2405...` contains exactly three post-freeze files: the fixture, acceptance, and runner.

## Exact unseen results

| case | hidden states | FULL equations | BAKE equations | work ratio | downstream flow delta |
|---|---:|---:|---:|---:|---:|
| alpha | 136 | 140 | 4 | 1225x | 1.74827114768009 |
| beta | 168 | 172 | 4 | 1849x | 3.48570642155629 |
| gamma | 192 | 196 | 4 | 2401x | 1.20416685096602 |

FULL↔BAKE max flow error was at most `1e-14`; max power error was at most `7e-14`.

Every machine proved:

1. base FULL system compiles from generic graph data;
2. exact BAKE is produced automatically;
3. FULL and BAKE boundary flow/power agree;
4. reduction is meaningful and grows with hidden-state complexity;
5. one external canonical topology successor changes a real downstream result;
6. the pre-failure artifact becomes immediately non-executable;
7. successor rebakes without a machine-specific class;
8. successor FULL/BAKE parity remains green;
9. rebuild artifact/descriptor checksums are deterministic;
10. event ledger remains exactly-once.

## Fail-closed behavior

The adversarial structurally valid graph with one isolated hidden state returned:

```text
NO_SAFE_BAKE
RANK_DEFICIENCY
```

A well-formed successor attempting to silently change conductance was rejected as:

```text
B0_7_SUCCESSOR_EDGE_METADATA_CHANGED
```

## Fresh-process replay

The four durable predicates `alpha`, `beta`, `gamma`, `guard` were executed in two complete fresh-process sets on byte-identical published files.

```text
71 assertions per set
REPLAY_EQUAL=true
B0_7_REPLAY_HASH=b48625f224522bfec3bac8234bc529fb7084b02d5474df92bcb0404407099cb7
```

## Predecessor regression

After challenge reveal and fresh import:

```text
B0.0: 33 PASS
B0.1: 64 PASS
FULL=132 REDUCED=4
work_ratio=1089x
max_flow_error=9e-14
max_power_error=1.42e-12
```

The exact B0.1 reducer therefore remained unchanged and green.

## Metrics boundary

For this passive steady generic-power family:

- effort/flow and power: measured;
- events/failure point: measured and asserted;
- validity/refinement: source-revision invalidation, stale fencing, deterministic successor rebake;
- states/equations/work ratio: recorded;
- compile/evaluation CPU time and Godot static memory: observations only, never correctness authority;
- direct dense exact solve has no iterative solver count;
- energy, momentum and nonlinear mode transitions are not applicable to this memoryless steady primitive family;
- local-unbake cost is not re-proved here; bounded local-unbake remains predecessor COMPLEX3 evidence.

## Closure

```text
kernel freeze is durable                         PASS
challenge fixture first appears after freeze    PASS
post-freeze frozen runtime diff                  0
three unseen machines FULL↔BAKE                  PASS
canonical failure + stale fencing + rebake       PASS
unsafe graph fail-closed                         PASS
two fresh-process replay sets                    MATCH
meaningful complexity reduction                  PASS
```

Therefore:

```text
B0.7 / Unseen Machine Challenge = RESEARCH EXACT CLOSED
B0_7_CLOSURE_HASH=3ed9d015cf4943fcf21c6ced514387a0e1162b5456e45051945693057a3392bb
```
