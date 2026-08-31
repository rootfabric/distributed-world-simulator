# V0 P7.3 — MatterMaterialBatch → canonical Item Graph — COMPLETE_MERGED

## Exact runtime subject

```text
branch: feature/v0-p7-bounded-terrain-mutation
HEAD:   b4b11a69ef921c59b28208685cf26509c3b81907
TREE:   99dea175fda7bacce936b15d30d9e25fa9e4af00
```

## Policy

```text
policy_id: p7/matter-material-delivery/r1
output: item/ore
1 canonical item quantity = 1.0 kg represented supported lunar geological Matter
quantization: FLOOR_WITH_EXPLICIT_RESIDUAL
exactly-once owner: CANONICAL_ITEM_GRAPH_REPLAY_LEDGER
```

No P7-private inventory, receipt ledger, replay ledger or persistence owner was added.

## Independent review

```text
review commit:
b9c638b1721edfe24537e264bd562e96ca224116

verdict:
PASS

Project Control:
33365405527 = SUCCESS
```

## Fresh independent verification

```text
verification commit:
2fadad48635c04e21b4de8acff4a13c8c5e27b88

verdict:
VERIFIED

Godot:
4.7.1.stable.double.custom_build.a13da4feb

P7.3              116/116
P7.2 bubble        53/53
P7.2 seam          50/50
P7.1 authority     83/83
P7.1 Tool→MW4      30/30
P5                  36/36
P3                  79/79
MW4                187
MW5                142
MW6                130

canonical runner:
EXIT 0

fatal logs:
11/11 clean

Project Control:
33366918481 = SUCCESS
```

## Human gate

```text
RUNTIME_FEATURE_MERGE APPROVED
```

Human approval was durably recorded in main before runtime integration.

## Runtime merge

PR #373 remained draft, so a non-draft exact-subject carrier PR #387 was used without rebasing or changing the reviewed/verified runtime subject.

```text
runtime carrier PR:
#387

canonical merge:
502d05fe24256fecd52f3092b8e056e74a8b4450

parents:
5d641e3195e1a43f1ec01c56977b62b4286ea7d7
b4b11a69ef921c59b28208685cf26509c3b81907

merge TREE:
012eccfcf196f4d8d6ca49696b9b39504c4e3763
```

GitHub recognizes original PR #373 as merged/closed because its exact verified HEAD is now an ancestor of main.

## Closure

```text
P7.3  COMPLETE_MERGED
P7    IN_PROGRESS
P7.4  NEXT
```

P7.4:

```text
PERSISTENCE_RESTART_COMPOSITION
```

Required direction:

```text
committed but undelivered MatterMaterialBatch
        ↓ restart
existing MW5 persistence/recovery
        ↓
same immutable batch still available
        ↓
canonical Item Graph delivery exactly once
```

Hard rules:
- no P7-private persistence owner;
- no delivery receipt store;
- no second Item Graph;
- no hidden Matter balance;
- restart must not duplicate extracted material.

Whole P7 is not accepted. P7.5-P7.7, whole-world/core regression and final checkpoint acceptance remain open.
