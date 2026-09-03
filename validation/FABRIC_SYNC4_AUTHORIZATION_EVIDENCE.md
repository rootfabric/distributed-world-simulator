# FABRIC.SYNC4 — Authorization Evidence

## Qualification

```text
FABRIC.SYNC4
POST-B0.5-A + COMPLEX0/COMPLEX1A DEVELOPMENT REVIEW
CLOSED

COMPLEX0-PERF1:
CLOSED

COMPLEX0 @ 2000:
EXACT DOUBLE VERIFIED / CLOSED

FABRIC0.19:
NOT AUTHORIZED

BRIDGE-2 EXECUTABLE RESEARCH:
AUTHORIZED

PROJECT CONTROL:
implementation subject PASS

NOT PRODUCTION ACCEPTED
```

## Exact implementation subject

```text
branch:
research/fabric-bake0-5-a-executable-hybrid-r2

HEAD:
5f1d2dc997ecce5cf1f188a6f65d7b1c2ba0ecd9

TREE:
d094c969a4252eb77f697d142271b9f74c3f1589

tracked clean:
YES
```

## Canonical Godot

```text
4.7.1.stable.double.custom_build.a13da4feb

binary SHA-256:
bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7

archive SHA-256:
d7a184b893d4e3ad4d4b6cb2e3a4fbb52997dfc87e4f00d2a7f24ac075903b92
```

## Exact-source provenance

```text
B0.5-A Exact Source Carrier:
run 33727368693
SUCCESS

artifact:
9882476413

downloaded artifact zip SHA-256:
28f8b39d01c845dfa2b3663add0c5eef590d3d39b34b36ccc8d01a9d924175a1

exact source bundle SHA-256:
e93db23407b727b6c7ac88d66190b215ef6bfbf1f3cf265d3466f9a2f3bfd4ef
```

The bundle was cloned, checked out at the exact implementation HEAD, and the
tracked worktree was clean before execution.

## Exact-double acceptance

Host:

```text
Debian GNU/Linux 13 (trixie)
Linux 6.18.35 x86_64
AMD EPYC 9V74 80-Core Processor
```

Results:

```text
COMPLEX0 / 50:
5/5 PASS

COMPLEX0 / 100:
11/11 PASS

COMPLEX0 / 500:
54/54 PASS
fragments = 243 + 257
post-split reduction = 250x

COMPLEX0 / 2000 exact closure:
25/25 PASS
fragments = 993 + 1007
post-split reduction = 1000x
transaction checksum =
b421928b2a5db9e700476d9d70e2be6b6ecde8bfe778b2511a1efaf85d082ebd
max reconstruction state error =
0.00000000000002

COMPLEX0-PERF1:
19/19 PASS

COMPLEX1A:
93/93 PASS
```

PERF1 measurements:

```text
500:
build_ms       79
structural_ms  1809
break_ms       84
transaction_ms 1967
checksum:
a606954658e0ab87eca2cb1b6ff2280b4ad7ebd56f125e3fbad3767e103ed828

2000:
build_ms       306
structural_ms  7699
break_ms       336
transaction_ms 8647
checksum:
b421928b2a5db9e700476d9d70e2be6b6ecde8bfe778b2511a1efaf85d082ebd

transaction growth:
4.39603457041179x

allowed growth:
<= 8x
```

Local log SHA-256 values recorded during this verification:

```text
COMPLEX0 / 50:
5de61e4d959e73ac3d958878a3e9e2e8643ba80937b4095218ef47fea93c903c

COMPLEX0 / 100:
f2403df1cd9498631f76214147996a2fb81cbccc50b0f9427ebc07d8cc66570b

COMPLEX0 / 500:
a63053ec969a5f92f48926cd1e11d3adb20043820fc25f884653160479e7e251

COMPLEX0 / 2000:
522c2fe942b14b697c5ed9cd93abe4e424d84826c2cafa0ddc315c86aa5df429

COMPLEX0-PERF1:
45889d612debb91083a22da85e12e80d5b5deae9da62e5d89186b19ba68707b9

COMPLEX1A:
5c2e5ccb49c07c8709ed1bee879c365444127d57b2a245d58c936eb7226c406a
```

These hashes identify the local evidence files but do not convert them into
canonical repository artifacts. Canonical durable evidence is this document,
the JSON authorization record, the exact source carrier, and repository tests.

## GitHub control evidence on implementation subject

```text
Project Control:
33727368612
SUCCESS

Complex Labs Portable Smoke:
33727368928
SUCCESS

B0.5-A Exact Source Carrier:
33727368693
SUCCESS

Complex Labs Linux Double Verification:
33727368671
QUEUED at review time
```

The queued self-hosted Linux job remains valid supplementary independent
verification. This closure does not falsify its status and does not claim it
completed.

## PERF1 finding

The observed old multi-minute wall clock was not an executable B0.2-E semantic
or algorithmic falsifier. Clean exact measurement produces approximately linear
growth at this rung.

The acceptance harness was corrected to avoid retaining and recompiling multiple
large 2000-part transaction graphs solely for determinism and to use dedicated
fresh-process exact closure.

No production/runtime compiler tolerances were weakened.

## Authorization decision

```text
FABRIC0.19:
NOT AUTHORIZED

reason:
no missing generic Physical Core primitive demonstrated

BRIDGE-2 EXECUTABLE RESEARCH:
AUTHORIZED

reason:
B0.5-A executable transition/handoff/lazy-cache evidence is closed;
COMPLEX0 proves canonical mutation/invalidation/split/rebake;
COMPLEX1A provides the FULL causal oracle for mixed execution.
```

## Scope of authorization

Authorization permits research implementation of mixed:

```text
FULL
↔ STRUCTURAL_BAKE
↔ CONTACT_BAKE where valid
↔ DYNAMIC_ROM
↔ HYBRID_BAKE
```

subject to:

- canonical Construction/Matter remains truth;
- no representation gains canonical ownership;
- exactly one owner per physical event;
- common invalidation/refinement ordering;
- stale physical artifacts never execute;
- deterministic replay;
- no hidden authority crossing;
- unsupported/uncertified regions fail closed to FULL / NO_SAFE_BAKE.

## Next executable

```text
BRIDGE-2
→ COMPLEX1B POWERED FENCE MIXED
→ CX2 REDUNDANT POWER FENCE
```

## Verdict

```text
FABRIC.SYNC4
VERIFIED / CLOSED

BRIDGE-2 EXECUTABLE RESEARCH
AUTHORIZED

FABRIC0.19
NOT AUTHORIZED

NOT PRODUCTION ACCEPTED
```
