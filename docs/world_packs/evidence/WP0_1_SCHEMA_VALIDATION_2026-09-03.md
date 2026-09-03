# WP0.1 Pack Contract / Schema Validation — 2026-09-03

Godot:
`4.7.1.stable.double.custom_build.a13da4feb`

Worktree:
`C:\distributed-world-simulator\wp-r1` (branch `feature/world-packs0-content-packs-r1`)

## Scope

WP0.1 closes the pack contract as a machine-checkable artifact:

- `config/world_packs/pack_schema.v1.json` is now a real JSON Schema (draft-07)
  instead of a descriptive field list;
- `tools/world_packs/validate_pack.gd` validates manifests headlessly
  (subset: type, const, enum, pattern, minLength, minItems, maxItems,
  uniqueItems, items, required, properties, boolean additionalProperties);
- unknown optional manifest fields are ignored by contract
  (`additionalProperties: true`, exercised by the valid fixture).

Contract tightening vs the WP0.0 descriptive schema:

- manifests must carry `"schema": "dws.world_pack.v1"` (const);
- `pack_id` pattern `^WP-[A-Z0-9]+(-[A-Z0-9]+)*$`;
- `version` pattern `^(R[0-9]+|[0-9]+\.[0-9]+\.[0-9]+)$`;
- catalogs require non-empty unique string items;
- `compatibility.requires_world_fill_features` items must match
  `^wf\.[a-z0-9]+(\.[a-z0-9]+)*$` (WF feature identifier namespace);
- `x-canonical-state: false` — the pack never carries canonical state.

## Fixtures

`tests/world_packs/fixtures/`:

- `wp-demo-valid.v1.json` — conforming WP-MOON-INDUSTRIAL demo manifest
  (includes an unknown optional field that must be ignored);
- `wp-demo-missing-required.v1.json` — missing required `decals`;
- `wp-demo-bad-identity.v1.json` — bad `pack_id` and `version` patterns.

## Validation run

Entrypoint: `RUN_WORLD_PACKS_WP0_1_TESTS.ps1` (fresh-worktree import preflight,
then focused headless runs).

Results:

- usage contract (no arguments): exit code 2 — PASS;
- valid fixture: `WORLD_PACKS_VALIDATE: PASS (1 manifest(s))` — PASS;
- missing-required fixture: rejected with
  `<root>: missing required field 'decals'` — PASS (expected rejection);
- bad-identity fixture: rejected with both pattern violations — PASS
  (expected rejection);
- directory mode (`--dir`) over a batch of valid manifests — PASS;
- sentinel: `WORLD PACKS WP0.1: PASS`.

Exit-code contract of the validator: 0 = valid, 1 = invalid manifest, 2 = usage/IO error.

## Boundary

This validates the manifest contract mechanics only. It does not accept any
third-party asset (WP0.2 ledger still governs that) and does not touch
P7/WORLDGEN/ECO/FABRIC/NETWORK/persistence truth.
