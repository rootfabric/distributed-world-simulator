# FABRIC-BAKE B0.2-E — Closure record

## Qualification

```text
FABRIC-BAKE B0.2-E
TOPOLOGY SPLIT / RE-BAKE

RESEARCH SLICE CLOSED
EXACT-HEAD DOUBLE PASS
B0.0/B0.1/B0.2-A/B/C/D REGRESSION PASS
EXACT-ONCE TOPOLOGY EVENT PASS
OLD REDUCED PIECES INVALIDATED
2 POST-SPLIT BAKE_READY ARTIFACTS
STATE / MASS / MOMENTUM HANDOFF PASS
DETERMINISTIC EVENT + TRANSACTION IDENTITIES
TRACKED TREE BYTE-CLEAN
WINDOWS PASS_BY_POLICY / NON-GATING

PRODUCTION ACCEPTANCE NOT CLAIMED
```

## Executable subject

```text
branch:
research/fabric-bake0-2-e-topology-split-rebake-r1

HEAD:
91a2f79bf6738efefa342589c44e4a0f0a6960d6

TREE:
610288ea119e9f7508f711ce5b0468b272a9b489

parent:
762ef5d4b3094d021b3f9f956b3d0cf049a2a38c
```

The subsequent closure commit is docs/evidence-only and is not the executable acceptance
subject.

## Exact evidence

```text
Godot:
4.7.1.stable.double.custom_build.a13da4feb

Godot SHA-256:
bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7

source-export run:
33370961820

artifact:
9750024058
fabric-bake-b0-2-e-exact-source-91a2f79b

artifact digest:
sha256:b26d0f49c6a5e0235c5d8e235c274ee201437154158fe78f23646426b69872c4

archive SHA-256:
d700bd6212913693c4d48e02db08a0fa7bde46013642ee5b75f479aaa19c07fc
```

Each fresh exact-head pass:

```text
B0.0       33/33 PASS
B0.1       64/64 PASS
B0.1 PG    PASS
B0.2-A/B   76/76 PASS
A/B PG     PASS
B0.2-C     118/118 PASS
C PG       PASS
B0.2-D     609/609 PASS
D PG       PASS
B0.2-E     2580/2580 PASS
E PG       PASS
```

Deterministic E output:

```text
split=2
sizes=[243,257]
invalidated=3
artifacts=2
dof=6500->286->26
ratio=250.000000
mass_err=0.0
linear_err=0.00000000000017
angular_err=0.00000000001475
state_err=0.00000000000002

event=2265ae95b31918ea728015c8ffdcc39076c0928834a9e041927f09f7d78e6287
transaction=e9c42a971c1f562ccb156743245611ce5f837337f473452715f412422640063a
```

Byte audit in each fresh tree:

```text
tracked=5064
missing=0
changed=0
```

## Verdict

```text
B0.2-E CLOSED
B0.2 overall CLOSED
production acceptance NOT CLAIMED
next: BRIDGE-1
```
