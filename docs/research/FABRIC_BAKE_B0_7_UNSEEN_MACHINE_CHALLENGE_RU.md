# FABRIC-BAKE B0.7 — UNSEEN MACHINE CHALLENGE

## Status

`KERNEL FREEZE CANDIDATE / CHALLENGE NOT REVEALED`

Predecessor: `FABRIC COMPLEX3 — RESEARCH EXACT CLOSED`.

This line is research-only. It does not change Construction/Matter canonical ownership and does not authorize a main product merge.

## Purpose

B0.7 answers a generalization question that earlier fixed fixtures cannot answer:

```text
Can a frozen generic FABRIC/BAKE kernel accept a machine topology that did not exist when
that kernel was frozen, reduce it automatically, survive canonical topology failure, and
still reproduce the FULL boundary physics without adding a device-specific solver?
```

## Frozen physical mechanisms

The challenge reuses existing mechanisms rather than inventing a new per-machine law:

- `fabric0_conservation_fabric_v1.gd` — generic conservation substrate;
- B0.1 `exact_boundary_reducer_v1.gd` / exact Schur reduction;
- B0.1 `exact_boundary_bake_compiler_v1.gd` / source, authority, validity and conservation contracts;
- `exact_boundary_runtime_v1.gd` / stale-artifact execution gate;
- B0.7 generic graph contract/compiler — deterministic topology → passive linear boundary system only;
- B0.7 challenge protocol — FULL/reduced comparison, successor validation, stale fencing, deterministic rebuild and metrics only.

The B0.7 generic layer may assemble existing primitives, but it may not introduce a machine-name switch, a device-specific equation, or a hand-written bake class.

## Unseen protocol

B0.7 is intentionally split into two Git phases.

### Phase U0 — kernel freeze

Publish and exact-test:

```text
unseen_machine_generic_graph_v1.gd
unseen_machine_generic_compiler_v1.gd
unseen_machine_challenge_protocol_v1.gd
```

Then freeze their Git blob identities in a durable commit.

### Phase U1 — challenge reveal

Only after U0 exists as a remote commit:

1. derive challenge seeds from the immutable U0 commit SHA;
2. add previously absent machine fixture data/topologies;
3. add acceptance tests and runner;
4. do **not** edit the frozen solver/compiler/protocol bytes.

Any post-reveal change below `scripts/research/fabric0/`, `scripts/research/fabric_bake0/` or representation contracts invalidates the unseen claim and requires a new freeze generation.

## Mandatory challenge outcomes

For every revealed machine:

1. the base FULL system compiles from generic graph data;
2. exact BAKE is produced automatically;
3. FULL and BAKE agree on boundary flow and power within the declared envelope;
4. reduction is meaningful (`full_equation_count >> reduced_equation_count` and work ratio is recorded);
5. an externally supplied canonical topology successor changes a real downstream boundary outcome;
6. the pre-failure artifact is immediately non-executable after source revision advance;
7. the successor rebakes without a machine-specific class;
8. the successor FULL and BAKE results still agree;
9. the same canonical successor rebuilds to identical artifact/descriptor hashes;
10. exactly-once event ledger semantics are preserved;
11. at least one adversarial unsafe topology returns `NO_SAFE_BAKE` rather than inventing a reduction;
12. fresh-process replay produces the same deterministic challenge hashes.

Wall time and memory are recorded as observations only; they never authorize correctness.

## B0.7 closure rule

B0.7 may be marked `RESEARCH EXACT CLOSED` only if:

```text
kernel freeze is durable
+
challenge fixture first appears after freeze
+
post-freeze runtime diff = 0
+
all revealed machines PASS FULL↔BAKE + failure/rebuild
+
unsafe graph FAILS CLOSED
+
two fresh-process replay hashes match
```
