# FABRIC-BAKE B0.2-D — Closure record

## Qualification

```text
FABRIC-BAKE B0.2-D
BOUNDED LOCAL UNBAKE

RESEARCH SLICE CLOSED
EXACT-HEAD DOUBLE PASS
B0.0/B0.1/B0.2-A/B/B0.2-C REGRESSION PASS
BOUNDED REGIONAL FULL EXPANSION
RESIDUAL BAKED COMPONENTS RETAINED
CUT-INTERFACE CONTINUITY PASS
MASS / LINEAR / ANGULAR MOMENTUM RECONCILIATION PASS
DETERMINISTIC PLAN IDENTITY
TRACKED TREE BYTE-CLEAN
WINDOWS PASS_BY_POLICY / NON-GATING

B0.2 OVERALL OPEN
PRODUCTION ACCEPTANCE NOT CLAIMED
```

## Exact executable subject

```text
branch:
research/fabric-bake0-2-d-bounded-local-unbake-r1

implementation HEAD:
8da6ec6b7c2983b127f4c0607edeb9be900825c3

TREE:
285240dcc8a08a3a676897792659dfcad43bf410

parent:
da90331f83e94ca71d8979304c084b072a082634
```

The closure/evidence commit after this point is docs-only and is not the executable acceptance subject.

## Exact source evidence

```text
source-export run:
33365726226

artifact id:
9748204242

artifact:
fabric-bake-b0-2-d-exact-source-8da6ec6b

artifact digest:
sha256:9f5dd67be50d79d7bcad6665781b5074117894da75f61a7c126b57e7ff1f660d

tracked archive SHA-256:
a15594210e395082b2186cb630e425535184f539115e470052cbc6914648f24d

tracked files:
5054
```

## Exact-head double pass

Both independent fresh filesystem extractions used a fresh import and the pinned Godot double build.

```text
Godot:
4.7.1.stable.double.custom_build.a13da4feb

SHA-256:
bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7
```

Each pass:

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
```

Deterministic D evidence:

```text
target_region=region/b0-2-012
full=20
retained=480
components=2
interfaces=2
dof=6500->286
ratio=22.727273
mass_err=0.0
linear_err=0.00000000000023
angular_err=0.00000000000539
interface_pos=0.00000000000001
interface_vel=0.0
plan=733cbe36eb3f98c72f893d83793ec6fe444899a32d7b7dc28d8cc991ac01ba8f
```

Tracked-byte audit in both runs:

```text
checked=5054
missing=0
changed=0
```

## Scope decision

D performs a derived mixed representation transition for exactly one bounded C-requested canonical region. It never expands the requested region implicitly. Unsafe residual size, invalid ownership partition, stale bindings, or unsupported transition shape fail closed.

Canonical Construction/Matter topology remains unchanged.

## Next authorized slice

```text
B0.2-E — TOPOLOGY SPLIT / RE-BAKE
```
