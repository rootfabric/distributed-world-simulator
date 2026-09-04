# ECO.EVO7 PERF2.4 R12 — ACCEPTED

Дата: 2026-09-04

Статус:

```text
PERF2.4 R12
ACCEPTED
EXACT LOCAL WINDOWS PASS
ECO-RUNTIME-VERIFY-2026-08-31-R1 SATISFIED
PERF2.SIM CLOSURE AUTHORIZED
```

## Exact tested runtime subject

```text
branch
feature/eco-evo7-perf2-4-runtime-optimization-r12

HEAD
840cfcea62ef7192b510235f915b849829654c6c

TREE
967d674c0ba2349db949193969f16f91553761ea
```

The tested executable identity is the HEAD/TREE above. Acceptance metadata commits are not substituted for the tested runtime identity.

Accepted predecessor:

```text
PERF2.3 control tip
4997f7116d0e4ac40ed88fe8a41a7b5029621d71
```

Frozen PERF2.0 contract blob:

```text
b076784f6b4016a0191e937c4e6ada1fe90c783b
```

## Runtime-verification policy and platform disclosure

The active policy is:

```text
config/ecology/eco-runtime-verification-policy.v1.json
revision: ECO-RUNTIME-VERIFY-2026-08-31-R1
```

For OS-neutral ECO runtime it requires one exact local PASS on either Ubuntu or Windows; dual-OS evidence is optional/non-blocking.

The R12 dispatch was initially prepared for Ubuntu. The canonical Ubuntu host was reachable but SSH access for the available verifier credential was unavailable, and no Linux self-hosted runner was registered. The accepted campaign therefore used the canonical Windows double-Godot. This is policy-compliant, not a threshold or contract exception.

Accepted platform:

```text
OS
Windows 10 Pro 19045

CPU
Intel Core i9-13900H, 14C/20T

Godot
4.7.1.stable.double.custom_build.a13da4feb

Godot SHA-256
3633c3e609c8ce2f9bae334a9c7e75c7f974de3af0415ab4a8050a625a15a7a5

host fingerprint
matches the established R3 Windows verifier record; full fingerprint is bound inside the accepted report artifact
```

Fresh detached worktree:

```text
C:\dws-perf2-4-r12-win-20260904-002326
```

Two earlier attempts were infrastructure aborts before a completed measurement campaign: one console-spawn rc=127 before test output/report creation and one machine-sleep interruption before measurement gates. Neither produced a performance verdict. The accepted evidence below comes from one completed campaign with no timing reroll.

## Transitive acceptance

```text
PERF1
PASS — 69 assertions

STREAM1
PASS — 195 assertions

PERF2.0
PASS — 62 assertions

PERF2.1
PASS — 861 assertions

PERF2.2
PASS — 170 assertions

PERF2.3
PASS — 1079 assertions

PERF2.4
PASS — 1304 assertions
```

Canonical A/B parity:

```text
samples                 54 / 54
comparison points         9 / 9
exact legacy↔optimized   27 / 27
working set              PRESERVED
operation reduction      PROVEN
```

## Frozen acceptance thresholds

No PERF2.0/PERF2.4 threshold was changed, rounded, weakened or retried.

| Gate | Frozen requirement | Accepted R12 |
| --- | ---: | ---: |
| wall geomean | >= 1.02 | 1.027677 PASS |
| STREAM1 geomean | >= 1.03 | 1.045910 PASS |
| improved wall points | >= 6/9 | 9/9 PASS |
| non-regressed wall points | 9/9 | 9/9 PASS |
| minimum point wall ratio | >= 0.97 | 1.009786 PASS |
| bounded working set | PRESERVED | PRESERVED |
| operation reduction | PROVEN | PROVEN |
| optimization_claim | TRUE | TRUE |
| serial_crossover_claim | FALSE | FALSE |

## Accepted nine-point result

Wall ratio is `legacy / optimized`; greater than 1 means optimized is faster.

| scale | chunk | wall ratio | STREAM1 ratio | context builds legacy→optimized | chunk-local sorts legacy→optimized |
| --- | ---: | ---: | ---: | ---: | ---: |
| AGE_2 | 1 | 1.009786 | 1.014577 | 858→12 | 3432→0 |
| AGE_2 | 7 | 1.010540 | 1.043395 | 127→12 | 508→0 |
| AGE_2 | 64 | 1.031803 | 1.062807 | 19→12 | 76→0 |
| AGE_12 | 1 | 1.022470 | 1.030089 | 2378→12 | 9512→0 |
| AGE_12 | 7 | 1.034767 | 1.057628 | 345→12 | 1380→0 |
| AGE_12 | 64 | 1.038169 | 1.060721 | 42→12 | 168→0 |
| AGE_22 | 1 | 1.026855 | 1.031626 | 7027→12 | 28108→0 |
| AGE_22 | 7 | 1.035996 | 1.054525 | 1009→12 | 4036→0 |
| AGE_22 | 64 | 1.039208 | 1.058946 | 115→12 | 460→0 |

All nine wall points improved. No point consumed the 3% regression budget.

## Accepted optimization composition

The accepted R12 result preserves the useful earlier repairs while rejecting unsuccessful experiments:

```text
R5   bounded immutable EnvironmentSample cache                    RETAINED
R9   prepared mutation-context certification per chunk            RETAINED
R10  direct adoption of already-fresh competition survivors       RETAINED
R11  competition-field ownership adoption                         REJECTED / NOT CARRIED
R12  redundant post-competition snapshot/records-copy elision     ACCEPTED
```

R12 optimized LS3.4 uses the already-refreshed `core.population_hash` and `core.records.size()` instead of an intermediate full `core.get_snapshot()`, keeps the one snapshot required by the public LS3.4 snapshot, and adopts its already-fresh records array. Legacy keeps the historical snapshot/copy layers for same-HEAD A/B evidence.

Competition formulas, survival decisions, field hashes, mutation formulas, canonical parity and bounded working-set semantics remain unchanged.

## Artifact integrity

```text
report
artifacts/perf2/perf2-4-runtime-optimization-r1.json

report hash
16d3407abef3d3ff30cbe4293cb1278e1b18845b0b5332589587d543b134853b

final HEAD unchanged
PASS

final TREE unchanged
PASS

tracked worktree clean
YES
```

## Project Control classification

R12 Project Control run:

```text
33762025862
```

Subject-local preflight passed:

```text
exact checkout                         PASS
control candidate syntax/generation    PASS
checkpoint-session regression          PASS
```

Global architecture/ownership compatibility remains RED because of concurrent project-wide Matter/project-program-registry passport/dependency drift outside the PERF2.4 delta.

This acceptance does not relabel that unrelated global RED as green and does not repair unrelated ownership drift.

## Acceptance decision

```text
PERF2.4 R12                    ACCEPTED
runtime acceptance             SATISFIED
optimization claim             TRUE
canonical A/B parity           27/27
bounded working set            PRESERVED
second OS verification         OPTIONAL / NOT REQUIRED
PERF2.SIM                      READY TO CLOSE
PERF2.CONV                     AUTHORIZED AS NEXT INTEGRATION FRONTIER
```

Next checkpoint:

```text
ECO.EVO7/PERF2.CONV
Integrated Simulation + Morphology Performance Convergence
```
