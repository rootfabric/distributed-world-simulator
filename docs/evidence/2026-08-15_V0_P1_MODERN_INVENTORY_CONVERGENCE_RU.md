# V0-P1 — Modern Inventory Convergence

Date: 2026-08-15
Status: DESIGN BRIEF + REPAIR MAP
Risk: MEDIUM
Candidate branch: `feature/v0-p1-world-items-containers`
Observed graphical head: `41b6aa200b8aefe5c1aaf08b42928880dd9a7720`

## Problem statement

Windows graphical verification proved that the P1 server and two clients start, but the Earth MVP still presents the legacy programmatic `m5_networked_inventory_shell.gd` UI (`ИНВЕНТАРЬ · V0`) instead of the newer component inventory screen already present in the same tree.

The product therefore currently mixes newer Item interaction behavior with an obsolete inventory composition.

## Current behavior

`earth_mvp_app.gd` directly instantiates `m5_networked_inventory_shell.gd`.

Canonical mutation remains correct:

```text
DEDICATED SERVER
  -> canonical M4 Item Graph
  -> client Item Graph snapshot
  -> M5InventoryUiBridge
  -> legacy M5 programmatic shell
```

The newer `scenes/ui/inventory/inventory_screen.tscn` exists in the same tree but is not used by the networked Earth MVP.

## Desired behavior

Keep the canonical server/M4/M5 boundary unchanged while replacing only the presentation composition:

```text
DEDICATED SERVER
  -> canonical M4 Item Graph
  -> client Item Graph snapshot
  -> M5InventoryUiBridge
  -> modern InventoryScreen scene/panels/toolbar
```

The networked runtime must keep using the existing M5 command adapter for all mutations. Search/filter/sort/profile/inspector are derived presentation state only.

## Alternatives considered

### A. Replace M5 bridge with the offline InventoryScreen controller stack
Rejected. `InventoryScreen` currently expects the local gameplay controller / `InventoryViewModel` / `InventoryCommandFacade` path. Replacing the network bridge would risk a second client-side mutation path and duplicate Item Graph truth.

### B. Rewrite the legacy shell to look similar to the modern screen
Rejected. This would create a second inventory presentation composition and continue the drift that caused the defect.

### C. Reuse the existing modern InventoryScreen scene as a presentation host while inheriting the existing M5 network shell behavior
Selected. A narrow networked-modern shell subclasses the existing M5 shell, instantiates `inventory_screen.tscn`, reuses its player/external panels and toolbar, keeps a persistent hotbar, and keeps the legacy world/mount panels hidden only as compatibility surfaces for existing acceptance helpers/reports.

A thin P1 app shim selects that shell. No M4/M5 authority or protocol change is required.

## Affected canonical owners

- Item canonical truth: unchanged, dedicated-server M4 Item Graph.
- M5 network UI bridge: unchanged owner and command path.
- Earth presentation/app composition: changed only to select the modern networked inventory presentation.
- Construction authority: unchanged; the existing MVP construction action remains a client command surface only.

## Non-goals

- no new inventory domain;
- no second Item Graph;
- no network protocol change;
- no persistence/save-format change;
- no authority change;
- no redesign of Item definitions;
- no wholesale merge of historical inventory branches;
- no claim of global/canonical V0 acceptance.

## Expected risks

1. Modern scene controls may accidentally call their offline controller path if `InventoryScreen.setup()` is invoked. Mitigation: do not invoke offline setup; the M5-derived shell owns wiring.
2. Search/filter/sort must not mutate canonical slot ordering. Mitigation: projection fields are changed only on duplicated view dictionaries; slot-container order remains canonical.
3. Hidden compatibility world/mount panels must not become product UI again. Mitigation: keep them invisible and use them only for existing acceptance/report compatibility.
4. Profile switching must remain presentation/transient-only. Mitigation: swap `InventoryInteractionProfile` on panels; mutations still submit through M5 bridge.
5. The Earth runtime route must be exact and test-covered. Mitigation: a P1 app shim and focused wiring test.

## Validation plan

1. Clean Godot import + imported UID contract.
2. New modern network inventory wiring test:
   - modern scene is instantiated;
   - legacy title is absent;
   - search/filter/sort/profile/inspector controls exist;
   - persistent hotbar remains available;
   - hidden compatibility world/mount surfaces are not visible;
   - default profile is `seven_days_like`;
   - canonical bridge remains the only network mutation boundary.
3. Existing P1 Earth wiring test updated to exact routed runtime.
4. Existing P1 world-items/containers test.
5. Existing H3 multiplayer gameplay contracts.
6. Existing V0 launcher contracts.
7. Windows exact-head server + two-client graphical check by operator.
8. Post-build critique and independent review before any merge/acceptance.

# Repair Map

## Finding R1 — obsolete inventory composition is still selected by Earth MVP

Root cause:

`earth_mvp_app.gd` hardcodes the legacy M5 shell. P1 inherited that wiring without converging it to the already-existing modern component screen.

Affected entry points:

- Earth network MVP runtime setup;
- inventory toggle;
- M5 UI render path.

Canonical fix location:

- a new P1 presentation shim selects a new modern M5 shell;
- the modern M5 shell inherits the current M5 bridge/command behavior and replaces only `_build_ui()` / derived render composition.

Why this is not a symptom patch:

The fix removes the composition mismatch at the actual wiring boundary instead of copying modern colors/layout into the old shell or bypassing M5.

Regression tests:

- exact Earth catalog route;
- modern scene/toolbar/profile/inspector wiring;
- existing canonical Item Graph and multiplayer regressions.

## Finding R2 — focused modern-inventory test ran before Control ready lifecycle

Observed exact head:

`fa653128796d767109810fb1b182368932359140`

Observed Windows result:

- `V0-P1 modern network inventory: 25 assertions, 0 failures`;
- the same log contained `SCRIPT ERROR` from `InventoryContainerPanel.set_interaction_profile()` and `InventoryHotbarPanel._apply_compact_hotbar_style()` because `@onready` children such as `grid` / labels were still `null`;
- `RUN_V0_P1_TESTS.ps1` correctly rejected the run as not parser/startup-clean.

Root cause:

`test_v0_p1_modern_network_inventory.gd` called `_run()` synchronously from `SceneTree._init()` and then invoked the shell's internal `_build_ui()` before the test-created shell and its nested Control scenes had completed a normal SceneTree ready cycle. Production Earth wiring first adds the shell to the live tree and then calls `setup()`, so the test lifecycle did not match the runtime lifecycle.

Files:

- `tests/runtime/test_v0_p1_modern_network_inventory.gd` only.

Exact correction:

- defer the focused test body out of `SceneTree._init()`;
- wait one process frame after adding the shell before invoking the isolated UI build;
- assert that the shell is inside the tree and node-ready before building the modern composition;
- keep `RUN_V0_P1_TESTS.ps1` fatal `SCRIPT ERROR` scanning unchanged.

Why production is not changed for R2:

The reproduced stack is caused by the test's premature direct call of internal `_build_ui()`. There is no evidence in this failure that the real `earth_p1_modern_inventory_app.gd -> add_child(shell) -> shell.setup()` path performs the same premature call. Changing production to mask a test-only lifecycle violation would weaken the boundary instead of repairing the harness.

Regression expectation:

The exact-head Windows preflight must report all focused assertions and contain zero `SCRIPT ERROR:` lines; only then may the graphical server + two-client smoke test begin.

## Required acceptance state

Implementation may be proposed only as a candidate. `IMPLEMENTER CANNOT SELF-ACCEPT`; Windows graphical evidence and independent review remain required before product-frontier merge.