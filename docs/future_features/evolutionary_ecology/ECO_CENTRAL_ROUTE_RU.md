# ECO — Центральный маршрут развития ветки

Статус: `ACTIVE / RESEARCH_ONLY / EVO1 P2.4 IMPLEMENTED CANDIDATE / EXACT WINDOWS GATE`.

Canonical North Star: `docs/future_features/evolutionary_ecology/ECO_EVOLUTIONARY_ECOSYSTEM_VISION_RU.md`.
Machine roadmap: `config/ecology/eco-evolutionary-ecology-roadmap.v1.json`.

## Accepted foundation

```text
ECO.P1                    ACCEPTED
ECO.PH0..PH5-S4           ACCEPTED
ECO.CONV0-A               ACCEPTED
ECO.CAL1-A..F             ACCEPTED
CAL1-F                    ROBUST_UNITY_CALIBRATION
ECO.EVO1 / P2.1           ACCEPTED
ECO.EVO1 / P2.2           ACCEPTED
ECO.EVO1 / P2.3           ACCEPTED
```

Canonical hashes:

```text
CAL1-F  f531fe844ceaa77094f6d259601f0df2f4b8b421328a221a1bab14196ccad1ed
P2.1    cf620f1d7896502a29a67d52f3700a570a4c585ff21a002b750e9440aee717e6
P2.2    633c797526347aa65470ad3d20490f4fe042efa9d20d5e0e68c1ff4c01182f86
P2.3    15752b545460541f5e4257c94fa5b75973274cfecc707106c24f574269f7df3e
```

P2.3 exact Windows succession evidence includes `shade_delta=0.595328177712`, `banked_gain=0.765095488003`, seed-bank reactivation `48`, reproduction events `15`, and exact fresh-process replay.

## Central route

```text
EVO0 / CAL1 COMPLETE
   ↓
P2.1 Seed Dispersal Kernel ACCEPTED
   ↓
P2.2 Establishment / Recruitment / Seed Bank ACCEPTED
   ↓
P2.3 Local Population Turnover + Succession ACCEPTED
   ↓
P2.4 Patch Colonization / Isolation / Migration ← CURRENT CANDIDATE
   ↓ PASS
P2.5 Disturbance + Recovery
   ↓
P2.6 Long-Horizon Biogeography
   ↓
P2.7 Lineage Divergence / Speciation Candidate Diagnostics
   ↓
P2.8 Deterministic Save/Restart Plant World Proof
```

EVO1 final acceptance remains:

`NO_BIOME_SPECIES_TABLES_AND_MULTIPLE_CAUSALLY_EXPLAINABLE_PERSISTENT_COMMUNITIES`.

## P2.4 implementation

Implementation head: `01042d585fa46aebe5fde090e217c9fcb58be68f`.

Diff from accepted P2.3 adds exactly five ECO research/test files and modifies no accepted P2.3/P2.2/P2.1/CAL1 source or runtime path.

### Spatial migration semantics

P2.4 takes the real `destination_position` produced by P2.1. A seed packet that leaves the source patch is routed only if that coordinate intersects a known target patch rectangle. Otherwise it remains unresolved external export.

```text
emitted
 = source-retained
 + routed to known target
 + unresolved export
```

Arrival is then passed to the accepted P2.2 establishment/seed-bank kernel, preserving lineage/genome/reproduction event and packet provenance.

### Isolation experiment

Two otherwise matched causal lineages differ only by inherited seed dispersal distance:

```text
SHORT = 5 m
LONG  = 20 m
```

Both emit eight 160-seed events from the same source into the same favourable environment and eastward transport.

Targets:

```text
NEAR Rect2(11,-20,24,40)
FAR  Rect2(50,-40,80,80)
```

Acceptance requires NEAR to recruit both SHORT and LONG, FAR to recruit LONG but not SHORT, NEAR total recruitment to exceed FAR, and LONG share to increase with isolation. A westward LONG control must route zero seeds into the east-side targets.

Thus connectivity and community filtering emerge from inherited dispersal + real transport geometry, not a migration table.

### Ownership boundary

Research patch `Rect2` records are experiment inputs only. P2.4 does not claim canonical Spatial Domain Fabric, terrain/world-query, network authority or persistence ownership. Production transfer still waits for XFER/global foundations.

### Strict P2.5 boundary

No explicit disturbance event scheduler or disturbance recovery chronology is introduced here. P2.5 owns those semantics.

## Exact Windows gate

```powershell
cd C:\Godot\lunar-world-eco-evolutionary-ecology

git pull

$Godot = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"

.\RUN_ECO_EVO1_P2_4_TESTS.ps1 -GodotPath $Godot
```

The runner first performs a parser/preload `--check-only` preflight, then the accepted P2.3 parent regression, P2.4 acceptance and two fresh-process replay probes.

Until PASS:

```text
P2.4 = IMPLEMENTED_CANDIDATE
P2.4 != ACCEPTED
P2.5 = BLOCKED
```

Current resolver: `RUN EVO1/P2.4 EXACT WINDOWS PATCH COLONIZATION / ISOLATION / MIGRATION GATE`.
