# FABRIC1 — GENERALIZED WORLD FABRIC — RESEARCH EXACT CLOSED

**Status:** `RESEARCH EXACT CLOSED` for the bounded FABRIC research definition. This is not a `main` product-checkpoint acceptance or production merge.

## Exact subject

- Branch: `research/fabric1-generalized-world-fabric-r1`
- Predecessor B0.7 closure: `01f166ec276d24884a96af7b8244194d1ab8ed70`
- Runtime HEAD: `63ca63b20e40a2065e742c62ff52acb7c95ade7e`
- Runtime TREE: `93ac849faf31ee904ffa74f3ae73ed73d76b3d16`
- Godot: `4.7.1.stable.double.custom_build.a13da4feb`
- Godot SHA-256: `bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7`
- Final fresh import: exit `0`, fatal markers `0`

Git compare from B0.7 final to the runtime candidate contains exactly eight new FABRIC1 paths. No B0.7 / COMPLEX3 / BRIDGE-3 / B0.6 predecessor runtime or test file was modified.

## Definition of done

The frozen research roadmap defines:

```text
FABRIC1
=
Constructible
+ Composable
+ Hybrid
+ Persistent
+ Reducible
+ Refinable
+ Deterministic
+ Causally scalable
```

This closure maps every term to executable evidence rather than treating it as a documentation checkbox.

### Constructible

`fabric1_component_contract_v1.gd` describes generic physical components as data: stable component identity, external ports, internal nodes and passive physical edges. The acceptance constructs three distinct components without a machine-specific runtime class.

### Composable

`fabric1_generalized_composer_v1.gd` composes components only through generic physical ports. Connected ports become internal; unbound ports become the composed physical boundary. Input component/connector order does not change the graph hash. Overlapping canonical node identity and double-bound ports fail closed.

### Hybrid

The new generalized lifecycle executes the same composed object in `BAKED` and `FULL` forms and performs `BAKED → FULL → canonical failure → FULL successor → REBAKE`. A fresh BRIDGE-2 mixed-representation closure also passed `122 + 125` assertions, preserving atomic mixed ownership/event-routing semantics. The full historical B0.5 suite is **not** claimed as freshly rerun: its expensive subject exceeded the bounded slice without an assertion failure, so the harness correctly prevented a third identical attempt.

### Persistent

The FABRIC1 capsule is explicitly `noncanonical + derived + discardable`; authoritative graph data is supplied independently on restore. Stale and corrupted capsules fail closed. In addition, fresh B0.6-D persistence passed `69 + 10 + 5` assertions including separate disk writer/reader Godot processes.

### Reducible

The composed machine is automatically reduced using the already frozen B0.7/B0.1 exact reduction path. No FABRIC1 device-specific solver or hand-written bake class is introduced.

| component width | FULL equations | BAKE equations | work ratio |
|---:|---:|---:|---:|
| 40 | 128 | 4 | 1024× |
| 56 | 176 | 4 | 1936× |
| 72 | 224 | 4 | 3136× |

Boundary flow/power parity remains within exact-double acceptance bounds.

### Refinable

The runtime performs an explicit `BAKED → FULL` refinement before a canonical topology mutation. Old bake execution is fenced with `STALE_PHYSICAL_BAKE_EXECUTION_FORBIDDEN`; the externally supplied canonical successor executes FULL and then automatically rebakes. Bounded **local** refinement is inherited without code modification from BRIDGE-3/COMPLEX3 rather than reimplemented here.

### Deterministic

Two complete fresh-process sets were run on byte-identical published runtime/test files:

```text
50 core assertions
+ 11 scale-40
+ 11 scale-56
+ 11 scale-72
= 83 assertions / replay
```

Both sets produced identical hashes:

```text
FABRIC1_CORE_HASH=0dd739404c2ed0b352abc08e7c93d9100213e7479dd2cd96da8a51f1f9509444
SCALE_40=c82de47d7b5a5fc1391ad569693d32c24f71a21a5bd547a171c7a235b8b75737
SCALE_56=31fc6aff13b0f9ff6cb8e2bfd0bb6bf136e0630d9c0504e0d797995cf0c942ec
SCALE_72=09695b7d32136669c74333e83b5900a0b351a30de3d517b4f4302f16d0f71a44
FABRIC1_REPLAY_HASH=b4695a2dd85ae5a937f5388a82ffc8448752b487e5660b29431e061d85dcb3ea
```

### Causally scalable

Two independent dimensions are covered:

1. the new generic composed machine grows from 128 → 224 FULL equations while its executable BAKE stays at four boundary equations and work advantage rises from 1024× → 3136×;
2. unchanged exact COMPLEX3 evidence proves `100,000 canonical parts → 20 active FULL parts`, `global rebuilds = 0`, `duplicate owners = 0` with two fresh replay sets.

Thus FABRIC1 does not equate world complexity with simultaneously expensive physical execution.

## Canonical failure semantics

The integration falsifier is:

```text
3 generic components
        ↓
generic port composition
        ↓
automatic exact BAKE
        ↓
BAKED execution
        ↓
refine to FULL
        ↓
external canonical edge failure
        ↓
old bake fenced immediately
        ↓
FULL successor changes downstream function
        ↓
automatic REBAKE
        ↓
derived restart capsule
        ↓
fresh runtime reproduces the successor state
```

FABRIC1 records zero canonical writes. Damage/topology truth continues to come from the external canonical source.

## Fresh predecessor boundaries

```text
B0.6-D:
  69 PASS
  disk writer 10 PASS
  disk reader 5 PASS
  recovery hash = f9613fe30c97322cfd1f81d6f74608a0bc58e51f6dbb8be6af37dff177ba8bba
  disk hash     = ab2287a06a5427e5d73f15b5c7a6ad11267f5f3c9aad1e519a4cdc5cc13fc1f9

BRIDGE-2:
  SYNC4 122 PASS
  mixed generic machine 125 PASS
```

## Unchanged inherited exact boundaries

- B0.7 closure: `3ed9d015cf4943fcf21c6ced514387a0e1162b5456e45051945693057a3392bb`
- COMPLEX3 closure: `e69c756494e0e10c7cf4ad9be7fdc9182a3f85ef6e6f8b43bcee344f29ddcc2f`
- COMPLEX3 replay: `d0a19061880c96ea262e75fa6e13b5debc8ca195510a3937c38b7650769d0c16`
- BRIDGE-3 closure: `4f9ec661e99775d0afc85995d51a4d614158414fc760141daffe0dab1b25f4a4`
- B0.6 closure: `892a66dbcb9e29c99ba7088a03dd41c167fd728a6f97923d4e944e4aef682584`

These are reused only because the FABRIC1 Git diff adds new paths and does not modify those runtime/test bytes.

## Project Control attribution

Local control evaluation on the current research workspace:

```text
standard PC0  = RED
exit          = 0 with --no-fail-on-red

directional  = GREEN
exit          = 0
```

The global RED belongs to other active product lines (G8, T1B, CH9.6, NX/V0, doctrine/ECO advisories). It is not converted into GREEN by this research closure. FABRIC1 therefore closes only the research-exact capability boundary and does not claim main product acceptance.

## Bounded claim

This milestone demonstrates a generalized integration of the already proven FABRIC/BAKE mechanisms. The new component/composer layer is currently a passive steady generic-power graph family. It does **not** claim arbitrary nonlinear/multi-domain automatic synthesis. Dynamic/hybrid/contact/local-unbake capabilities remain supplied by their exact predecessor modules and contracts, now integrated through a single lineage rather than rewritten as device-specific code.

## Final deterministic closure hash

```text
FABRIC1_CLOSURE_HASH=a652cfc238f5abc2574d5e2f664e578ab92f1ff1413d8706a4067c0dae4969a6
```

`FABRIC1 generalized world fabric = RESEARCH EXACT CLOSED`.
