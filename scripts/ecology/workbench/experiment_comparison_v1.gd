# EcologyWorkbench ExperimentComparison v1 (P10, ECO ARCH2 A10.5 / ECO-POLYGON-1).
# Role: compare two COMPLETED experiment results (P11 batch input) by
#   manifest_hash, seed, final canonical state hash, metric series diff
#   summary and event counts. All seeds are KEPT (no hidden winner
#   selection); the report is derived data only.
# Layer: 3 (READ-ONLY PROJECTION). Pure static function.
class_name EcoWorkbenchExperimentComparisonV1
extends RefCounted

const SCHEMA := "dws.ecology.workbench.experiment-comparison.v1"

const COMPARE_METRICS := [
	"tick", "generation", "population", "alive", "lineage_depth_max",
	"morphology_unique_signatures", "morphology_shannon_permille",
	"body_modules_total", "mineralized_mg",
	"births_total", "deaths_total", "mutation_events_total",
]

## Compare two completed experiment results. Each result is
## {"experiment_id", "manifest_hash", "seed", "final_state_hash",
##  "metrics": ExperimentMetricsV1.summary() (or a compatible summary)}.
## selected_metrics: optional subset of COMPARE_METRICS (default: all).
## Deterministic: compare(a, b) and compare(b, a) carry the same facts
## (each side's values are reported separately; nothing is dropped).
static func compare(result_a: Dictionary, result_b: Dictionary, selected_metrics: Array = []) -> Dictionary:
	var metrics := COMPARE_METRICS.duplicate()
	if not selected_metrics.is_empty():
		var filtered: Array = []
		for metric in selected_metrics:
			if COMPARE_METRICS.has(metric):
				filtered.append(metric)
		if not filtered.is_empty():
			metrics = filtered
	var final_a := _final_of(result_a)
	var final_b := _final_of(result_b)
	var metric_diffs := {}
	for metric in metrics:
		var has_a := final_a.has(metric)
		var has_b := final_b.has(metric)
		if not has_a and not has_b:
			continue
		var value_a: int = int(final_a.get(metric, 0)) if has_a else 0
		var value_b: int = int(final_b.get(metric, 0)) if has_b else 0
		metric_diffs[String(metric)] = {
			"a": value_a if has_a else null,
			"b": value_b if has_b else null,
			"delta": value_b - value_a,
			"equal": (not has_a and not has_b) or (has_a and has_b and value_a == value_b),
		}
	return {
		"schema": SCHEMA,
		"experiment_ids": [String(result_a.get("experiment_id", "")), String(result_b.get("experiment_id", ""))],
		"manifest_hash": {
			"a": String(result_a.get("manifest_hash", "")),
			"b": String(result_b.get("manifest_hash", "")),
			"equal": String(result_a.get("manifest_hash", "")) == String(result_b.get("manifest_hash", "")),
		},
		"seed": {
			"a": int(result_a.get("seed", -1)),
			"b": int(result_b.get("seed", -1)),
			"equal": int(result_a.get("seed", -1)) == int(result_b.get("seed", -1)),
		},
		"final_state_hash": {
			"a": String(result_a.get("final_state_hash", "")),
			"b": String(result_b.get("final_state_hash", "")),
			"equal": String(result_a.get("final_state_hash", "")) == String(result_b.get("final_state_hash", "")),
		},
		"metric_diffs": metric_diffs,
		"event_counts": {
			"a": _event_counts_of(result_a).duplicate(),
			"b": _event_counts_of(result_b).duplicate(),
		},
		"metrics_compared": metrics,
	}

static func _final_of(result: Dictionary) -> Dictionary:
	var metrics: Dictionary = result.get("metrics", {})
	if metrics is Dictionary and metrics.has("final"):
		return metrics.get("final", {})
	return {}

static func _event_counts_of(result: Dictionary) -> Dictionary:
	var metrics: Dictionary = result.get("metrics", {})
	if metrics is Dictionary and metrics.has("event_counts"):
		return metrics.get("event_counts", {})
	return {}
