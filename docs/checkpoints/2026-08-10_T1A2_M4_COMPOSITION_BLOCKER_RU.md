# T1A.2 composition blocker — M4 final server report read race

Date: 2026-08-10
Branch: `feature/t1a2-d0-authoritative-outpost-builder`
T1A.2 focused head: `c1010d85f7a3c947f125bd6f509ba5b8b45492b2`
M4 harness fix head: `32fe310089ac2ed836c6c3b298f9d6e1d0b0462f`

## Observed full regression failure

The first full `RUN_WORLD_REGRESSION_TESTS.ps1` attempt after T1A.2 focused acceptance stopped at `test_m4_graphical_shared_gameplay_processes` before reaching T1A.2.

Observed M4 result:

```text
A graphical                              PASS
B graphical                              PASS
A pickup succeeded                       PASS
B deterministic contention rejection     PASS
foreign inventory write rejected         PASS
server canonical graph has one beacon    FAIL
beacon replicated in shared container    FAIL
server item graph checksum                FAIL
A received item graph replica             PASS
B received item graph replica             PASS
A and B item graph checksum convergence  PASS
server/client checksum convergence        FAIL
A clean shutdown                          PASS
B clean shutdown                          PASS
M4 graphical shared gameplay: 22 assertions, 4 failures
```

The four failures are all derived from the single final `server.json` read. Both graphical clients already held the same valid canonical Item Graph checksum.

## Root cause

`m3_dedicated_server_runtime.gd` publishes `server.json` through `m3_process_support.gd`, which uses `AtomicJson.write_dictionary()`.

The server republishes the report while handling graceful `LEAVE` and `PEER_DISCONNECTED`. The M4 process test waited for both client processes to exit and then performed exactly one ordinary `FileAccess` read of `server.json`.

On Windows, an atomic replace may expose a short path gap. The one-shot read can therefore return `{}` while the authoritative service remains healthy and both clients have already converged. This is a process-harness observation race, not a canonical Item Graph mutation failure.

## Fix

M4 now derives the expected checksum from the two COMPLETE client reports and polls `server.json` for up to 10 seconds until the authoritative `item_graph_snapshot.checksum` equals that checksum.

The server, gameplay service, Item Graph semantics, network protocol and T1A.2 implementation are unchanged.

Net M4 patch versus the previously validated T1A.2 head is intentionally small:

```text
+10 lines
-1 line
```

The helper syntax was parse-checked with exact engine:

```text
Godot 4.7.1.stable.double.custom_build.a13da4feb
```

## Acceptance state

T1A.2 focused gate remains PASS:

```text
T1A.0  PASS 58
T1A.1  PASS 67
C1     PASS 40
C2B    PASS 64
T1A.2  PASS 186
```

T1A.2 remains:

```text
SOURCE_ACCEPTED       false
MAIN_INTEGRATED       false
COMPOSITION_VERIFIED  false
PRODUCTION_READY      false
```

Required next gate:

1. focused `test_m4_graphical_shared_gameplay_processes.gd` on Windows;
2. if PASS, full `RUN_WORLD_REGRESSION_TESTS.ps1`.
