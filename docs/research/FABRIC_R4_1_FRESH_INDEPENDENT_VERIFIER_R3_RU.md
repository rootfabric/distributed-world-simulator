# FABRIC R4.1 — FRESH INDEPENDENT VERIFIER R3

```text
ROLE         = VERIFIER
SUBJECT_HEAD = 5ed03392edcdaf0efaf743423f12bd9e1550e70a
SUBJECT_TREE = ef7366f3452b812ab735c42d8447c3ca84c7bea3
STATUS       = PENDING_EXACT_CI
```

R1/R3 verifiers относятся к устаревшим subject `3afd12e...` / `ae924e...` и не переносит freshness на текущий repair.

R3 verifier-owned oracle не использует expected bytes product acceptance. Он независимо проверяет:

- аналитический branched bridge: `x=279/469`, `y=265/469`, `I_xy=2/469`;
- permutation determinism и отсутствие non-finite в successful details;
- большой representable finite ток/мощность;
- common-mode boundary-power case `R=5e306, 1e308/9e307`;
- representable `1e308` power с overflow-safe residual scale;
- compensated node-balance case, причём verifier отдельно доказывает, что naive partial sum действительно overflow;
- fail-closed RHS/current/power/conductance negatives;
- PERF diagnostic failure-shape с независимым sentinel primary error.

После primary oracle verifier переигрывает exact frozen R4.1 product runner в detached worktree на canonical Linux double. До успешного self-hosted run этот документ не является PASS и не разрешает новый freeze/R4.2 reveal.
