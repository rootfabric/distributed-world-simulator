# V0 — H0.3 role and staged-gate correction

**Status:** authoritative correction for the V0 design lane until the parent roadmap is consolidated at a safe control synchronization.

## H0.3 boundary

Any older V0 diagram/text that shows:

```text
ScenarioSpec → H0.3 scheduler/orchestrator → game runtime workers
```

is superseded.

H0.3 is the **DEVELOPMENT multi-worker Work-Order scheduler/control layer**. It schedules development agents and Work Orders. It does not start game server/client/world/item processes and does not participate in runtime boot.

V0-S0 uses the existing production runtime lifecycle, currently rooted through:

```text
project.godot
→ main.tscn
→ scripts/app/simulator_app.gd
→ existing runtime lifecycle
```

## No adapter waterfall

After H0.3 acceptance:

```text
H0.3
  ├→ V0.0 capability/owner freeze → V0-S0 boot
  ├→ GEO-min + usable player + Construction/C22 → V0-S1
  ├→ ITEM-min → V0-S2
  └→ NX MAIN_INTEGRATED → NET-min → V0-S3
```

V0.0 freezes per-scenario capability gates; it does not require all later capabilities to already be integrated.

## MAT / CH corrections

`MAT0` is not a mandatory V0-S1 gate unless the selected S1 scenario requires canonical material semantics.

CH9 equipment is not a universal V0-S2 gate. Base S2 may prove canonical container/pickup/transfer/drop roundtrip; equip/unequip is included when the accepted/integrated CH equipment capability is available and required.

## Network gate

`NX SOURCE_ACCEPTED` alone does not authorize V0-S3. Required path:

```text
NX SOURCE_ACCEPTED
→ explicit NX integration/merge gate
→ post-NX PC0
→ NX MAIN_INTEGRATED
→ NET-min
→ V0-S3
```

## Risk/control rule

V0/H0.3 reuse canonical Harness risk classes and policies. No parallel risk taxonomy or V0-owned scheduler/control truth may be introduced.
