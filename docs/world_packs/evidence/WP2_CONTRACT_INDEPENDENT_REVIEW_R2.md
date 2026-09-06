# WP2 CONTRACT INDEPENDENT REVIEW R2

- Reviewed branch: `feature/world-packs2-readonly-presentation-adapter-r1`
- Reviewed exact HEAD (verified live): `597018d6f94e050e603161e0de3dd52a9242cb40`
- Commit: `fix(world-packs): close WP2 contract R2 edge cases`
- Review range: `a3434411..597018d6` (6 files: 4 under `tools/world_packs/presentation/`,
  `tests/world_packs/test_presentation_adapter.py`,
  `fixtures/world_packs/proof_a/proof_a_contract_fixture.v1.json`)
- Reviewer: independent role context; NOT the R2 repair implementer (fresh reviewer agent,
  read-only access to the subject worktree; no commits made during review).
- Review environment: Windows worktree review + Linux exact-head acceptance (fresh Ubuntu
  WSL clone of the subject branch at `597018d6`).

## VERDICT

```text
PASS
```

## Per-section findings

### Ownership

OK — diff `a3434411..HEAD` touches only `tools/world_packs/presentation/`, the adapter
test file and the regenerated Proof A fixture. No Matter writes, no WORLDGEN runtime, no
RL runtime ownership, no networking, no persistence, no main changes.
`config/world_packs/wp2_activation_state.v1.json` gates A/B/F untouched; WP2 runtime
remains BLOCKED.

### Frame contract (R2.1)

OK — `WorldSurfacePresentationInput.surface_normal` is a REQUIRED dataclass field with no
default and no default factory, ordered before all defaulted fields. The previous
`(0.0, 0.0, 1.0)` hidden global-axis default is removed; grep of the whole range confirms
no `Vector3.UP` / `+Y` / `+Z` / radial fallback is reintroduced anywhere (the only
`(0,0,1)` occurrences are explicit caller-supplied arguments in `proof_a.py` and tests).
Construction without `surface_normal` raises `TypeError` (tested). `gravity_direction`
remains explicitly optional (`None` allowed). Consumers normalize internally; zero/NaN/Inf
vectors rejected at construction.

### Read-only

OK — frozen dataclasses, `MappingProxyType` composition, resolver deep-copy +
`_deep_freeze` internal state, snapshot properties return fresh deep copies; no write-back
path exists.

### Presentation-only (R2.2)

OK — the forbidden-field walker recurses through Mapping AND list/tuple. Rejected:
top-level, nested dict, nested list (`layers: [{density: ...}]`), list-of-list, tuple.
Plain arrays (`asset_refs`, `tags`, presentation-only `states`) still accepted (tested).

### Fidelity

OK — `requested_fidelity != resolved_fidelity` allowed and truthful; the selected asset
tier is reported as actually resolved; `presentation_selection_lock` covers the resolved
selection only (requested fidelity excluded, fallback yields the same lock — tested).

### Proof A

OK — the committed fixture (`contract_revision: WP2_CONTRACT_REPAIR_R2`) was rebuilt
independently by the reviewer in memory and compares byte-equal (deterministic). For every
3 seeds × 6 surfaces: canonical hash before A == after A, before B == after B,
A canonical == B canonical; `material_id`/`matter_revision`/`representation_revision`
unchanged; presentation A != presentation B; collision/mutation identities remain
`NOT_AVAILABLE`/`NOT_EXERCISED`, not fabricated.

### Variation (R2.3)

OK — token is the full SHA-256 hexdigest (64 hex chars, 256 bits ≥ 128-bit minimum);
the retired `[:16]` (64-bit) truncation is gone. Domain-separated
(`DWS-WP2-VARIATION-V1`), body-scoped, surface-scoped, recipe-scoped, channel-scoped,
fidelity-independent; no camera/filesystem/region-owner inputs. Documented as a
deterministic presentation variation key — NOT canonical world identity, NOT authority
identity (inequality with `canonical_input_hash` tested).

### Composition (R2.4)

OK — composition keys must be non-empty UTF-8 strings; `1`, `True`, `None`, `""` and
mixed int/string keys all raise `CompositionKeyError` (tested). Durable note
`RUNTIME_COMPOSITION_KEY_SEMANTICS_PENDING_UPSTREAM_CONTRACT` is present and exported;
no invented `matter/<canonical-id>` semantics. Canonical hash stays deterministic
(sorted-key strict JSON, `allow_nan=False`).

### Versioning

OK — R7 exact versioned recipe identity (`recipe/<name>@X.Y.Z`, strict semver, no
`latest`, duplicate logical identity rejected) intact and unchanged in the range.

## Test evidence

Reviewer-side (subject worktree, exact HEAD):

```text
python -m pytest -q tests/world_packs/test_presentation_adapter.py
  -> 92 passed
```

Independent Linux exact-head acceptance (fresh Ubuntu clone at `597018d6`,
`HEAD == origin/feature/world-packs2-readonly-presentation-adapter-r1` verified live
after `git fetch --all --prune`):

```text
python -m pytest -q tests/world_packs/test_presentation_adapter.py
  -> 92 passed in 0.09s
python -m pytest -q tests/world_packs
  -> 418 passed in 12.25s   (0 failed, no deselect, no xfail; symlink test passes for real)
python -m compileall -q tools/world_packs tests/world_packs
  -> exit 0
```

## Consequence for control state

Per the R2 work order, on this PASS the subject branch state may be updated in a separate
controlled commit to `contract_review.state = REVIEWED_PASS` with
`reviewed_head = 597018d6f94e050e603161e0de3dd52a9242cb40` and
`review_environment = Linux`. WP2 runtime `status = BLOCKED` REMAINS in force; Proof B /
Proof C remain NOT STARTED; main remains untouched; the subject branch is FROZEN after
that state commit. Next trigger only: P7.7 COMPLETE_MERGED + formal P7 ACCEPTED +
WORLDGEN executable gate open + runtime scheduler slot granted, followed by a new live
activation audit before any WP2 runtime integration.
