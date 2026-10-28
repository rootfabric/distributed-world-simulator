# FABRIC R5.6.3 P0 — Coupled Pair Dynamics (research-only)

**Date:** 2026-10-26. **Status:** ISOLATED_LINUX_GODOT_DOUBLE_PASS / FULL_REPO_EXACT_PENDING / INDEPENDENT_REVIEW_PENDING / MERGE_READY=false.

## Identity, dependency, authority

- Research base (frozen R5.6.2 R1.3): PR #818, HEAD `d8e8361419b1fbcf0138c4deea18d19accc297f6`, TREE `7c5c0a4e6546b4f3f444c8a17582518c099b951e`.
- Branch: `research/fabric-r5-6-3-p0-coupled-pair-r1`. This is a stacked **advisory experiment**, not a promotion or the R5.6.3 R1 acceptance candidate.
- R5.6.2 **R2 owner receipts/outbox and process/power fault semantics remain the next mandatory authority stage**. The P0 predictor may be explored independently but may NOT mutate Construction or join canonical physical execution before that gate.
- Dependency #784 and stacked #800/#818 remain research Draft as observed. **No `main` push, no merge, no Construction/Matter/BRIDGE-4/physics production modification**.
- R5 CLOSE → INTEGRATION-R6 remains the accepted roadmap; do not insert a duplicate R5.7. SHIP-LAB-1 is a separate trial.

## Narrow goal

Prove that **two distinct moving point masses** can be advanced by a single coupled equal-and-opposite 3D spring/damper interaction without numerical instability or canonical writes. This does **not** claim two species of quantum excitations, emergent geometry, rigid-body rotation, contact/friction manifold, owner-authorized motion, multi-part atomicity or distributed exactly-once.

Input A/B: exact keys `{part_id, mass_kg, position_m[3], velocity_mps[3]}`; link: exact keys `{stiffness_npm,rest_length_m,damping_nspm}`; timestep seconds. The velocities are **derived trial variables**, not Construction authority. Before any future integration, caller must validate a live canonical `ConstructSnapshot` and the R5.6.2 lifecycle authority/source fence; this P0 deliberately has no such API.

Let `r=x_b-x_a`, `n=r/|r|`, `v_r=(v_b-v_a)·n`. Internal pair force on A is

`F_a=[k(|r|-L)+c v_r]n,  F_b=-F_a`.

Semi-implicit Euler predicts `v_i'=v_i+dt·F_i/m_i`, then `x_i'=x_i+dt·v_i'`. The action/reaction structure conserves total linear momentum up to explicit floating-point acceptance budget. Energy is **diagnostic only**, not a conserved exactly-integrated quantity; damping need not give global discrete energy monotonicity at all timesteps.

### Fail-closed research envelope

- Both masses finite, positive, ≤1e12 kg; distinct `part/` IDs; no unexpected body/link fields.
- Position coordinates finite, |component|≤1e9 m; velocity components finite, |component|≤1e8 m/s.
- Link stiffness finite and positive, rest length and damping finite/nonnegative; direction defined (distance >1e-12 m).
- `0<dt≤0.1 s`; stiffness number `dt·sqrt(k(1/m_a+1/m_b))≤0.1`; damping number `dt·c(1/m_a+1/m_b)≤0.1`.
- Every output component and energy finite/within envelope; momentum residual ≤ `1e-10 max(1,|P_before|)` kg·m/s.
- On failure: typed error, no state/write/partial successor. On success: `canonical_writes=0`, `authority=DERIVED_PREDICTION_ONLY`.

## P0 local evidence

Executed **twice** in a stand-alone minimal Godot project, *not* in the full repository checkout:

- Godot Linux **4.7.1 double** (`4.7.1.stable.double.custom_build.a13da4feb`), executable SHA256 `bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7`.
- Identical result each run: `checks=438, failures=[], negatives=12, max_energy_drift_ratio=0.0020370820818046043`.
- Both raw stdout logs SHA256 `badfda1cf805760c736eeecd059f642bd4c14e40a94252380d068df14319862e`; exit code 0 both.
- Exact local script Git blob SHA: predictor `cd36048523a7f86928d8891e9f6a0fc8362b1f23`, test `5f27f60092a05bccfb928adcabdff37648238c66`. Match published GitHub content before claiming identical-source evidence.
- Scenarios: static equilibrium; stretched spring; Newton's third law; total momentum/COM; swapping A/B; translations; damping; 200-step small-dt trajectory; 3D isotropy and rotation; 12 independent malformed/unstable rejection checks.
- This is **not** independent Windows/Linux repo-exact signoff. The scoped GitHub CI and later separate Reviewer/Verifier must run independently.

## Work Order: subsequent gates

1. **P0 branch CI:** exact source scope, no other file changes; full repo cold imports and same 438/0 + 12 negatives on canonical pinned Linux Godot, deterministic two-run byte identity; preserve logs and hashes; any import errors are FAIL.
2. **Fresh independent Reviewer:** reverse/swap roles, translation/rotation, high-offset cancellation, mass ratios, dt/stiffness/damping boundaries, energy-drift restrictions, NaN/inf, malicious extra source/auth fields, and the non-authoritative nature of input.
3. **Fresh Verifier:** identical published HEAD/TREE, Godot double SHA, exact raw CI, no direct Construction/Matter writes, no user-world side effects and no regression of #818.
4. **Separate required R5.6.2 R2:** owner-authenticated receipt/outbox + crash/power fault matrix + source fencing. Its absence prohibits any R5.6.3 owner mutation, physical publication or merge.
5. **Future R5.6.3 R1:** source-bound, atomically owner-admitted coupled step, many-pair interaction graphs, multi-body conservation/constraints and crash/restart continuity, then R5.6.4 budget and R5.6.5 performance/generalization.

**MERGE_READY=false**, explicit human research-branch merge approval required. This document is an implementer P0 evidence map, not an independent review signature.
