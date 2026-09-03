# WORLD PACKS — Content License Ledger

Status: **enforced (WP0.2)**

Every third-party asset imported anywhere under `assets/third_party/` requires
complete provenance before it may be committed to this public repository.

## Rules

1. Each third-party asset lives in its own directory:
   `assets/third_party/<source>/<asset_name>/`.
2. That directory must contain `SOURCE.md` following
   `docs/world_packs/licenses/SOURCE_TEMPLATE.md` with **all** fields filled:
   `source_url`, `creator`, `asset`, `download_date`, `license`, `license_url`,
   `redistribution`, `modifications`, `checksum`, `files_imported`.
3. No ambiguous asset is committed. If redistribution permission is unclear,
   the asset stays out of git.
4. Quaternius content is additionally gated by
   `docs/world_packs/licenses/QUATERNIUS_GATE.md`.
5. Enforcement is mechanical: `tools/world_packs/check_asset_ledger.gd`
   (runner: `RUN_WORLD_PACKS_WP0_2_TESTS.ps1`). Any file under
   `assets/third_party/` without a complete sibling `SOURCE.md` fails the check.

## Register

| Directory | License | Redistribution | Checksum | Notes |
|---|---|---|---|---|
| *(empty — no third-party assets committed yet)* | — | — | — | R1 packs are asset-free by design |

The R1 pack family (WP0.3–WP0.8) is intentionally **asset-free**: all identity
is procedural presentation. External CC0 candidates (Poly Haven, ambientCG,
Kenney) are evaluated by the content-scout work orders and may only land here
through this ledger.
