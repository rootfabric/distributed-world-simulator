# V0 PLAYABLE RECOVERED LOCAL BASELINE — 2026-08-15

Status: USER-VALIDATED LOCAL PLAYABLE RECOVERY POINT

This document records a durable branch-local execution fact. It does NOT declare
GLOBAL V0 checkpoint acceptance and does NOT replace independent reviewer / verifier
requirements from PROJECT_CONTROL.md.

## Durable source anchor

Immutable recovery checkpoint branch:

```text
checkpoint/v0-playable-recovered-2026-08-15
```

Exact recovery recipe/source SHA:

```text
70e68be743922d464db1e8bf51215802362a32f0
```

Development continuation branch:

```text
feature/v0-playable-product-frontier
```

No future V0 product work should restart from the historical stale line
`feature/v0-s1-networked-planetary-outpost-mvp` or from an arbitrary `agent/v0-*`
branch merely because its name looks newer.

## Human runtime fact

On Windows with Godot 4.7.1 double precision build
`4.7.1.stable.double.custom_build.a13da4feb`, the recovered composition was launched
as a dedicated server plus two graphical Earth clients and the user confirmed that
this recovered version is the correct playable version after removal of the obsolete
V0-NET-001 reliable MOVE fallback.

The corrected movement composition is:

```text
V0-I1 inventory convergence
+ gameplay mouse-capture fix
+ V0-S0 stabilized surface camera / input ownership / ordered ENet
+ NX4 client prediction + reconciliation movement
+ V0-I2/C1 inventory interaction + Construction controls
+ C2A Earth-fixed Construction presentation
```

The obsolete historical movement workaround is explicitly NOT part of this baseline:

```text
V0-NET-001 reliable MOVE fallback at ~20 Hz
```

It caused visible movement stepping and a camera-yaw / movement-basis mismatch when
combined with the later S0 surface camera.

## Required product markers

A future descendant intended to preserve this baseline must retain all of these
properties:

```text
F1 debug HUD is hidden by default and toggles cleanly
Tab opens/closes the M5 network inventory
inventory owns mouse while open; gameplay owns mouse while closed
NX4 advance_local_prediction path is active for local movement
look_yaw is sourced from EarthExplorer surface-relative camera yaw
ordered ENet realtime mapping is present
no false connect-timeout after a real disconnect
A/B graphical clients use server-authoritative state with local prediction/reconciliation
Construction build controls remain exposed through inventory
Construction remains server-authoritative
C2A Earth-fixed anchor / derived render transform remains presentation-only
procedural Earth surface presentation remains enabled
```

Forbidden regression marker:

```text
V0-NET-001 reliable camera-relative movement fallback
```

If a descendant reintroduces that fallback, it is NOT equivalent to this playable
baseline even if server + clients still start.

## Recovery / launch entry point

From a clean checkout compatible with this anchor:

```powershell
.\RUN_V0_RECOVERED_PLAYABLE.ps1 `
  -GodotExe "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"
```

The recovery flow is fail-closed and must preserve NX4 movement rather than install
the obsolete reliable movement workaround.

## Continuation rule

Use this split deliberately:

```text
checkpoint/v0-playable-recovered-2026-08-15
    = recovery anchor; do not develop here

feature/v0-playable-product-frontier
    = sole V0 product continuation line until superseded by a later explicitly
      declared convergence frontier
```

Any new branch for V0 gameplay should record this frontier's exact integration-base
SHA and must not silently substitute an older V0 branch.

## Immediate next product gates

Recommended sequence from this baseline:

1. Materialize the recovered composition as normal committed production source so
   ordinary launch no longer depends on applying historical delivery patches.
2. Add focused regression coverage for camera-relative NX4 movement, F1 HUD, Tab
   inventory, Construction controls, and C2A fixed-anchor presentation.
3. Prove TWO_PLAYER_PLAYABLE_BUILD repeatedly from clean checkouts.
4. Complete NETWORKED_CONSTRUCTION_VERTICAL_SLICE from both clients.
5. Add RECONNECTABLE_SHARED_WORLD behavior and verify reconstructed shared state.
6. Run five clean E2E repeats.
7. Run the declared 30-minute two-client soak.
8. Produce fresh evidence for independent review. Only main/control may later declare
   checkpoint acceptance.
