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
→ transport listener reports SERVER_READY
→ Earth application reports earth_runtime_ready
→ dedicated-server lifecycle reports node_ready
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

## Windows exact-head execution record

Exact validation HEAD `903bd1e0753bb4fe5612a791537b2dd51bec969b` was executed on Windows with Godot `4.7.1.stable.double.custom_build.a13da4feb`.

The complete existing `RUN_V0_P1_TESTS.ps1` preflight was GREEN, including imported UID contracts and all focused P1/runtime regressions. The new live reconnect process gate then failed before actor A became ready.

Observed ordering from the same server process:

```text
~2246 ms  SERVER_READY
~9491 ms  earth_runtime_ready
~9505 ms  lifecycle node_ready / runtime_role=dedicated-server
~9532 ms  PEER_DISCONNECTED for early actor-A transport
```

### Repair Map

**Root cause:** the validation harness treated transport-level `SERVER_READY` as the complete Earth application readiness boundary. For `--world=earth`, synchronous world initialization continues for several seconds after that marker. A fast headless M3 client can therefore connect while the dedicated server is not polling the transport often enough to complete the handshake/session path.

**Files:** `tests/runtime/test_v0_p1_live_reconnect_convergence.gd` only for code; this evidence document records the failure/correction.

**Correction:** keep the `SERVER_READY` assertion, then require `earth_runtime_ready` and the dedicated-server lifecycle `node_ready`/`runtime_role=dedicated-server` markers from the same server log before spawning actor A. Do not paper over the defect with a blind sleep and do not change production runtime.

**Regression expectation:** the runner must print all server readiness assertions before `actor A launched`; the existing A/B reconnect assertions remain unchanged and fail closed on a real runtime problem.

Repair implementation commit:

```text
c33ac086ba00627a0ae4aa0369ea760baa71cffb
```

A fresh exact-head Windows real-UDP run is required after the validation branch advances.

## Runner

```powershell
.\RUN_V0_P1_RECONNECT_GATE.ps1 `
    -GodotExe C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe `
    -ExpectedHead <exact-validation-head>
```

By default the runner first executes `RUN_V0_P1_TESTS.ps1`, then the live reconnect process gate. `-SkipP1Preflight` is available only for focused iteration after the same exact checkout already passed the P1 preflight.

## Non-claims

This is not graphical UI acceptance and does not self-accept or merge P1. It closes the real network reconnect/convergence evidence gap for Item Graph/world-item/container state only when the exact-head real-UDP runner is GREEN. Independent review remains required before P1 integration.
