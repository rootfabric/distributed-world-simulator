# FABRIC R4.1 — FRESH INDEPENDENT VERIFIER R4

```text
ROLE         = VERIFIER
SUBJECT_HEAD = a5001eeafd012323548707d6b705b12301a91761
SUBJECT_TREE = 934ecfed15bd0f18389a64daf44caee6748cd73e
STATUS       = PENDING_EXACT_CI
```

R1/R2/R3 verifier executions are stale for freshness because they bind earlier product subjects or earlier verifier orchestration. R4 binds the corrected exact product subject above. The only product change after the prior runtime repair is the test-only restoration of the byte-decoding fixture helper; runtime solver code is unchanged.

Verifier-owned oracle is independent of the product acceptance expected values. It checks:

- analytical branched bridge: `x=279/469`, `y=265/469`, `I_xy=2/469`;
- insertion-order permutation determinism and recursive no-nonfinite successful details;
- representable high finite current/power;
- common-mode boundary-power cancellation;
- representable `1e308` power with overflow-safe residual scaling;
- a byte-constructed subnormal resistance case that proves naive partial node-balance overflow while the final signed balance stays finite/analytic;
- RHS/current/power/conductance fail-closed negatives;
- PERF diagnostic wrapper preserving an independent primary sentinel and explicit empty failure hash.

After the 24-check primary oracle, the workflow replays the exact R4.1 product runner from `a5001eeafd012323548707d6b705b12301a91761` in a detached worktree on the canonical Linux-double Godot. Until that self-hosted run succeeds, this document is not a PASS and cannot authorize Director/freeze/R4.2 reveal.
