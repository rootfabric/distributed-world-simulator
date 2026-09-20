# EcologyWorkbench ExperimentComparison v1 (skeleton, P0).
# Role: compare branches/variants/seeds by pre-selected metrics; all seeds are
#   kept, no hidden winner selection; report is derived data only.
# Layer: 3 (READ-ONLY PROJECTION).
# Canonical API used (owner map rows 8,9):
#   - diversity_metrics_v1.gd: compare()  [A7]
#   - observatory_session_v1.gd: export_report()  [A7]
#   - canonical_value_v1.gd: digest() for report provenance.
class_name EcoWorkbenchExperimentComparisonV1
extends RefCounted

## Compare completed metric series of >= 2 branches. Deterministic.
static func compare(series: Array, selected_metrics: Array) -> Dictionary:
	return {}
