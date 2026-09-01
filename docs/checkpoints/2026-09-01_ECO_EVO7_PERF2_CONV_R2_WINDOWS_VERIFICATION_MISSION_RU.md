# ECO.EVO7 PERF2.CONV R2 — Windows Exact Verification Mission

Дата: 2026-09-01

## Subject

~~~text
branch:
feature/eco-evo7-perf2-conv-stream1-vis4-r2

HEAD:
0e05bc346eadc84ba4186f82051c29c6911dad79

TREE:
350f42b9461b14c2c968021ad33abfc8911d8205
~~~

## Exact prerequisites

~~~text
PERF2.4 R5
HEAD e6550f1fe929a9767c34ff64378e9c64761ad925
TREE edfd2ffeb3848f9ba1cdb6b4948f2be101c06ffb

VIS4.9
HEAD ab44617d8961add81a6c9f245c99d0b68eaeab52
TREE 9d543a3db4f54a676e9f25152785c36a72c56a30
~~~

Do not use the old PERF2.4 R2 subject 8c022eae as the convergence prerequisite.

## Canonical Windows Godot

Use the already verified Windows double console binary:

~~~text
version:
4.7.1.stable.double.custom_build.a13da4feb

SHA-256:
3633c3e609c8ce2f9bae334a9c7e75c7f974de3af0415ab4a8050a625a15a7a5
~~~

The same honest host shims used by the previous verifier are allowed:

~~~text
lscpu -> real host CPU identity
python3 -> real CPython for JSON validation
~~~

They must not alter test outcomes.

## Required execution

Create a fresh detached worktree at the exact convergence HEAD and verify exact TREE.

Then execute:

~~~text
RUN_ECO_EVO7_PERF2_CONV_TESTS.sh
~~~

without interruption.

The runner must execute the exact R5 PERF2.4 prerequisite in its own detached worktree,
then exact VIS4.9, then the integrated PERF2.CONV campaign.

## Frozen thresholds

Do not modify:

~~~text
PERF2.4:
wall geomean >= 1.02
stream geomean >= 1.03
improved points >= 6 / 9
nonregressed points = 9 / 9
minimum point ratio >= 0.97

PERF2.CONV:
p50 combined/simulation <= 2.50x
p95 combined/simulation <= 4.00x
max combined generation <= 5000 ms
cache entries <= 5 x live records
foreground progress >= 1 frame/generation
~~~

## Required final report

Return:

~~~text
ECO.EVO7 PERF2.CONV R2 — FINAL ACCEPTANCE

SUBJECT
HEAD
TREE
Godot version
Godot SHA-256

PERF2.4 R5 EXACT
PERF1
STREAM1
PERF2.0
PERF2.1
PERF2.2
PERF2.3
PERF2.4

wall geomean
stream geomean
improved points
nonregressed points
27/27 parity status
optimization_claim

VIS4.9 EXACT
PASS / FAIL

PERF2.CONV
assertions
p50 combined/simulation
p95 combined/simulation
max combined generation
PH5 cache bounded
STREAM1 optimized contract
source seals
single-flight
foreground progress
PERF2.5
PERF2.6
PERF2.7
PERF2.8

FINAL
runner RC
final marker
HEAD unchanged
TREE unchanged
tracked status
log SHA-256

VERDICT
WORK FINISHED
NEXT
~~~

If any frozen threshold fails:

~~~text
PERF2.CONV NOT VERIFIED
do not retry selectively
do not weaken budgets
preserve the exact RED evidence
~~~
