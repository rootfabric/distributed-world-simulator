# ECO.EVO7 PERF2.CONV R2 — PERF2.4 R5 Hot-Path Candidate

Дата: 2026-09-01

Статус:

~~~text
PERF2.CONV R1
PERF2.4 R2 PREREQUISITE PERFORMANCE RED
PRESERVED / NOT CLOSED

PERF2.CONV R2
PERF2.4 R5 HOT-PATH CANDIDATE INTEGRATED
EXACT WINDOWS ACCEPTANCE REQUIRED
~~~

## Previous exact RED boundary

The previous convergence subject remains preserved:

~~~text
HEAD:
d7d58d2459182e0854414c33d5b67038fe2f1ddf

TREE:
188eb46ef6613fd34c8ee7471c61df3058c74d3c
~~~

Its exact Windows run failed only on frozen PERF2.4 A/B performance thresholds:

~~~text
PERF1     PASS / 69
STREAM1   PASS / 195
PERF2.0   PASS / 62
PERF2.1   PASS / 861
PERF2.2   PASS / 170
PERF2.3   PASS / 1079

PERF2.4:
1255 PASS / 1261
6 threshold-derived failures

wall geomean:
0.996889 < 1.02

stream geomean:
0.999032 < 1.03

improved wall points:
5 / 9 < 6 / 9

nonregressed wall points:
7 / 9 < 9 / 9
~~~

Correctness remained GREEN:

~~~text
27 / 27 canonical A/B pairs
bounded working set preserved
deterministic operation reduction proven
JSON/hash round-trip PASS
tamper fails closed
~~~

Therefore the thresholds remain frozen and the old subject is not accepted.

## New PERF2.4 prerequisite

PERF2.CONV R2 adopts:

~~~text
PERF2.4 R5

HEAD:
e6550f1fe929a9767c34ff64378e9c64761ad925

TREE:
edfd2ffeb3848f9ba1cdb6b4948f2be101c06ffb
~~~

R5 descends from the repaired R2 compile subject and keeps the same frozen measurement contract:

~~~text
config/ecology/eco-evo7-perf2-measurement-contract.v1.json

blob:
b076784f6b4016a0191e937c4e6ada1fe90c783b
~~~

Frozen PERF2.4 thresholds remain unchanged:

~~~text
wall geomean legacy / optimized          >= 1.02
STREAM1 geomean legacy / optimized       >= 1.03
wall points improved                     >= 6 / 9
wall points non-regressed                = 9 / 9
minimum point ratio                      >= 0.97
exact A/B parity                         = 27 / 27
~~~

## R5 optimization target

R5 moves optimization into recruitment environment sampling.

The old optimized path repeatedly created and validated immutable EnvironmentSample
objects for destination cells.

R5 adds an optimized-only cache:

~~~text
environment cache identity =
revision
+ environment_seed
+ environment_field_hash
~~~

Properties:

~~~text
bounded by environment cell count
cleared when immutable environment identity changes
legacy A/B path remains uncached
cold path still uses EnvironmentSample.create + validate
recruitment formulas unchanged
recruitment event hashes unchanged
pool hashes unchanged
LS3.3 authority unchanged
~~~

The shared recruitment kernel accepts a prepared immutable sample only when supplied
explicitly by the optimized executor.

This is a runtime cache seam, not a biology/math change.

## Convergence ancestry

R5 was merged into a new convergence branch by a true Git merge:

~~~text
merge:
639e7d011d8e4ab5832d81f6efab20b54da7ec8b

parents:
d7d58d2459182e0854414c33d5b67038fe2f1ddf
e6550f1fe929a9767c34ff64378e9c64761ad925
~~~

The old convergence R1 RED subject remains independently addressable.

## Current convergence candidate

After updating exact prerequisite pins:

~~~text
branch:
feature/eco-evo7-perf2-conv-stream1-vis4-r2

HEAD:
0e05bc346eadc84ba4186f82051c29c6911dad79

TREE:
350f42b9461b14c2c968021ad33abfc8911d8205
~~~

PERF2.CONV now pins:

~~~text
PERF2.4:
e6550f1fe929a9767c34ff64378e9c64761ad925
edfd2ffeb3848f9ba1cdb6b4948f2be101c06ffb

VIS4.9:
ab44617d8961add81a6c9f245c99d0b68eaeab52
9d543a3db4f54a676e9f25152785c36a72c56a30
~~~

## Acceptance rule

No closure is authorized until one uninterrupted exact Windows or Ubuntu run produces:

~~~text
PERF2.4 R5 exact prerequisite PASS
VIS4.9 exact prerequisite PASS
PERF2.CONV integrated PASS
final candidate marker PRESENT
runner RC=0
HEAD unchanged
TREE unchanged
tracked tree CLEAN
~~~

PERF2.CONV budgets are unchanged:

~~~text
p50 combined / simulation <= 2.50x
p95 combined / simulation <= 4.00x
max combined generation   <= 5000 ms
PH5 caches                <= 5 x live records
foreground progress       >= 1 frame / generation
~~~

Until that evidence exists:

~~~text
PERF2.4 OPEN
PERF2.CONV OPEN
PLAY1 BLOCKED
~~~
