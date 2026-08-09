# Universal World Generation Fabric — status ledger

**Current branch:** `feature/g6-hydrology-fluid-surface-v0`  
**Global revision:** `GLOBAL-P0-2026-08-08-R1`

```text
G6.0 Fluid Contracts                   ACCEPTED
G6.1 CasualRiverProviderV1             ACCEPTED
G6.2 Cross-Cell / Cross-LOD Continuity ACCEPTED
G6.3 Runtime WaterSurfaceQuery         ACCEPTED
G6.4 Casual Visual River Lab           ACCEPTED
G5 + MW10 shared baseline              ACCEPTED / INTEGRATED
G6 Full Acceptance                     SOURCE_ACCEPTED
```

Final G6 Windows evidence:

```text
G6.0-G6.4 focused chain                PASS
MW10 lock release retry                PASS (12 assertions)
world regression manifest coverage     PASS
RUN_WORLD_REGRESSION_TESTS.ps1         PASS
main_scene_cli_all                      PASS (6 tests, 0 fail)
PowerShell Fix3 parser                  PASS
git status --porcelain                 EMPTY
git diff --check G5...G6               PASS
working tree                           CLEAN
```

Full world/core regression terminal marker:

```text
All world/core regression tests through NX4 client prediction and reconciliation passed.
```

Runtime-tested head was `c165f797304334d1fbde6e8178fbd143751c1e60`. Fix3 closeout was verified at `04987a5bc8ade0a4aff94671eefac3181156bc60`; post-runtime changes were limited to acceptance harness/validation/docs and did not change hydrology, Matter or world runtime semantics.

Acceptance record:

```text
docs/checkpoints/G6_FULL_ACCEPTANCE_ACCEPTED_RU.md
validation/g6-full-acceptance-validation.json
```

Architecture status remains intentionally separated:

```text
SOURCE_ACCEPTED        YES
MAIN_INTEGRATED        NO
COMPOSITION_VERIFIED   NO
PRODUCTION_READY       NO
```

Next checkpoint:

```text
G7 Semantic Field Fabric
```
