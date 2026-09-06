# WP2.0 CONTRACT PREPARATION + PROOF A FIXTURE — EVIDENCE (2026-09-06)

Base: `integration/world-packs-wp1-2-foundation-r1@c99bbd72`.
Вердикт активации: **WP2 RUNTIME ACTIVATION = BLOCKED; contract-only AUTHORIZED**
(см. `WP2_ACTIVATION_AUDIT_2026-09-06.md` и `config/world_packs/wp2_activation_state.v1.json`).

## Что сделано (safe parallel work only)

- `tools/world_packs/presentation/contract.py` — immutable
  `WorldSurfacePresentationInput` (normal и gravity — РАЗДЕЛЬНЫЕ опциональные
  body-fixed вектора; gravity может отсутствовать) и presentation-only
  `SurfacePresentationSelection` (без mass/density/strength/collision/
  authoritative geometry/network ownership; guard `PhysicalFieldError`).
- `tools/world_packs/presentation/resolver.py` — generic read-only resolver:
  canonical Matter snapshot → material family → versioned recipe →
  surface family/variant/mapping mode/scale/lock/variation token.
  Mapping mode использует |normal·gravity| полосы, инвариантен к знаку,
  отсутствию gravity и глобальным осям (нет +Y up, нет radial-only).
- `config/world_packs/presentation/matter_catalog_snapshot.v1.json` —
  read-only снапшот 7 фактических Matter IDs с origin/main@fa2b602.
- `config/world_packs/presentation/surface_recipes.v1.json` — два artistic
  recipe (dark basaltic / light dusty) + явный debug-neutral fallback binding.
  Схема отвергает любые физические поля в recipes (layer_depths и пр.).
- `tools/world_packs/presentation/proof_a.py` + committed fixture
  `fixtures/world_packs/proof_a/proof_a_contract_fixture.v1.json`
  (stable-content sha256 `a4000ebdc539e369b6f57c49b5790c9e4a12751e3bf4afc3df43c48e455731f1`).

## Proof A (contract level)

SAME canonical input (3 seeds × 6 поверхностей: floor, slope, wall, inward
ceiling, ceiling с inward gravity, irregular facet без gravity):
`canonical_input_hash`, `matter_snapshot_identity`, `geometry_source_identity`
идентичны под recipe A и B; отличаются только `surface_family`, `variant`,
`scale_parameters`, `presentation_lock`. Two-client capability: preview vs
high fidelity на том же canonical input — разный variant, тот же canonical
hash. Никакого утверждения «basalt физически стал sandstone» — только
presentation. Collision/mutation identity честно записаны как
NOT_AVAILABLE/NOT_EXERCISED (runtime заблокирован, hash-и не выдуманы).

## Validation (exact worktree)

```text
python -m pytest -q tests/world_packs        -> 347 passed, 1 failed
python -m compileall -q tools/world_packs tests/world_packs -> exit 0
```

Единственный FAIL — известный environmental Windows symlink-тест
(`test_local_missing_symlink_and_corruption`, WinError 1314), задокументирован
в FOUNDATION DONE R2 как Linux-green; не связан с WP2.

## Границы

Runtime integration (Godot adapter, real representation boundary, real
WORLDGEN) НЕ выполнялась и не могла выполняться: gates A/B/F закрыты.
Canonical ownership не тронут: нет новых Matter materials, нет writes, нет
terrain/collision/chunk authority, нет networking, нет persistence.
