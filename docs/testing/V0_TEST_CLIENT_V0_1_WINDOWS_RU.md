# V0 Test Client V0.1 — Windows verification

**Status:** REQUIRED LOCAL VERIFICATION  
**Godot:** `4.7.1.stable.double.custom_build.a13da4feb`

## 1. Preconditions

Use a clean Windows checkout of `rootfabric/distributed-world-simulator` on the test-client branch/PR head.

Required:

- Windows x86_64 Godot 4.7.1 double build matching `a13da4feb`;
- PowerShell 5+ or PowerShell 7;
- Git available in PATH;
- normal desktop session (not headless);
- no firewall rule blocking localhost UDP/ENET.

Verify Godot first:

```powershell
& "C:\path\to\godot.double.exe" --version
```

Expected exact first line:

```text
4.7.1.stable.double.custom_build.a13da4feb
```

## 2. Recommended full observable run

From repository root:

```powershell
.\RUN_V0_PLAYABLE_SEAMLESS_CLIENTS.ps1 -GodotPath "C:\path\to\godot.double.exe" -Scenario All -Observe -StepMs 1000
```

The runner first executes the headless contract compile gate, then launches the visual scenarios.

## 3. Seam scenario

Run only:

```powershell
.\RUN_V0_PLAYABLE_SEAMLESS_CLIENTS.ps1 -GodotPath "C:\path\to\godot.double.exe" -Scenario Seam -Observe -StepMs 1200
```

Expected visible result:

- two windows: `DWS Test Client A — Seam` and `DWS Test Client B — Seam`;
- HUD shows Gateway, player/entity IDs, Authority, epoch, world revision and position;
- route changes `authority/a → authority/b → authority/a`;
- reconnects remains 0;
- respawns remains 0;
- parent PowerShell ends with `PASS: SEAM...`.

Artifacts:

```text
artifacts/test-results/v0-test-client-seam-*/
```

## 4. Items scenario

Run only:

```powershell
.\RUN_V0_PLAYABLE_SEAMLESS_CLIENTS.ps1 -GodotPath "C:\path\to\godot.double.exe" -Scenario Items -Observe -StepMs 1000
```

Expected visible result:

- two windows: `DWS Test Client A — Items` and `DWS Test Client B — Items`;
- Client A performs canonical commands one by one:
  - pickup beacon;
  - select hotbar;
  - mount;
  - detach;
  - open shared crate;
  - move beacon to crate;
  - close crate;
- Client B remains an independent replica observer;
- both windows end on the same non-empty Item Graph checksum;
- the beacon final location is the shared crate;
- PowerShell ends with `PASS: ITEMS...`.

Artifacts:

```text
artifacts/test-results/v0-test-client-items-*/
```

## 5. Fast non-observe smoke

For a quicker machine check:

```powershell
.\RUN_V0_PLAYABLE_SEAMLESS_CLIENTS.ps1 -GodotPath "C:\path\to\godot.double.exe" -Scenario All -StepMs 150
```

## 6. Acceptance evidence to return

Record:

```text
git rev-parse HEAD
git status --short
Godot --version
PowerShell runner exit code
SEAM PASS/FAIL
ITEMS PASS/FAIL
artifact directories
client-a/client-b JSON reports
```

For a clean acceptance run:

```text
contracts = PASS
seam = PASS
items = PASS
git worktree = clean except ignored test artifacts
```

## 7. Scope boundary

V0.1 intentionally does NOT prove:

```text
planet surface
+
seam
+
Item Graph
+
cross-authority item carry
```

in one live topology.

Current status remains:

```text
SEAM graphical topology        PROVEN BY V0.1 seam gate
ITEMS graphical topology       PROVEN BY V0.1 items gate
single seam+items topology      NOT_YET_PROVEN
planetary client surface        WAIT P7.2 / C1
```

The V0.1 client is the diagnostic shell that will be extended at C1/P7.2 and later V3/V4.
