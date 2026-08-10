# G7 Semantic Field Fabric — Full Acceptance Candidate

**Architecture:** `GLOBAL-P0-2026-08-10-R2`
**Project Control:** `PC0-2026-08-10-R1`
**Branch:** `feature/g7-semantic-field-fabric`

## Accepted sub-stages

```text
G7.0 Semantic Field Contracts                 ACCEPTED
G7.1 Upstream Semantic Field Adapters         ACCEPTED
G7.2 Composition / Provenance                 ACCEPTED
G7.3 Cross-Cell / Cross-LOD Invariance        ACCEPTED
G7.4 Semantic Field Lab                       ACCEPTED
```

G7.4 final automated acceptance tested head:

```text
ddacaf18a5c4b57c708562538a71065240d73ddb
```

Final graphical observation also passed. Abrupt LOD switching remains non-blocking presentation tuning debt and does not affect canonical semantic identity.

## G7 Full Acceptance gate

The aggregate runner verifies:

- main-owned PC0 declares `G7 Full Acceptance`;
- branch passport and PC0 stage agree;
- all G7.0..G7.4 validation records are `ACCEPTED`;
- G7.4 manifest and manual graphical acceptance are accepted;
- the entire G6..G7 diff stays inside the Semantic Field Fabric / control / documented shared-fix boundary;
- canonical GLOBAL roadmap is byte-identical to main before its inherited Markdown hard-break whitespace is excluded from `git diff --check`;
- Project Control reports G health not RED;
- aggregate G7 focused semantic tests pass;
- one fresh world/core regression passes through NX4;
- final working tree remains clean.

Run on Windows:

```powershell
cd C:\Godot\lunar-world-g6-fluid

git fetch origin --prune
git reset --hard origin/feature/g7-semantic-field-fabric

$Godot = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"

.\RUN_G7_FULL_ACCEPTANCE.ps1 `
    -GodotPath $Godot
```

Expected final marker:

```text
G7 FULL ACCEPTANCE: PASS
G7.0 ACCEPTED: PASS
G7.1 ACCEPTED: PASS
G7.2 ACCEPTED: PASS
G7.3 ACCEPTED: PASS
G7.4 ACCEPTED: PASS
Semantic identity / provenance / cross-cell / presentation separation: PASS
World/core regression: PASS
Working tree: CLEAN
NEXT: G8 GEOMORPHOLOGY
```

## Gate after PASS

A green run allows G7 to be marked fully accepted and PC0 to advance the World Generation frontier to `G8 — Geomorphology`.

G8 owns procedural geomorphology such as valley incision, river-channel incision, banks, floodplain shaping, and procedural erosion/deposition baseline. It does not own player excavation, persistent terrain damage, Matter transactions, global world addressing, authority or persistence foundations.
