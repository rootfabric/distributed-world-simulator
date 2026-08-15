# V0-P1 — live reconnect / absent-peer convergence gate

**Scope:** validation/tooling only. No production runtime or gameplay semantics are changed.

## Base runtime candidate

The gate is designed against the frozen P1 implementation candidate:

```text
feature/v0-p1-world-items-containers
e754d2258451e605d25932c5dc00207f736a3348
```

The implementation candidate remains the runtime-under-test. This validation slice adds a durable real-network process gate instead of crediting reconnect from focused in-process tests.

## Scenario

```text
dedicated server
→ A joins and remains live
→ B joins and captures session/entity/epoch
→ B sends canonical LEAVE and exits
→ A replica observes B.connected=false
→ only then A moves while B is absent
→ A picks up item/shared/beacon/1
→ A opens container/shared/crate/1
→ A transfers the beacon into canonical crate slot 0
→ A captures the confirmed Item Graph checksum
→ B reconnects with the same logical player id
→ B must receive a new transport session
→ B must preserve canonical player entity identity
→ B ownership epoch must advance
→ B Item Graph checksum must equal A current checksum
→ B must reconstruct beacon removal from WORLD and crate slot/container membership
→ B must observe A current authoritative transform
→ A must remain live and observe B return
→ both clients leave cleanly
```

## Trust boundary

The test uses the existing production `m3_graphical_client_runtime.gd` and the normal `--network-mvp` dedicated-server composition over real loopback UDP. It does not mutate Item Graph state locally and does not inject canonical snapshots.

The result is accepted only when:

- every process exits as expected;
- the reconnect script reports zero failures;
- the exact post-mutation Item Graph checksum is observed by reconnected B;
- session identity changes while canonical player entity identity is preserved;
- ownership epoch advances;
- A proves B was absent before the mutation and proves B returned afterward;
- tracked checkout state remains clean;
- logs contain no parser/script/runtime failure markers.

## Runner

```powershell
.\RUN_V0_P1_RECONNECT_GATE.ps1 `
    -GodotExe C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe `
    -ExpectedHead <exact-validation-head>
```

By default the runner first executes `RUN_V0_P1_TESTS.ps1`, then the live reconnect process gate. `-SkipP1Preflight` is available only for focused iteration after the same exact checkout already passed the P1 preflight.

## Non-claims

This is not graphical UI acceptance and does not self-accept or merge P1. It closes the real network reconnect/convergence evidence gap for Item Graph/world-item/container state. Independent review remains required before P1 integration.
