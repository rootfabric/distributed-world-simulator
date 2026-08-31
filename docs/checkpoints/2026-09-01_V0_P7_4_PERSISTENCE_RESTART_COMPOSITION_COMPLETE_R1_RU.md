# V0 P7.4 — Persistence Restart Composition — COMPLETE_MERGED

## Exact runtime subject

```text
branch: feature/v0-p7-bounded-terrain-mutation
HEAD:   9deb31b85a5f46ae30b5eeaa6e2e3a1f6a37f292
TREE:   1efad34a075af63169c48dd5055c2537c8d7e6ef
```

P7.4 composes existing owners only:

```text
MW5 Matter persistence/recovery
        ↓
MW4 committed replay / receiver / journal
        ↓
accepted P7.3 MaterialBatch → canonical Item Graph
        ↓
canonical Item Graph replay ledger
        ↓
existing M6/V0 gameplay recovery
        ↓
NetworkedGameplayService aggregate revision owner
```

No P7-private persistence owner, replay ledger, delivery receipt, second Item Graph or hidden Matter balance was introduced.

## Independent review

```text
review commit:
abd753941f2bc4f9ff771e8501f261505b61c7de

verdict:
PASS

Project Control:
33388053145 = SUCCESS
```

Reviewer explicitly accepted the restart seed boundary and found no blocking ownership defect.

## Verifier platform amendment

R1 and R2 verifier rounds ended correctly as:

```text
NOT_VERIFIED / INSUFFICIENT_ENVIRONMENT
execution_performed=false
```

They contribute zero runtime execution evidence.

A formal Human-directed amendment authorized the existing canonical Windows x86_64 exact-double path in addition to Ubuntu:

```text
amendment commit:
b31d657c9f6987167da233e1d6f212884a095a88

Windows runner:
RUN_V0_P7_4_PERSISTENCE_RESTART_GATE.ps1

Godot console:
C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe

Godot version:
4.7.1.stable.double.custom_build.a13da4feb

Godot SHA-256:
3633c3e609c8ce2f9bae334a9c7e75c7f974de3af0415ab4a8050a625a15a7a5
```

Runtime source, gate contents and acceptance invariants were unchanged.

## Fresh independent Verifier R3

```text
verification commit:
8b106a6057672de7972c0e779efeb4ccb9abb186

verdict:
VERIFIED

dispatch Project Control:
33431640700 = SUCCESS

result Project Control:
33432608471 = SUCCESS
```

Fresh exact Windows campaign:

```text
16 / 16 stages PASS
1384 assertions
0 failures

17 / 17 logs
fatal-pattern matches: 0

fresh import: PASS
tracked clean before: PASS
tracked clean after: PASS
external timeout: none
execution evidence inherited from R1/R2/Implementer/Reviewer: none
```

Important delegated regressions were freshly closed:

```text
P7.2 bubble          53 / 0
M6 recovery process 128 / 0
MW4                 187 / 0
MW5                 142 / 0
MW6                 130 / 0
```

The final gate ended:

```text
V0-P7.4 PERSISTENCE RESTART COMPOSITION GATE GREEN
EXACT_HEAD=9deb31b85a5f46ae30b5eeaa6e2e3a1f6a37f292
GODOT=4.7.1.stable.double.custom_build.a13da4feb
```

Verifier transparently recorded non-fatal Godot exit-time leak notices from runner stderr. They were not present in the 17 campaign logs, matched none of the five fatal patterns, and all in-stage leak checks passed.

## Human gate

Human operator delegated the exact P7.4 Human RUNTIME_FEATURE_MERGE decision to the control session. After independent re-check of the R3 chain:

```text
RUNTIME_FEATURE_MERGE APPROVED
```

## Runtime merge

Original PR #396 remained Draft. The connector's Ready-for-review mutation failed internally, so an exact non-draft carrier PR #425 was created at the identical verified HEAD.

The carrier compare was exactly:

```text
7 commits
6 files
+1030 / -0
```

with no runtime byte beyond the reviewed/verified subject.

```text
carrier PR:
#425

carrier Project Control:
33442744229 = SUCCESS

canonical merge:
bfd2d8efec6f499311dea81d9b602f30b3ac6a73

parents:
0ad8c41f04b1d115da7de4a24a1c0390761c3ae1
9deb31b85a5f46ae30b5eeaa6e2e3a1f6a37f292

merge TREE:
1efad34a075af63169c48dd5055c2537c8d7e6ef
```

The merge TREE is exactly the independently verified runtime TREE.

GitHub recognizes original PR #396 as merged/closed with the same canonical merge commit.

## Closure

```text
P7.4  COMPLETE_MERGED
P7    IN_PROGRESS
P7.5  NEXT
```

P7.5:

```text
TWO_CLIENT_CONVERGENCE
```

Required direction:

```text
accepted P7.4 restart/replay semantics
        ↓
existing MW6 replication + MW7 interest
        ↓
canonical Item Graph / Matter state
        ↓
two independent clients
        ↓
same authoritative state / same material accounting
```

Hard rules for P7.5:
- reuse the P7.4 NetworkedGameplayService aggregate revision seam;
- no second aggregate revision path;
- keep exactly-once recognition in the canonical Item Graph replay ledger;
- no P7-private delivery receipt/replay record;
- preserve existing MW6/MW7 and RL2/RL3 ownership;
- no network foundation change unless explicitly escalated.

## Separate Harness control debt

The epoch `E2026-08-30-V0-P7-R1` is missing `transition-table.v1.json`.

Observed effect:

```text
-Drive / -Close => exit 3
```

This predates P7.4 R3, has no proven runtime-correctness impact, and does not invalidate P7.4 review/verification/merge evidence.

It should be repaired before relying on automated `-Drive/-Close` for P7.5.

Whole P7 is not accepted. P7.5-P7.7, whole-world/core regression and final checkpoint acceptance remain open.
