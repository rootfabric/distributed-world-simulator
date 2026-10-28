# FABRIC R5.6.1 R2 — numeric conditioning narrow repair (post-RED)

## Reproduced original defect

Independent GDScript falsifier run on frozen R2 R1 HEAD
`2ea4debdcef7a38dc1de2a0acc9a906ccfcea442` with canonical Linux double Godot
`4.7.1.stable.double.custom_build.a13da4feb` demonstrates two 1 kg parts
at x=100000000 and x=100000001: the original origin-based ten moments
publish **Iyy=0** instead of the independent centered sum **0.5 kg*m^2**.
The same occurs at x=10^9. ConstructionPartRecord validates those finite inputs.
This is a false physical result, not a hash or transaction issue.

## Narrow solution

- Represent moment sums in a translated, fixed-at-initialization source frame,
  with origin equal to the first source part's coordinate. This removes large
  common offsets BEFORE squaring positions; the resulting tensor around the
  center of mass is translation-invariant. Return center of mass in canonical
  construct coordinates by adding the origin back.
- On sparse owner-verified mutations, calculate moment differences against
  the SAME per-index origin and update only O(k log N) affected BIT nodes.
- For still ill-conditioned *range queries* (e.g., two nearly co-located
  parts far from the reference), estimate conservative roundoff from the
  magnitudes of both Fenwick prefixes and centroid shifts; return
  `R56_R2_RANGE_NUMERIC_PRECISION_UNSAFE` instead of accepting a false result.
  No mutation is performed during failed query.
- This guard is a bounded engineering numeric contract, NOT rigorous interval
  arithmetic, arbitrary-precision sums, or a universal accuracy guarantee.
  Future R5.6.3 coupled mechanics will need an independent trajectory/energy
  oracle and explicit conditioning/scale envelope.

## Mandatory tests

`fabric_r5_6_1_r2_numeric_conditioning_acceptance.gd`: **54/0** expected,
correct point-mass inertia for offsets [1,1e5,1e7,1e8,1e9], sparse update
compares against exact analytic point-pair inertia, and a far-offset narrow
range fails closed with no change to derived state.

Existing R2 3x626, 100k scale 255, inherited R1 203 / narrow 26 / BRIDGE-4
49 must remain unchanged. Collector schema upgraded to v2, strict numeric
marker and 11/11 tamper rejection required.

## Scope and authority

R2 remains a point-mass only, non-authoritative derived Construction consumer.
Index math has O(k log N) updates; authorizing canonical mutations and binding
BRIDGE-4 can still require O(N). No core Construction/Matter/R5.1-R5.5 edits.
No main, no automatic merge; independent Windows/Linux exact and separate
Reviewer/Verifier on final new HEAD/TREE remain mandatory.
