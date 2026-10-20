# FABRIC R5.6.1 R2 — fresh reviewer finding: COM representability envelope

**Subject frozen HEAD:** `1b2e707c3605c502280efe157ed112816f85c6df`
**TREE:** `a5ddadb521d07afff5b4758d627c34a63ad2d629`
**Parent:** `716cddeee0cb479bcf4d96496510c0be033f5e64`
**Canonical Godot:** `4.7.1.stable.double.custom_build.a13da4feb`, Linux SHA256 `bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7`.

## Scope / verdict

`REVIEWER_CONCERN_REQUIRES_NUMERIC_ENVELOPE_DISPOSITION` — a reproducible representation precision gap, not a declaration that R2 promised a specific center-of-mass tolerance. **Do not mark final MERGE_READY until accepted scope or repair is explicit.** This is not the previously repaired inertia-cancellation bug.

## Reproducer

A new reviewer-owned script builds a genuine `ConstructionConstructSnapshot` containing two canonically valid point-mass records, each 1 kg, at positions `(offset, 0, 0)` and `(offset + ulp(offset), 0, 0)`. The source positions are *both representable* doubles (all `Snapshot.validate()` calls succeed). The physically exact center relative to the first part is `ulp(offset)/2`.

The R2 index correctly computes `Iyy = ulp(offset)^2/2`, but returns the COM as a **single absolute Float64** `cx + _origin.x`. For these inputs, the exact midpoint is halfway between representable floats; rounding back to an absolute float loses the entire fractional displacement. A subsequent subtraction of the original part position returns zero. `query_range()` returns `success=true` and no precision warning: its numerical guard covers tensor components, not COM representability.

| Offset (m) | Part separation (m) | Exact COM displacement from first part (m) | Published displacement (m) | Silent COM error (m) |
| ---: | ---: | ---: | ---: | ---: |
| 1e9 | 1.1920928955078125e-7 | 5.960464477539063e-8 | 0 | 5.960464477539063e-8 |
| 1e12 | 1.220703125e-4 | 6.103515625e-5 | 0 | 6.103515625e-5 |
| 1e13 | 0.001953125 | 0.0009765625 | 0 | 0.0009765625 |
| 1e14 | 0.015625 | 0.0078125 | 0 | 0.0078125 |
| 1e15 | 0.125 | 0.0625 | 0 | 0.0625 |

The reviewer asserts a *proposed*, not yet product-approved, 1e-6 m absolute accuracy floor for COM or explicit numeric rejection. Result on product: **RED, exit 1, 20 checks / 4 failed**. Baseline at 1e9 stays below 1e-6; the four higher offsets fail. Full raw stdout/stderr is attached. No changes to any product files.

## Analysis and options

This is a data-representation limitation of returning the center in one Float64 in global construct-local coordinates, **not a fixable issue by mere tighter summation**. A numerical fault should not be silently accepted if its estimated COM representation error violates the admitted envelope.

Disposition options:
1. **Narrow guard:** document `COM_ABS_PRECISION` and reject `query_range` if the computed world center, when projected back into the stable source-anchored local frame, loses more than the declared tolerance; return e.g. `R56_R2_RANGE_CENTER_PRECISION_UNSAFE` without mutating state. Source-relative `cx` is already available. Add RED→GREEN test and exact Linux/Windows gates. Tolerance must be justified by the physical floor, not chosen to make tests green.
2. **Schema evolution:** return center as source-anchor plus a high-precision local offset rather than a single `Float64` coordinate, requiring explicit downstream consumer contracts.
3. **Explicit bounded-input policy:** define a maximum safe local-coordinate envelope and reject source inputs outside it; note that this is narrower than present Construction snapshot validity. Test refusal.

If the research claim explicitly excludes the relevant coordinate magnitudes and documents a safe numerical domain, classify as a nonblocking scope limitation rather than falsely asserting a violated 1e-6 contractual threshold. Existing Windows exact PASS and old inertial RED→GREEN remain valid for their claimed scenarios.

**Next gate:** fresh separate-actor reviewer decides numeric envelope; if a repair is chosen, current HEAD/TREE must change and exact Windows/Linux and independent acceptance must be repeated. No merge, no main edits.
