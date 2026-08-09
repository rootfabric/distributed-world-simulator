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
G7.0 Semantic Field Contracts          FIX1 WINDOWS FOCUSED PASS / FULL RERUN PENDING
```

G7.0 introduces a typed semantic-field boundary while preserving the existing G0 provider execution payload:

```text
GeoFieldBundle / GeoSample             PRESERVED
GeoKernel                               UNCHANGED
existing geo/* field identities        PRESERVED
SemanticField registry                 ADDED
SemanticField typed query/sample       ADDED
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

First Windows full gate reached legacy M4 graphical shared gameplay and exposed a shared report-read race. Shared G6 Fix1 was synchronized into G7. Windows focused verification on tested head `31316df5dc1068888a1e411d14c8af733a68ebc1` then passed:

```text
M4 graphical shared gameplay          PASS — 22 assertions / 0 failures
server canonical graph                PASS
shared container replication          PASS
server/client Item Graph convergence  PASS
client shutdown                       PASS A / PASS B
post-cleanup git status               EMPTY
```

G7.0 is not yet `ACCEPTED`: only the repeated full Windows checkout gate remains.

Full Windows command:

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
