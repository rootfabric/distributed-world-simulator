# FABRIC R5.5 R1 — Windows exact validation handoff (implementer, not independent verifier)

Branch: `research/fabric-r5-5-incremental-successor-rom-isolation-r1` (PR #750, draft).
Base: R5.4 merge `56ab06936b902e8c752be06eafa2e4d16465cc82`.
Canonical Godot: `4.7.1.stable.double.custom_build.a13da4feb`,
SHA256 `3633c3e609c8ce2f9bae334a9c7e75c7f974de3af0415ab4a8050a625a15a7a5`.

## What the implementer changed after the initial PRODUCT_HEAD `f25b3d7a964cf19136d083398774e5bb78720daf`

1. `fix(fabric): use global is_same reference identity in R5.5 stage isolation status` —
   parse-defect repair: `Dictionary.is_same()` does not exist in canonical Godot;
   R5.5 originally failed to compile (`Function "is_same()" not found in base Dictionary`).
2. `test(fabric): R5.5 adversarial evidence and exact Windows focused runner` —
   additive `tests/research/fabric_bake0/fabric_r5_5_adversarial_evidence.gd`
   and `RUN_FABRIC_R5_5_TESTS.ps1` (exact-head runner, modeled on `RUN_FABRIC_R5_4_TESTS.ps1`).
3. `test(fabric): characterize scratch prefix tamper as undetected residual limitation` —
   falsifier outcome recording + doc limit.
4. `fix(fabric): unwrap single-value determinism comparison in R5.5 runner` — runner-only.

No closed kernel (R5.1/R5.3/R5.4, COMPLEX3) was modified; diff vs base touches only
R5.5 files, tests and docs.

## Reproduction (Windows, PowerShell 7.x)

```powershell
git fetch origin
git worktree add <wt> <PRODUCT_HEAD>
cd <wt>
.\RUN_FABRIC_R5_5_TESTS.ps1 -GodotBin <canonical godot console exe> `
  -ExpectedHead <PRODUCT_HEAD> -ExpectedTree <PRODUCT_TREE>
.\RUN_FABRIC_R5_4_TESTS.ps1 -GodotBin <canonical godot console exe> `
  -ExpectedHead <PRODUCT_HEAD> -ExpectedTree <PRODUCT_TREE>
```

Both runners verify: clean tracked tree, exact HEAD/tree, Godot version + SHA256,
cold import, `--check-only` parse, deterministic payload match across runs, strict
fatal-pattern failure. R5.4 gate additionally runs R5.3 regression, R5.1 100k
(`--count=100000`), `test_r5_4_evidence.py`, and `collect_r5_4_evidence.py`.

## Expected canonical results (Windows)

- `FABRIC_R5_5_RESULT={"checks":16,"failures":[]}` — identical across 3 runs.
- Adversarial payload: 30 checks, 0 failures; committed work counters
  `local_reconstructed_parts=20, range_query_count=4, range_query_prefix_reads=80,
  rebaked_components=2`; `r5_5_successor_full_builds=1`,
  `r5_5_successor_attempt_full_builds=0`, `r5_5_stage_index_isolated=true`;
  post-commit `machine_hash=0df084fd8517c2bb2780f68e6bfceaeb6a2be352adc762d2f16213689087bf98`,
  `local_recursive_changed=4 / reused=11`.
- Known undetected tamper (residual limitation, documented): scratch prefix mutation
  commits silently (`prefix_tamper.detection=NOT_DETECTED`).

Independent verifier must not trust this report; rerun both gates on a fresh worktree.
