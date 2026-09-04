# FABRIC COMPLEX2-D — Independent Structural Failure — Exact Evidence

## Verdict

```text
COMPLEX2-D PHYSICAL EXACT: PASS
ASSERTIONS:                50 / 50
INDEPENDENT REPLAY:        PASS
MIXED vs FULL:             PASS
GLOBAL PROJECT CONTROL:    RED — unrelated pre-existing ownership/passport drift
DEDICATED SELF-HOSTED D:   QUEUED when evidence recorded
```

This record separates the executable FABRIC research result from the repository-wide Project Control health signal.

## Exact executable identity

```text
branch: feature/fabric-complex2-modular-machine-r1
HEAD:   3ac206b02c77002fe62bc937105ee67e1ef46260
TREE:   64be92fbcb535c973b9eb22935510a016d1cf18d
```

Source carrier:

```text
workflow: FABRIC BRIDGE-2 Exact Source Carrier
run:      33885515320
artifact: 9941665844
digest:   sha256:6d1f1a871d6501216faff103b7ac7dcceb1b82c868ec11ac4a9cec1ccd75235d
bundle:   sha256:b7e1ad38c093f9e5dbc7cabe29b73509635e01ac48b00946361e86b181258182
```

Bundle checksum passed and the detached checkout resolved exactly to the HEAD/TREE above.

## Canonical Godot

```text
4.7.1.stable.double.custom_build.a13da4feb
SHA256 bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7
```

Two independent bundle checkouts were executed as a non-root user. Both returned code 0 and the same integrated hash:

```text
5dcc2f802c5aaf444eeca2c910aab9973205ab7ab2d4c3b2caada3257b27b580
```

Exact marker:

```text
FABRIC COMPLEX2-D Independent Structural Failure Acceptance: PASS (50 assertions) redundant_path=FAIL redistributed=PASS connected=PASS atomic_rebuild=FULL+CONTACT mixed=FULL_REFERENCE scene=PASS
```

## Independent failure subject

The failed support is:

```text
brace/complex2-12-16
```

It is deliberately distinct from both earlier COMPLEX2 failure supports:

```text
support/complex2-23-24   # detachable head / path A
support/complex2-10-11   # prior drive support / path B
```

Therefore D is not a replay of A's detachable endpoint or the earlier functional-path break.

## Redundant load path result

Five canonical modules `12..16` form a load subnetwork with four chain supports plus the independent brace. Under the 100 N certification load:

```text
brace force before failure = 61.608243 N
tip before                 = 0.123216486 m
tip after                  = 0.320945163 m
chain-force ratio          = 2.604726
post-failure equilibrium residual ≈ 2.84217e-14 N
```

After brace loss:

- the failed brace carries zero load;
- the machine remains one connected component containing all 25 modules;
- the chain supports inherit the redistributed load;
- static equilibrium and strain-energy/work identity remain within exact acceptance bounds;
- functional topology and functional solution do not change.

This distinguishes structural degradation from detachment and from electrical/functional topology loss.

## Mixed representation lifecycle

The canonical support failure changes source projections for exactly:

```text
region/complex2-full
region/complex2-contact
```

Acceptance proves:

1. both derived artifacts become stale;
2. mixed execution is blocked fail-closed while stale;
3. a partial single-region rebuild fails with `BRIDGE2_REBUILD_REGISTRY_FAILED`;
4. one atomic FULL+CONTACT rebuild succeeds;
5. both handoff errors are zero;
6. mixed execution resumes and remains equal to FULL reference within `1e-12`;
7. the COMPLEX2-C DYNAMIC backend and COMPLEX2-B HYBRID backend remain unchanged;
8. the exact five representation kinds are preserved.

Fail-closed guards include:

```text
COMPLEX2D_EVENT_ALREADY_APPLIED
COMPLEX2D_REFINEMENT_REQUIRED_LOAD
COMPLEX2D_REFINEMENT_REQUIRED_DEFLECTION
```

## Project Control caveat

Project Control run `33885515305` failed in the repository-wide step:

```text
Run architecture and ownership passport compatibility regression
```

The failure reports pre-existing `CRITICAL_DEPENDENCY_DRIFT` / passport RED status in G, ECO and V0, naming Matter/P7/control files outside the COMPLEX2-D change set. D's checkpoint-session regression passed before that step. This evidence therefore does not relabel Project Control as green and does not attribute the unrelated ownership drift to D.

## Conclusion

`COMPLEX2-D Independent Structural Failure` is **exact-verified at the physical research boundary**. It proves load redistribution and bounded multi-region rebuild for a structurally independent failure while retaining connectivity and functional topology. Repository-wide Project Control remains a separate RED control-plane issue.