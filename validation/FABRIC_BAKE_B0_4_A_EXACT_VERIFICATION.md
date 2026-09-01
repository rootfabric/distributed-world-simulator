# FABRIC-BAKE B0.4-A — Exact Verification Evidence

```text
checkpoint:
B0.4-A DYNAMIC MODEL / PORT CONTRACT

branch:
research/fabric-bake0-4-dynamic-rom-r1

predecessor:
be419fb695221917df0f6026ed335e1355f72840
FABRIC.SYNC2 closure

exact executable HEAD:
1fbfffe30f5758a1bbb3c65db23edf06ecf3dae4

TREE:
79bedac6b6668ffcf29629238a5c055fb55d5f3c
```

## Exact source carrier

```text
workflow run:
33517363429
SUCCESS

artifact:
9804153300

bundle SHA-256:
eb5fef15df097f5b1d54510e31add7d7562866680ad65fecf7b0b29d6c42b3b4
```

## Godot

```text
4.7.1.stable.double.custom_build.a13da4feb

Linux binary SHA-256:
bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7
```

## Fresh exact pass #1

```text
fresh detached:
PASS

tracked clean before validation:
PASS

import:
PASS / exit 0

B0.4-A acceptance:
609/609 PASS

B0.4-A playground:
PASS

B0.4-A script/load fatal markers:
0
```

## Fresh exact pass #2

Second independent filesystem clone from the exact bundle:

```text
HEAD:
1fbfffe30f5758a1bbb3c65db23edf06ecf3dae4

TREE:
79bedac6b6668ffcf29629238a5c055fb55d5f3c

tracked:
clean

import:
PASS / exit 0

B0.4-A acceptance:
609/609 PASS

B0.4-A playground:
PASS

B0.4-A script/load fatal markers:
0
```

Deterministic identity:

```text
model hash:
5a75707e8d34bccd24c86ef325ccfb24ca53f5485889cc47fa32dd209490c46f
```

## Predecessor regression on exact subject

```text
B0.0       33/33 PASS
B0.1       64/64 PASS
B0.2-A/B   76/76 PASS
B0.2-C    118/118 PASS
B0.2-D    609/609 PASS
B0.2-E   2580/2580 PASS
BRIDGE-1  146/146 PASS
B0.3      319/319 PASS
B0.4-A    609/609 PASS

TOTAL:
4554/4554 PASS
```

## Project Control

```text
run:
33517363373

conclusion:
SUCCESS
```

## Verdict

```text
B0.4-A
DYNAMIC MODEL / PORT CONTRACT
VERIFIED

RESEARCH CHECKPOINT CLOSED
EXACT-HEAD DOUBLE-GODOT PASS
PROJECT CONTROL PASS
NOT PRODUCTION ACCEPTED

B0.4 parent:
IN PROGRESS

next:
B0.4-B CERTIFIED REDUCTION
```
