# EcologyWorkbench MorphologyDescriptor v1 (skeleton, P0).
# Role: DERIVED read-only view over canonical BodyGraph for presentation:
#   segment/tube/capsule/junction/membrane primitives + symmetry/repeat
#   features. NOT a second morphology truth; never written back to
#   Genome/DevelopmentProgram/BodyGraph.
# Layer: 3 (READ-ONLY PROJECTION).
# Canonical API used (owner map rows 3,8,10):
#   - body_graph_v1.gd: validate(), topology_signature(modules)  [A1/A2]
#   - phenotype_snapshot_v1.gd: compile(state, genome)  [A1]
#   - diversity_metrics_v1.gd FEATURES (height_mm, branching_nodes, ...)  [A7]
# Reusable adapter note (owner map §3.2): phenotype -> render description needs
#   a reusable adapter; do not copy plant_render_description formulas.
class_name EcoWorkbenchMorphologyDescriptorV1
extends RefCounted

const SCHEMA := "dws.ecology.workbench.morphology-descriptor.v1"

## Build descriptor from canonical body modules. Pure function.
static func compile(body_modules: Array) -> Dictionary:
	return {}
