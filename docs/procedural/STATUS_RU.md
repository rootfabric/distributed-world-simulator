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
G6 Full Acceptance                     FIX3 IMPLEMENTED CANDIDATE
```

Current G6 full-acceptance evidence:

```text
G6.0-G6.4 focused chain                PASS
MW10 lock release retry                PASS (12 assertions)
world regression manifest coverage     PASS
RUN_WORLD_REGRESSION_TESTS.ps1         PASS
main_scene_cli_all                      PASS (6 tests, 0 fail)
world regression terminal marker       PASS
final hygiene                          FAIL — transient Microsoft/ only
```

The full Windows world/core regression completed successfully and printed:

```text
All world/core regression tests through NX4 client prediction and reconciliation passed.
```

The only remaining blocker was an untracked root `Microsoft/` directory created by Windows child-process profile handling after the regression had already passed.

Fix3 is acceptance-harness-only. `RUN_G6_FULL_ACCEPTANCE.ps1` now snapshots whether `Microsoft/` existed before the run and removes it after child processes only when all of the following are true:

```text
directory did not exist before the run
path is Microsoft/ at repository root
Git reports no tracked files under Microsoft/
```

Pre-existing or tracked content is never deleted. No hydrology, Matter, world runtime, or test semantics changed.

Because the full world regression is already green and the only post-tested changes are the cleanup logic plus validation/status records, the closeout does not require another full world regression. Required closeout is PowerShell parse + clean tree + `git diff --check` on the updated head.

After that:

```text
G6 Full Acceptance -> SOURCE_ACCEPTED
next -> G7 Semantic Field Fabric
```
