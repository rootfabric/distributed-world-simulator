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
G6 M4 report-race harness Fix1         IMPLEMENTED / SHARED BASELINE
G7.0 Semantic Field Contracts          FIX1 IMPLEMENTED / FULL RERUN PENDING
```

G7.0 introduces a typed semantic-field boundary while preserving the existing G0 provider execution payload:

```text
GeoFieldBundle / GeoSample             PRESERVED
GeoKernel                               UNCHANGED
existing geo/* field identities         PRESERVED
SemanticField registry                  ADDED
SemanticField typed query/sample        ADDED
```

Registry v1 contains 13 fields: three accepted upstream field identities and ten vocabulary-only fields reserved for G7.1+ providers/adapters.

P0 ownership remains explicit:

```text
SemanticFieldId != SurfaceCellKey
SemanticFieldId != LOD
SemanticFieldQuery != universal WorldQuery Fabric
G7 != Material Ontology
G7 != Authority / Interest
G7 != Persistence / Network
G7 != Scheduler / Cache owner
```

Assistant-side exact-engine evidence on byte-exact published registry/test content:

```text
Godot 4.7.1 double                    PASS
headless editor import                PASS
G7.0 contracts                        PASS — 180 assertions
parse/load errors                     0
registry blob                         9e92aa345f02856cf906e81e2fa6e1746955199b
test blob                             8dea46beea10efda51439d17737c9be8ac7811e2
```

First full Windows gate reached world/core regression and exposed one shared M4 process-test race:

```text
A/B Item Graph convergence            PASS
M4 server report assertions           FAIL — 4
root cause                             one-shot read raced AtomicJson replacement
```

Shared Fix1 is now in current G6:

```text
G6 head                               62def33a40481354820adfb6288672183887c9f1
M4 test blob                           9a17996df2545efbaaa807283b9ec70542e35128
G7 sync merge                          0c08c600c10bfedd730243e866bfa272aa14707b
assistant race smoke                   M4_REPORT_RACE_SMOKE: PASS
```

Current G6 is an ancestor of G7 and G7 is `behind_by = 0`. The G7 diff relative to current G6 remains contract-first; the M4 harness change belongs to the shared baseline.

G7.0 is not yet `ACCEPTED`: repeat the full Windows gate.

```powershell
$Godot = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"
.\RUN_G7_0_FULL_ACCEPTANCE.ps1 -GodotPath $Godot
```

The full runner checks current G6 ancestry, GLOBAL-P0 alignment, a strict G7.0 changed-file allowlist, focused contracts, world/core regression, clean worktree and `git diff --check`.

Candidate / Fix1 records:

```text
docs/checkpoints/G7_0_SEMANTIC_FIELD_CONTRACTS_CANDIDATE_RU.md
docs/procedural/G7_0_FULL_ACCEPTANCE_FIX1_RU.md
validation/g7-0-semantic-field-contracts-validation.json
validation/g7-0-full-acceptance-fix1.json
config/procedural/g7-0-semantic-field-contracts.v1.json
```

After G7.0 acceptance:

```text
G7.1 G3/G5/G6 Upstream Semantic Field Adapters
```

Longer roadmap remains:

```text
G7 Semantic Field Fabric
    -> G8 Geomorphology
    -> G9 Layered Geology / P0 Material gate
    -> G10 GeoVolume / SDF
    -> G11 Heterogeneous Body Lab
    -> G12 Scheduler / Cache / Provenance
    -> G13 Detail Contract Freeze
```
