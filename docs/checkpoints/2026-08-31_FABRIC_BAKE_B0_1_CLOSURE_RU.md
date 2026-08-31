# FABRIC-BAKE B0.1 — Closure Record

**Date:** 2026-08-31  
**Qualification:** RESEARCH CHECKPOINT CLOSED / EXACT-HEAD DOUBLE PASS  
**Production acceptance:** NOT CLAIMED

## Exact executable subject

```text
branch:
research/fabric-bake0-1-exact-boundary-reduction-r1

HEAD:
e854185f501cfc2658d5d1c5430be4eed3b070ee

TREE:
0114ed1973e7bcd1d6225381d07f1ad1ade6b9a0

parent / B0.0 closure:
d389b8ed72ffbed8949279b42089da3687125a90
```

The implementation commit is the only commit ahead of the B0.0 closure at the
executable boundary.

## Exact source materialization

GitHub-hosted run:

```text
33348975423 = SUCCESS
```

It checked out the exact executable HEAD in detached state and asserted:

```text
HEAD = e854185f501cfc2658d5d1c5430be4eed3b070ee
TREE = 0114ed1973e7bcd1d6225381d07f1ad1ade6b9a0
```

The resulting exact tracked archive:

```text
SHA-256:
548d832c6d042227c3b0df85b991519e1ae2702a7ef71770bdaa6f226ba3c0d1
```

## Verification engine

```text
Godot:
4.7.1.stable.double.custom_build.a13da4feb

Linux executable SHA-256:
bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7
```

## Exact-head pass 1

Fresh extraction of the exact Git archive, fresh project import, then:

```text
./RUN_FABRIC_BAKE_B0_1_TESTS.sh
```

Result:

```text
B0.0 Acceptance: PASS (33 assertions)

B0.1 Acceptance: PASS (64 assertions)
full=132
reduced=4
internal_rank=128
reduced_rank=3
work_ratio=1089.0
max_flow_error=0.00000000000009
max_power_error=0.00000000000142

B0.1 Playground: PASS
```

Derived identities:

```text
descriptor:
92c62af79e1c75889c846084711c6752e92489db1d1aa27a5f13aa832bbc00f6

artifact:
a04a380833bf0f62ae0fc8f33da2cbc66d7520dd78fea193b34d9f21f6cd0300
```

## Exact-head pass 2

A second independent filesystem directory was created from the same immutable archive.
Before import it had no `.godot` state. Fresh import returned exit code 0, followed by
the same canonical runner.

Result:

```text
B0.0 Acceptance: PASS (33 assertions)
B0.1 Acceptance: PASS (64 assertions)
B0.1 Playground: PASS

descriptor:
92c62af79e1c75889c846084711c6752e92489db1d1aa27a5f13aa832bbc00f6

artifact:
a04a380833bf0f62ae0fc8f33da2cbc66d7520dd78fea193b34d9f21f6cd0300
```

Known unrelated ECO scene parse errors appeared during full-project import, as on prior
fresh worktrees; import still completed successfully and they do not participate in the
B0.0/B0.1 execution chain.

## Post-run byte audit

The second verifier tree was compared against a third pristine extraction of the same
exact archive:

```text
tracked_files_checked = 5025
missing = 0
changed = 0
```

Thus import and both B0.0/B0.1 tests did not rewrite tracked source bytes.

## Project Control

GitHub-hosted run:

```text
33349147651 = SUCCESS
```

The run explicitly asserted the same executable HEAD/TREE and B0.0 ancestry before
running both standard and directional control auditors.

The current whole-project control summary was YELLOW because of unrelated active
frontiers. This closure only records that the exact B0.1 subject did not introduce a
control-command failure; it does not declare the entire project GREEN.


## Platform verification policy

For FABRIC-BAKE, Ubuntu/Linux exact-double verification is the required and sufficient
platform gate for research checkpoint closure.

```text
Ubuntu/Linux exact-double = REQUIRED / AUTHORITATIVE
Windows                   = PASS_BY_POLICY / NON-GATING
Windows execution evidence = NOT REQUIRED
```

The former queued Windows run `33348754783` is obsolete as closure evidence and is not
part of the B0.1 chain. Its queue/offline state has no status effect.

`PASS_BY_POLICY` records the accepted compatibility policy; it is not a claim that the
specific Windows workflow actually executed.

## What was proven

```text
132-equation well-posed passive linear subsystem
→ exact deterministic Schur elimination
→ 4-equation acausal boundary relation

FULL boundary flow ≈ BAKED boundary flow
FULL boundary power ≈ BAKED boundary power

singular internal block
→ RANK_DEFICIENCY / NO_SAFE_BAKE

unsafe passive/reciprocal candidate
→ UNSAFE_ELIMINATION / NO_SAFE_BAKE

foreign reduction descriptor
→ execution forbidden

canonical source mutation
→ B0.0 invalidation
→ old artifact non-executable
→ deterministic rebuild
```

## Non-claims

B0.1 does not prove:

- generic sparse elimination;
- pseudo-inverse/nullspace reduction;
- rank-revealing QR;
- generalized Schur or DAE condensation;
- nonlinear/dynamic ROM;
- hybrid/contact reduction;
- production acceptance.

## Closure

```text
B0.1
RESEARCH CHECKPOINT CLOSED
EXACT-HEAD DOUBLE PASS
PROJECT CONTROL NON-BLOCKING
PRODUCTION ACCEPTANCE NOT CLAIMED
```

Next:

```text
B0.2
STRUCTURAL AGGREGATE BAKE
+ REFINEMENT GUARDS
+ LOCAL UNBAKE
```
