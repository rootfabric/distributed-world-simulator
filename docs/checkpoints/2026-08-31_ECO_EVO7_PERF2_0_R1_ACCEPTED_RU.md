# ECO.EVO7 PERF2.0 R1 — Exact Windows Acceptance

Статус: **ACCEPTED**.

## Accepted frozen subject

```text
branch:
feature/eco-evo7-perf2-0-measurement-contract-r1

HEAD:
5994598d317a55ddae2954f943021878a279afc9

TREE:
a0241f89b6fd7546a27e4388992ffe371b4c5de6

immediate parent:
080698aa96fec6a5f8bc7ae9d479daf966da54eb

Godot:
4.7.1.stable.double.custom_build.a13da4feb
```

Accepted predecessor:

```text
STREAM1 verified subject:
4d0d95a2f0cf8aeb9642765c17a071f039e0f1c4

STREAM1 tree:
68389ef9a491fc2f1e13efb92058029c9536f870
```

## Final fresh detached Windows evidence

Canonical repository-local entrypoint:

```powershell
.\RUN_ECO_TEST_WORKFLOW.ps1 -Suite perf2.0 -GodotPath <exact-double-Godot>
```

Final run environment:

```text
fresh worktree:
C:\distributed-world-simulator\eco-perf2-0-runtime-test

branch:
<detached-head>

PowerShell:
Windows PowerShell 5.1

import:
PASS / exit 0

HEAD before:
5994598d317a55ddae2954f943021878a279afc9

TREE before:
a0241f89b6fd7546a27e4388992ffe371b4c5de6
```

Final gate:

```text
PERF1:
PASS (69 assertions)

STREAM1:
PASS (195 assertions)
108 exact generation comparisons

PERF2.0:
PASS (62/62 assertions)

transitive marker:
ECO.EVO7 PERF2.0 transitive measurement-contract acceptance: PASS

canonical workflow marker:
ECO WORKFLOW STAGE perf2.0: PASS
ECO repository-local test workflow: PASS

workflow exit:
0

HEAD after:
5994598d317a55ddae2954f943021878a279afc9

TREE after:
a0241f89b6fd7546a27e4388992ffe371b4c5de6

tracked worktree:
CLEAN
```

## Repair evidence chain

PERF2.0 acceptance intentionally preserves the complete RED→repair→GREEN
history.

### R1 RED

```text
HEAD:
85c9f7f8d4714eee01d22448ea17db2370c8f988

PERF1:
PASS

STREAM1:
PASS

PERF2.0:
FAIL 61/62
```

The fail-closed source guard correctly rejected a probe source comment that
contained the literal `workbench`.

No transitive PASS marker was emitted.

### Repair 1

```text
1cef3e380f214fc5e0044684b4f527105ec5c1be
fix(eco): remove PERF2 probe authority guard false positive
```

This changed only the misleading comment wording; probe runtime semantics were
unchanged.

### Intermediate exact-content GREEN

```text
HEAD:
382b672220224fc58034df17982547687a3ad7cc

PERF1:
PASS (69)

STREAM1:
PASS (195 / 108 exact)

PERF2.0:
PASS (62/62)

transitive marker:
PASS
```

This run proved the measurement-contract/test content green, but exposed a
separate local workflow defect under detached HEAD on Windows PowerShell 5.1.

### Detached-HEAD repair

The first attempted repair used:

```powershell
[string](& git branch --show-current)
```

This was insufficient on Windows PowerShell 5.1 because empty native stdout may
be represented as AutomationNull and still reach `.Trim()` as null.

The definitive repair is:

```text
080698aa96fec6a5f8bc7ae9d479daf966da54eb
fix(eco): handle empty detached HEAD branch output safely
```

The implementation materializes native stdout into an array and guards access
before `.Trim()`.

### Canonical closure entrypoint

```text
5994598d317a55ddae2954f943021878a279afc9
ci(eco): exercise canonical PERF2.0 workflow in closure
```

The PERF2.0 closure workflow now calls the canonical repository-local
entrypoint rather than bypassing it through the direct stage runner.

The final fresh detached Windows run on this exact HEAD printed:

```text
branch=<detached-head>
```

and completed successfully.

## What is accepted

PERF2.0 R1 freezes the measurement contract for simulation-side PERF2 work:

- exact controlled workload identity;
- `workload_hash`;
- `simulation_workload_hash`;
- same-mode comparison key;
- cross-mode execution comparison key;
- exact canonical-result parity fence;
- warmup / measured-generation / repetition minimums;
- p50 / p95 / mean / min / max statistics;
- engine static-memory vs optional process RSS semantics;
- failed-run exclusion;
- no best-of-N primary reporting;
- no measurement authority in ecology truth;
- reuse of PERF1/STREAM1 timings and telemetry.

The accepted contract makes **no speedup claim**.

## Authority boundary

PERF2.0 remains:

```text
NONCANONICAL
SIDE-CHANNEL ONLY
MEASUREMENT ONLY
```

It does not own:

- ecology generation publication;
- candidate / dispersal / recruitment identity;
- biology;
- persistence;
- network replication;
- world state;
- production authority.

## Acceptance conclusion

```text
fresh detached exact-Windows
+
exact Godot double build
+
PERF1 PASS
+
STREAM1 PASS / 108 exact
+
PERF2.0 62/62
+
transitive PASS
+
canonical workflow PASS
+
immutable HEAD/TREE
+
clean tracked worktree
=
ECO.EVO7 / PERF2.0 R1 ACCEPTED
```

PERF2.1 — STREAM1 Generation Profiling — is now unblocked.

PERF2.1 must consume this accepted measurement contract unchanged. Any future
change to the PERF2.0 protocol requires an explicit new measurement-contract
revision rather than silent drift.
