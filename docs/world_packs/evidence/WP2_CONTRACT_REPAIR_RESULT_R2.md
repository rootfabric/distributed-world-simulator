# WP2 CONTRACT REPAIR R2 — RESULT EVIDENCE

- Previous reviewed/failing ancestor: `31177a5fcf01857823a3b22f77f63968f95fb3e9`
- Previous implementation repair (R1): `1cd63675b1dc0c41e4cc2dd66a06de27c564fa58`
- Subject HEAD at R2 start (verified live): `a343441140c2ca57aa47c465e74df081f5aded01`
- R2 repair commit (exact implementation HEAD, reviewed): `597018d6f94e050e603161e0de3dd52a9242cb40`
- Branch: `feature/world-packs2-readonly-presentation-adapter-r1` (normal push, no force)
- Observed main during repair: `fa2b6024481ea5a796ec9c7b0e2f9885f1a82c91` (live-fetched, untouched)
- Independent review R2 (PASS): branch `review/world-packs2-contract-r2`,
  evidence `docs/world_packs/evidence/WP2_CONTRACT_INDEPENDENT_REVIEW_R2.md`
  (durable at `19ef82ed553c2c53d0525c672385ef5724891cf9`)

## Per-finding result

| Finding | Fix | Status |
|---|---|---|
| R2.1 hidden global-axis default | `surface_normal` is a REQUIRED dataclass field (no default/factory, ordered before defaulted fields); construction without it raises `TypeError`; no `Vector3.UP`/`+Y`/`+Z`/radial fallback anywhere | REPAIRED |
| R2.2 recursive physical-field guard | forbidden-field walker recurses Mapping AND list/tuple; nested list, list-of-list, tuple fixtures all raise `PhysicalFieldError`; plain arrays (`asset_refs`/`tags`/states) still accepted | REPAIRED |
| R2.3 variation token width | retired `[:16]` (64-bit) truncation; token = full SHA-256 hexdigest (64 hex chars, 256 bits ≥ 128-bit minimum); semantics fixed: deterministic presentation variation key, NOT canonical/authority identity; body/surface/recipe/channel scoped, fidelity independent | REPAIRED |
| R2.4 composition key contract | keys must be non-empty UTF-8 strings (`CompositionKeyError` on `1`, `True`, `None`, `""`, mixed int/string); durable note `RUNTIME_COMPOSITION_KEY_SEMANTICS_PENDING_UPSTREAM_CONTRACT` (no invented `matter/<id>` semantics); canonical hash deterministic | REPAIRED |

## Validation

Windows (implementation worktree, exact HEAD `597018d6`):

```text
python -m pytest -q tests/world_packs/test_presentation_adapter.py
  -> 92 passed
python -m compileall -q tools/world_packs tests/world_packs
  -> exit 0
python -m pytest -q tests/world_packs
  -> 417 passed, 1 failed: test_local_missing_symlink_and_corruption
      (OSError WinError 1314 — Windows symlink privilege limitation, environment-only;
      NOT declared green, deferred to the Linux exact-head run below)
```

Linux exact-head acceptance (fresh Ubuntu WSL clone at `597018d6`;
`HEAD == origin/feature/world-packs2-readonly-presentation-adapter-r1` verified live
after `git fetch --all --prune`):

```text
python -m pytest -q tests/world_packs/test_presentation_adapter.py
  -> 92 passed in 0.09s
python -m pytest -q tests/world_packs
  -> 418 passed in 12.25s  (100% PASS, 0 failed, no deselect, no xfail;
      symlink test passes for real)
python -m compileall -q tools/world_packs tests/world_packs
  -> exit 0
```

## Proof A

Fixture regenerated deterministically at `597018d6`
(`contract_revision: WP2_CONTRACT_REPAIR_R2`); the independent reviewer rebuilt it
in memory and compared byte-equal. All 3×6 invariant cases hold (canonical before ==
after for both recipes, cross-recipe canonical equality, material/revisions unchanged,
presentation A != B, collision/mutation NOT_AVAILABLE — not fabricated).

## Final state after R2

- `config/world_packs/wp2_activation_state.v1.json`:
  `contract_review.state = REVIEWED_PASS`,
  `reviewed_head = 597018d6f94e050e603161e0de3dd52a9242cb40`,
  `review_environment = Linux`.
- WP2 runtime activation: **BLOCKED** (gates A/B/F not lifted).
- Proof B / Proof C: NOT STARTED. main: untouched.
- Subject branch **FROZEN** after this state commit. Next trigger only:
  P7.7 COMPLETE_MERGED + formal P7 ACCEPTED + WORLDGEN executable gate open +
  runtime scheduler slot granted, then a new live activation audit before any
  WP2 runtime integration.
