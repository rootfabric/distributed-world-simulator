# ECO.PH5-S1 — PlantRenderDescription + RendererProfile Foundation — ACCEPTED

Статус: `ACCEPTED / RESEARCH_ONLY`.

Принят derived rendering pipeline:

`GrowthGraph -> PlantRenderDescription -> RendererProfile -> representation/LOD materialization`.

## Exact Windows evidence

Godot: `4.7.1.stable.double.custom_build.a13da4feb`.

Checkout: `5d339b3628298e7f84ff563b6bdaf0bcb3aa2c7b`.

- PH4 parent lifecycle: `PASS (718 assertions)` + restart `5`;
- PH5 focused acceptance: `PASS (720 assertions)`;
- PH5 visual lab smoke: `PASS (15 assertions)`;
- PH5 fresh-process replay: `PASS (4 assertions)`.

Exact PH5 hashes:

- `reference_description_hash = 72196b2711322160e95dca32c0e4729dcf009f7c817a1448e53bd7de02ce97a3`;
- `profile_matrix_hash = 2121aaf7f0e725bcf9a8216784ad835bb488c0e6b5a3a1e24604220779c302e0`;
- `full_materialization_hash = 374eade14f40d3d42491ca24dfaae69adc511dea47e76bc629a5d3abf5a2028c`.

Focused and fresh-process hashes are identical.

## Graphical evidence

`PASS_BY_USER_OBSERVATION`.

User confirmed renderer-profile switching works without errors. `BRANCH_LEAF_INSTANCED`, `CANOPY_APPROXIMATION` and `IMPOSTOR_BILLBOARD` visibly produce different representations for the same selected environment while retaining the same source `growth_graph_hash`.

## Accepted invariants

- renderer/profile/LOD is presentation only;
- renderer changes cannot mutate GrowthGraph, genome, phenotype, resource, selection or lifecycle truth;
- all six profiles consume one deterministic `PlantRenderDescription`;
- `TREE/BUSH/GRASS` are not canonical ecology or renderer identity classes;
- S1 does not claim production-quality 3D mesh, GPU foliage, canopy clustering or impostor baking.

## Next

Open `ECO.PH5-S2 — 3D Tapered Branch Tubes + Instanced Foliage`.

S2 may improve geometric and asset fidelity only downstream of `PlantRenderDescription`; the source GrowthGraph hash remains immutable.
