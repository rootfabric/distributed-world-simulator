# Universal World Generation Fabric — status ledger

**Current branch:** `feature/g7-semantic-field-fabric`
**Global revision:** `GLOBAL-P0-2026-08-08-R1`

```text
G6.0 Fluid Contracts                   ACCEPTED
G6.1 CasualRiverProviderV1             ACCEPTED
G6.2 Cross-Cell / Cross-LOD Continuity ACCEPTED
G6.3 Runtime WaterSurfaceQuery         ACCEPTED
G6.4 Casual Visual River Lab           ACCEPTED
G5 + MW10 shared baseline              ACCEPTED / INTEGRATED
G6 Full Acceptance                     SOURCE_ACCEPTED
G6 P0 Alignment Cleanup                ACCEPTED
G7.0 Semantic Field Contracts          ACCEPTED
G7.1 Upstream Semantic Field Adapters  ACCEPTED
G7.2 Composition / Provenance           IMPLEMENTED CANDIDATE
```

## G7.1 acceptance

Full Windows acceptance passed on tested head:

```text
61de8526448a5a2ab95745fa380cdc8b3c4ea24f
```

Engine:

```text
Godot 4.7.1.stable.double.custom_build.a13da4feb
```

Confirmed:

```text
G7.1 focused adapters                  PASS
G3/G5/G6 semantic adapters             PASS
RL3 representation streaming processes PASS — 37 assertions
main_scene_cli_all                      PASS — 6 / 6
world/core regression                  PASS
G7.1 adapter scope                     PASS
working tree                           CLEAN
G7.1 FULL ACCEPTANCE                   PASS
```

Accepted G7.1 checkpoint:

```text
af0898ba2f0fc03dbd0298440f302b497a5d0cad
```

## G7.2 candidate

G7.2 adds synchronous deterministic composition only:

```text
partial adapter results
        │
        ▼
SemanticFieldComposerV1
        │
        ├─ SemanticFieldBundle
        └─ SemanticFieldCompositionReceipt
```

Strict policy:

```text
semantic-composition-policy/require-complete-v1

missing requested field       REJECT
duplicate field ownership     REJECT
duplicate adapter             REJECT
unrequested contributed field REJECT
input ordering                 NORMALIZED BY ADAPTER_ID
```

The composer preserves adapter-produced samples byte-for-byte and does not rewrite their provenance. The receipt pins query, bundle, sample and upstream provenance checksums.

Focused integration paths use real accepted G7.1 adapters:

```text
G3 + G5 -> surface-height + valley-influence bundle
G3 + G6 -> surface-height + river/fluid semantic bundle
```

P0 boundaries remain:

```text
composer != WorldQuery
composer != scheduler/cache
composer != authority/interest
composer != persistence/network
composer != material ontology
composer != geomorphology
receipt != world identity
```

Validation:

```powershell
$Godot = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"
.\RUN_G7_2_COMPOSITION_PROVENANCE_TESTS.ps1 -GodotPath $Godot
.\RUN_G7_2_FULL_ACCEPTANCE.ps1 -GodotPath $Godot
```

G7.2 remains unaccepted until the full Windows gate passes.

Next if accepted:

```text
G7.3 Cross-Cell / Cross-LOD Invariance
```
