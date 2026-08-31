# FABRIC-BAKE B0.2-C — Closure record

## Qualification

```text
FABRIC-BAKE B0.2-C
REFINEMENT GUARD FIELD

RESEARCH SLICE CLOSED
EXACT-HEAD DOUBLE PASS
B0.0/B0.1/B0.2-A/B REGRESSION PASS
EARLY REFINEMENT BEFORE CERTIFIED CAPACITY CROSSING
DETERMINISTIC FIELD IDENTITY
TRACKED TREE BYTE-CLEAN
WINDOWS PASS_BY_POLICY / NON-GATING

B0.2 OVERALL OPEN
PRODUCTION ACCEPTANCE NOT CLAIMED
```

## Exact executable subject

```text
branch:
research/fabric-bake0-2-refinement-guards-r1

implementation HEAD:
ffd53302d891b4d64b88589c434c56e76aef1eaa

TREE:
754bdd8a38246afe7bbd85eba74615ef7f0bb3e7

parent:
a1b8631a86b9bb896a6ca9a4871a5f0d2cee5b2a
```

The later docs-only closure commit is not the executable acceptance subject.

## Exact source evidence

```text
source-export run:
33357380503

artifact id:
9745553457

artifact name:
fabric-bake-b0-2-c-exact-source-ffd53302

artifact digest:
sha256:bba17f89324308083b3a2cdacfe29665709afdb9f849d77faa98bf6cbf8f32cc

tracked archive sha256:
f8d690545e49d22fa02daca2f5e86465aedcf2b2f40a351d4d0b221fb2a5a79f
```

## Engine identity

```text
Godot:
4.7.1.stable.double.custom_build.a13da4feb

binary sha256:
bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7
```

## Fresh exact-head evidence

Two separate fresh source extractions were imported and run independently.

Each run:

```text
B0.0 Acceptance       PASS (33 assertions)
B0.1 Acceptance       PASS (64 assertions)
B0.1 Playground       PASS
B0.2-A/B Acceptance   PASS (76 assertions)
B0.2-A/B Playground   PASS
B0.2-C Acceptance     PASS (118 assertions)
B0.2-C Playground     PASS
```

B0.2-C deterministic evidence:

```text
parts=500
bonds=499
regions=25
first_trigger=30
capacity_cross=40
peak_region=region/b0-2-012
guard_field=d3bbb115fb79d3159f1446eb2d589754c50b99892fd8b96c682de65e85d1243a
```

Post-run tracked-byte audit in both fresh trees:

```text
tracked_files=5043
missing=0
changed=0
```

## Scope decision

The R1 certified guard evaluator accepts connected rigid trees only. Cyclic/redundant structural graphs return `NO_SAFE_GUARD` rather than using an uncertified internal-load heuristic.

C emits a deterministic region refinement request. It does not execute unbake and does not emit the final executable structural `PhysicalBakeArtifact`.

## Next authorized research slice

```text
B0.2-D — BOUNDED LOCAL UNBAKE
```


## Independent Ubuntu verification R1

A separate Ubuntu verifier subsequently repeated the exact executable subject in two fresh detached worktrees with fresh imports.

```text
HEAD:
ffd53302d891b4d64b88589c434c56e76aef1eaa

TREE:
754bdd8a38246afe7bbd85eba74615ef7f0bb3e7

PASS #1:
B0.0 33/33
B0.1 64/64
B0.2-A/B 76/76
B0.2-C 118/118
runner exit 0

PASS #2:
same assertion counts and deterministic summary evidence
runner exit 0

first_trigger=30
capacity_cross=40
peak_region=region/b0-2-012
guard_field=d3bbb115fb79d3159f1446eb2d589754c50b99892fd8b96c682de65e85d1243a

tracked status:
CLEAN in both runs

runtime changes:
NONE
verification commits:
NONE
```

This independently confirms the existing `RESEARCH SLICE CLOSED / EXACT-HEAD DOUBLE PASS` qualification. It does not extend the scope or claim B0.2 overall closure.
