# FABRIC-BAKE B0.2-C — Independent Ubuntu Verification R1

## Subject

```text
branch lineage:
research/fabric-bake0-2-refinement-guards-r1

executable HEAD:
ffd53302d891b4d64b88589c434c56e76aef1eaa

TREE:
754bdd8a38246afe7bbd85eba74615ef7f0bb3e7
```

This verification was performed independently on Ubuntu/Linux using two separate fresh detached worktrees. Runtime code was not changed and no verification commit was produced.

## Engine identity

```text
Godot:
4.7.1.stable.double.custom_build.a13da4feb

SHA-256:
bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7
```

## PASS #1

Fresh detached worktree, fresh import exit 0.

```text
B0.0:      33/33 PASS
B0.1:      64/64 PASS
B0.1 PG:   PASS
B0.2-A/B:  76/76 PASS
A/B PG:    PASS
B0.2-C:    118/118 PASS
C PG:      PASS

runner exit: 0

first_trigger:   30
capacity_cross:  40
peak_region:     region/b0-2-012
guard_field:     d3bbb115fb79d3159f1446eb2d589754c50b99892fd8b96c682de65e85d1243a

safety invariant:
30 < 40  HOLDS

tracked status:
CLEAN
```

Playground sequence:

```text
load=20  STRUCTURAL_GUARD_SAFE           utilization=0.500000  requests=0
load=30  STRUCTURAL_REFINEMENT_REQUIRED  utilization=0.750000  requests=1
load=41  STRUCTURAL_REFINEMENT_REQUIRED  utilization=1.025000  requests=1
```

## PASS #2

A second fresh detached worktree and fresh import produced byte-identical summary evidence:

```text
B0.0:      33/33 PASS
B0.1:      64/64 PASS
B0.1 PG:   PASS
B0.2-A/B:  76/76 PASS
A/B PG:    PASS
B0.2-C:    118/118 PASS
C PG:      PASS

runner exit: 0

first_trigger:   30
capacity_cross:  40
peak_region:     region/b0-2-012
guard_field:     d3bbb115fb79d3159f1446eb2d589754c50b99892fd8b96c682de65e85d1243a

tracked status:
CLEAN
```

## Fail-closed contract confirmed

The exact B0.2-C acceptance suite confirmed the expected fail-closed behavior:

```text
cyclic/redundant graph
  -> NO_SAFE_GUARD_CYCLIC_OR_REDUNDANT_STRUCTURAL_GRAPH

incomplete external wrench inventory
  -> rejected

foreign descriptor binding
  -> STRUCTURAL_GUARD_DESCRIPTOR_BINDING_MISMATCH

missing capacity certificate coverage
  -> NO_SAFE_GUARD_CAPACITY_COVERAGE_MISMATCH

inconsistent capacity certificate
  -> NO_SAFE_GUARD_CAPACITY_CERTIFICATE_MISMATCH

invalid safety margin / uncertainty
  -> NO_SAFE_GUARD_UNCERTIFIED_MARGIN

non-rigid structural bond
  -> rejected
```

## Platform result

```text
Ubuntu/Linux exact-double:
PASS

Windows:
PASS_BY_POLICY
NON-GATING
NO EXECUTION EVIDENCE REQUIRED
```

## Independent verdict

```text
B0.2-C:
VERIFIED

qualification:
RESEARCH SLICE CLOSED
EXACT-HEAD DOUBLE PASS CONFIRMED
INDEPENDENT UBUNTU DOUBLE PASS CONFIRMED

B0.2 overall:
OPEN

next:
B0.2-D BOUNDED LOCAL UNBAKE

production acceptance:
NOT CLAIMED
```

Temporary verification worktrees were removed after the run. The external run produced no code changes and no runtime commits.
