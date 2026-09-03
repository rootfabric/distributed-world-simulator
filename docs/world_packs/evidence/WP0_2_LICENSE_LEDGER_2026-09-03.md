# WP0.2 Content License Ledger — 2026-09-03

Godot:
`4.7.1.stable.double.custom_build.a13da4feb`

Worktree:
`C:\distributed-world-simulator\wp-r1` (branch `feature/world-packs0-content-packs-r1`)

## Scope

WP0.2 makes third-party provenance mechanically enforced:

- `docs/world_packs/licenses/LEDGER.md` — policy + register (currently empty:
  no third-party assets are committed; R1 packs are asset-free by design);
- `docs/world_packs/licenses/SOURCE_TEMPLATE.md` — the exact per-asset
  `SOURCE.md` record format (10 required fields);
- `docs/world_packs/licenses/QUATERNIUS_GATE.md` — closed gate: no Quaternius
  file may be committed until a concrete pack/version passes license
  verification against the 2026-08-28 QAL terms;
- `tools/world_packs/check_asset_ledger.gd` — headless checker: every file
  under a provenance root requires a sibling complete `SOURCE.md`
  (`--root=res://assets/third_party` in real usage).

## Validation run

Entrypoint: `RUN_WORLD_PACKS_WP0_2_TESTS.ps1`.

Results:

- real root `assets/third_party` (absent/empty): PASS (enforced-empty baseline);
- complete provenance fixture: PASS;
- incomplete `SOURCE.md` fixture (empty `redistribution`, missing `checksum`):
  rejected — `WORLD_PACKS_LEDGER: FAIL (2 violation(s))`, exit 1;
- missing `SOURCE.md` fixture: rejected — exit 1;
- usage contract (unknown option): exit 2;
- sentinel: `WORLD PACKS WP0.2: PASS`.

## Boundary

No third-party asset was downloaded or committed in this milestone. The ledger
is the acceptance gate that future content-scout imports (#524/#525) must pass
before any binary enters `assets/third_party/`.
