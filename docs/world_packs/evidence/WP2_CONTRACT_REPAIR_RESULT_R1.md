# WP2 CONTRACT REPAIR R1 — RESULT EVIDENCE

- Repair map: `docs/world_packs/evidence/WP2_CONTRACT_REPAIR_MAP_R1.md`
- Old reviewed HEAD: `31177a5fcf01857823a3b22f77f63968f95fb3e9`
- Repair commit (exact HEAD for independent re-review): `1cd63675b1dc0c41e4cc2dd66a06de27c564fa58`
- Branch: `feature/world-packs2-readonly-presentation-adapter-r1` (normal push, no force, `31177a5f` not rewritten)
- Observed main during repair: `fa2b6024481ea5a796ec9c7b0e2f9885f1a82c91` (live-fetched, unchanged)

## Per-finding result

| Finding | Fix | Status |
|---|---|---|
| R1 frame vectors | Contract A: internal normalization; non-zero finite vector validation; alignment = abs(dot(n̂, ĝ)) ∈ [0,1] | REPAIRED |
| R2 immutable inputs | Deep-copy + recursive freeze (MappingProxyType/tuple); snapshot properties return fresh deep copies | REPAIRED |
| R3 fidelity semantics | `requested_fidelity` / `resolved_fidelity` split; fallback tier truthful | REPAIRED |
| R4 lock semantics | Option A: `presentation_selection_lock` over exact resolved selection incl. asset refs; requested-fidelity fallback defined as lock-invariant (tested) | REPAIRED |
| R5 Proof A | Real before/after canonical-hash protocol per recipe, 3 seeds × 6 surfaces; cross-recipe identity equality; tautology removed | REPAIRED |
| R6 variation token | `DWS-WP2-VARIATION-V1\|body_id\|surface_id\|recipe_ref\|channel`; fidelity-independent, body-scoped | REPAIRED |
| R7 version validation | Strict `recipe/<name>@X.Y.Z` key↔`version` match; rejects missing @version, invalid semver, mismatch, duplicate logical identity; no `latest` | REPAIRED |
| R8 strict numerics | Finite validation of position/vectors/composition (no bool/str); canonical hash `allow_nan=False`, deterministic strict JSON documented | REPAIRED |

## Validation at exact HEAD `1cd63675`

```text
python -m pytest -q tests/world_packs/test_presentation_adapter.py
  -> 69 passed

python -m pytest -q tests/world_packs
  -> 394 passed, 1 failed:
     tests/world_packs/test_library_contract.py::test_local_missing_symlink_and_corruption
     OSError WinError 1314 (Windows symlink privilege) — known Windows capability
     limitation, NOT declared green; Linux full clean run required for final
     exact review.

python -m compileall -q tools/world_packs tests/world_packs
  -> exit 0
```

## Proof A invariant evidence (new)

Fixture `fixtures/world_packs/proof_a/proof_a_contract_fixture.v1.json`
(`contract_revision: WP2_CONTRACT_REPAIR_R1`, stable-content sha256
`61f7330fa35dbfbfde50666a36e7086537def9fbe3bba4f76ce9e18b1198fe2b`) now carries, per
surface (3 seeds × 6 surfaces):

- `canonical_before_recipe_a` == `canonical_after_recipe_a` (resolution does not change canonical identity)
- `canonical_before_recipe_b` == `canonical_after_recipe_b`
- `canonical_after_recipe_a` == `canonical_after_recipe_b` == `canonical_input_hash`
- `material_id`, `matter_revision`, `representation_revision` unchanged
- `matter_snapshot_identity` and `geometry_source_identity` stable across all seeds
- collision identity `NOT_AVAILABLE_IN_CONTRACT_FIXTURE`, mutation log `NOT_EXERCISED_IN_CONTRACT_FIXTURE` — not invented

`test_proof_a_fixture_invariants` re-derives the deterministic samples independently and
re-resolves live with a fresh resolver, comparing every recorded selection byte-for-byte.

## Final state

- `config/world_packs/wp2_activation_state.v1.json`: `status: BLOCKED` (unchanged gates
  A/B/F), new `contract_review.state: FIXED_PENDING_REREVIEW`.
- WP2 runtime activation: **BLOCKED** (STOP not lifted by this repair).
- Proof B / Proof C: NOT STARTED.
- main: untouched.
- Godot runtime tests: not required (no Godot/runtime code added).
