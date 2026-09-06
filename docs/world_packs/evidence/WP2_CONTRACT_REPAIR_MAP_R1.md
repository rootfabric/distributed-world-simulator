# WP2 CONTRACT REPAIR MAP R1

- Reviewed exact HEAD: `31177a5fcf01857823a3b22f77f63968f95fb3e9`
- Branch: `feature/world-packs2-readonly-presentation-adapter-r1`
- Reviewer verdict: `WP2 CONTRACT PREPARATION = FIX_REQUIRED`, `WP2 RUNTIME ACTIVATION = BLOCKED`
- Runtime STOP is NOT lifted by this repair. No WORLDGEN runtime, Matter writes, RL adapter,
  network protocol, persistence, Proof B/C or main merge work is started here.

For each finding: review finding → root cause → affected code → test gap → selected repair → acceptance.

---

## R1 — FRAME VECTOR CONTRACT (mapping thresholds on unnormalized dot)

- **Review finding**: mapping thresholds (`ALIGNMENT_PLANAR_MIN = 0.85`,
  `ALIGNMENT_TRIPLE_MIN = 0.35`) are applied to the raw, unnormalized
  `dot(surface_normal, gravity_direction)`. Non-unit vectors therefore land in
  arbitrary mapping bands.
- **Root cause**: `select_mapping_mode` in `resolver.py` computes
  `abs(sum(n*g))` directly on input magnitudes.
- **Affected code**: `tools/world_packs/presentation/resolver.py::select_mapping_mode`;
  vector acceptance in `tools/world_packs/presentation/contract.py::WorldSurfacePresentationInput.__post_init__`.
- **Test gap**: no metamorphic scale-invariance test, no zero/NaN/Infinity rejection test.
- **Selected repair**: contract **A — normalize internally** (consumer DTO must not demand
  unit vectors):
  - `surface_normal`: required non-zero finite 3-vector;
  - `gravity_direction`: `None` allowed, otherwise non-zero finite 3-vector;
  - reject zero vectors, NaN, ±Infinity, malformed lengths at DTO construction;
  - mapping alignment = `abs(dot(normalize(n), normalize(g)))`, guaranteed `0 <= alignment <= 1`.
- **Acceptance**: metamorphic tests — `(0,0,1)/(0,0,-1)`, `(0,0,10)/(0,0,-3)`,
  `(0,0,0.1)/(0,0,-50)` all yield the same mapping mode; sign invariance of both normal
  and gravity; rejection tests for zero/NaN/Inf/malformed.

## R2 — TRUE IMMUTABLE RESOLVER INPUTS (shallow copy leaks nested state)

- **Review finding**: `dict(catalog_snapshot)` / `dict(recipes)` is a shallow copy —
  nested dicts stay shared; mutating the injected original (or the returned
  `catalog_snapshot` view) after construction changes resolver behavior.
- **Root cause**: `SurfacePresentationResolver.__init__` / `catalog_snapshot` property use
  one-level `dict()` copies.
- **Affected code**: `tools/world_packs/presentation/resolver.py` (constructor + property).
- **Test gap**: no negative mutation tests.
- **Selected repair**: deep-copy on construction into a closed internal representation,
  frozen recursively (nested `MappingProxyType` / tuples); `catalog_snapshot` returns a
  fresh thawed deep copy so mutating either the original or the view cannot reach
  internal state.
- **Acceptance**: negative tests — mutate original catalog, mutate returned view, mutate
  original recipes after construction; resolver output must be byte-identical.

## R3 — FIDELITY SEMANTICS (fallback lied about selected asset tier)

- **Review finding**: when the requested tier is missing (ice/ore fixtures only define
  `standard`), the output reported `fidelity = "high"` while actually serving the
  `standard` asset.
- **Root cause**: `SurfacePresentationSelection.fidelity` echoed the *requested*
  `ClientFidelity.level` unconditionally.
- **Affected code**: `resolver.py::resolve`, `contract.py::SurfacePresentationSelection`.
- **Test gap**: no fallback-tier truthfulness test.
- **Selected repair**: split fields — `requested_fidelity` (what the client asked) and
  `resolved_fidelity` (the tier actually selected). Preferred variant per review.
  `fallback_used` continues to mark binding fallback; tier fallback is now visible in
  `resolved_fidelity != requested_fidelity`.
- **Acceptance**: tests — request `high` with only `standard` present (ice/ore) →
  `requested_fidelity="high"`, `resolved_fidelity="standard"`; request `preview` with
  only `standard` → resolved `standard`; request existing exact `high` (silicate-rock) →
  resolved `high`, fields equal.

## R4 — PRESENTATION LOCK SEMANTICS (hash named as bundle identity it was not)

- **Review finding**: `presentation_lock` was documented as "exact prepared-bundle
  identity" but hashed a mixture of requested fidelity and selection inputs without
  pinned asset content identities.
- **Root cause**: lock blob in `resolver.py::resolve` mixed requested fidelity into a
  hash that was then described as a bundle identity.
- **Affected code**: `resolver.py::resolve`, `contract.py::SurfacePresentationSelection`,
  Proof A fixture output.
- **Test gap**: no regression matrix over lock inputs.
- **Selected repair**: **Option A — presentation selection lock**. Field renamed
  `presentation_selection_lock`. Lock covers exactly: recipe id + version, surface
  family, resolved variant + variant_version, resolved fidelity, mapping mode, scale
  parameters, exact resolved asset refs. Requested-but-fallback fidelity does NOT change
  the lock (the resolved selection is identical) — documented and tested. It is NOT a
  prepared-cache content identity and never claims to be one.
- **Acceptance**: regression tests — asset_refs change → lock changes; resolved variant
  changes → lock changes; mapping mode changes → lock changes; requested fidelity change
  with identical resolved selection → lock unchanged.

## R5 — PROOF A TAUTOLOGY (`assert x == x`)

- **Review finding**: `assert surface["canonical_input_hash"] == surface["canonical_input_hash"]`
  proved nothing; no real before/after resolution comparison existed.
- **Root cause**: fixture builder recorded a hash once and the test compared it to itself.
- **Affected code**: `proof_a.py::build_fixture` build-time asserts;
  `test_presentation_adapter.py::test_proof_a_fixture_invariants`.
- **Test gap**: no independent before/after canonical hash proof, no cross-recipe
  canonical identity proof, no material/revision identity checks.
- **Selected repair**: real invariant protocol per seed (3 seeds × 6 surfaces), per recipe:
  canonical hash BEFORE resolution → resolve → canonical hash AFTER resolution → assert
  equality; assert canonical hash under recipe A == under recipe B (independent
  resolutions); assert `material_id`, `matter_revision`, `representation_revision`,
  matter snapshot identity and geometry source identity unchanged. Collision/mutation
  identities remain `NOT_AVAILABLE` / `NOT_EXERCISED` — not invented.
- **Acceptance**: rewritten fixture carries `canonical_before/canonical_after` per recipe;
  the test re-derives everything independently from fresh samples and a fresh resolver.

## R6 — VARIATION TOKEN DOMAIN (cross-body collisions)

- **Review finding**: token input `f"{surface_id}|{ref}"` is not domain-separated; equal
  `surface_id` on two different bodies collide; channel is implicit.
- **Root cause**: `variation_seed` derivation in `resolver.py::resolve`.
- **Affected code**: `resolver.py::resolve`.
- **Test gap**: no cross-body collision test, no fidelity-independence test.
- **Selected repair**: domain-separated key
  `DWS-WP2-VARIATION-V1|{body_id}|{surface_id}|{recipe_ref}|{channel}` with explicit
  default channel `surface-presentation`. Seed is not part of the token (token is per
  stable canonical spatial identity: body + surface + recipe + channel); documented.
  No filesystem order, camera position, region owner or client fidelity enters the token.
- **Acceptance**: tests — same surface/recipe/channel across `preview` vs `high` clients
  → identical token; same `surface_id` on different `body_id` → different tokens;
  different recipe → different token.

## R7 — EXACT VERSION VALIDATION (key/version mismatch accepted)

- **Review finding**: recipe documents were only checked for physical fields; the key
  `recipe/foo@1.2.3` was never checked against `doc["version"]`.
- **Root cause**: `validate_recipe_document` covered only `FORBIDDEN_RECIPE_FIELDS`.
- **Affected code**: `contract.py::validate_recipe_document`, resolver construction.
- **Test gap**: no version-mismatch/malformed-key/duplicate-identity tests.
- **Selected repair**: strict recipe index validation on every load (file or injected):
  key must be `recipe/<name>@<semver>` with full strict semver (X.Y.Z, numeric);
  `doc["version"]` must exist and equal the key version; missing `@version`, invalid
  semver, key/version mismatch and duplicate logical identity rejected. No `latest`
  alias introduced.
- **Acceptance**: tests for each reject case plus acceptance of the shipped fixture
  document.

## R8 — STRICT NUMERIC CANONICAL INPUT (NaN/Infinity silently hashed)

- **Review finding**: `json.dumps` happily serializes `NaN/Infinity` into the canonical
  hash blob, so non-finite world state hashed silently.
- **Root cause**: no finite-value validation on `position_body_fixed`, vectors or
  `composition` values; canonicalization used default `json.dumps`.
- **Affected code**: `contract.py::__post_init__`, `canonical_input_hash`,
  `canonical_state`.
- **Test gap**: no non-finite rejection tests.
- **Selected repair**: validate finiteness of position, normal, gravity and every
  composition value (must be real `int`/`float`, finite; no bools/strings) at DTO
  construction; `canonical_input_hash` uses `json.dumps(..., allow_nan=False)` as a
  second hard stop. Deterministic strict form: sorted keys, `,`/`:` separators,
  `ensure_ascii=False`, UTF-8 — a bounded documented contract, not a new RFC
  canonicalizer.
- **Acceptance**: tests reject NaN/±Inf in each numeric field and non-numeric
  composition values.

---

## Out of scope (unchanged)

- WP2 runtime activation stays `BLOCKED` (gates A/B/F untouched).
- Proof B / Proof C: NOT STARTED.
- main: untouched; no merge.
- Godot runtime tests: not required (no Godot/runtime code added).

## Validation plan

```bash
python -m pytest -q tests/world_packs/test_presentation_adapter.py
python -m pytest -q tests/world_packs
python -m compileall -q tools/world_packs tests/world_packs
```

Linux full clean run required for final exact review if Windows symlink capability
(WinError 1314) blocks symlink-dependent suites; such a suite is NOT declared green here.
