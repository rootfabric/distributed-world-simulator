# EcologyWorkbench ExperimentMetrics v1 (skeleton, P0).
# Role: collect metrics from COMPLETED immutable snapshots only (never from
#   in-flight state): population, births/deaths, resource balances, mutation
#   events, morphology/genotype diversity, lineage.
# Layer: 3 (READ-ONLY PROJECTION).
# Canonical API used (owner map rows 6,7,8):
#   - observatory_session_v1.gd: observe()  [A7]
#   - phenotype_snapshot_v1.gd: compile(state, genome)  [A1]
#   - diversity_metrics_v1.gd: compare(a, b, pa, pb)  [A7]
#   - persistent_environmental_feedback_v1.gd: balance(state)  [A6]
#   - body_graph_v1.gd: topology_signature(modules)  [A1/A2]
# Forbidden: metrics must not feed back into simulation state.
class_name EcoWorkbenchExperimentMetricsV1
extends RefCounted

## Compute one metrics frame from a completed observation.
static func frame(observation: Dictionary) -> Dictionary:
	return {}
