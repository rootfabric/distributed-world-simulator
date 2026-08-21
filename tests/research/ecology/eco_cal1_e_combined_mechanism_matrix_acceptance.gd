extends SceneTree

const Matrix = preload("res://scripts/research/ecology/plant_combined_mechanism_matrix_v1.gd")

const EXPECTED_PARENT_D := "c295da316e42fdf2f1073f8853709482191818a23763e9991d473cb5064992b6"
const EPSILON := 0.000000001

var assertions := 0
var failures: Array[String] = []

func _init() -> void:
	var result: Dictionary = Matrix.run()
	_check(not result.is_empty(), "CAL1-E result must exist")
	if result.is_empty():
		_finish()
		return

	_check(String(result.get("cal1_d_parent_hash", "")) == EXPECTED_PARENT_D, "accepted CAL1-D parent hash must remain exact")
	_check(int(result.get("context_count", -1)) == 24, "matrix must contain 24 environment/density/disturbance contexts")
	_check(int(result.get("row_count", -1)) == 192, "matrix must contain 192 strategy-context rows")
	_check(int(result.get("sparse_nonzero_interaction_rows", -1)) == 0, "50m SPARSE control must remove B/C neighbour interactions")
	_check(int(result.get("dense_nonzero_interaction_rows", 0)) > 0, "DENSE contexts must activate accepted neighbour mechanisms")
	_check(int(result.get("multiobjective_contexts", 0)) > 0, "at least one context must expose different winners across causal objectives")
	_check(int(result.get("multi_member_pareto_contexts", 0)) > 0, "at least one context must retain multiple non-dominated strategies")
	_check(int(result.get("distinct_pareto_signatures", 0)) > 0, "Pareto diagnostics must exist")
	_check(String(result.get("aggregate_hash", "")).length() == 64, "aggregate hash must be sha256")

	var repeat: Dictionary = Matrix.run()
	_check(not repeat.is_empty(), "same-process repeat must exist")
	if not repeat.is_empty():
		_check(String(repeat.get("aggregate_hash", "")) == String(result.get("aggregate_hash", "")), "same-process aggregate must be deterministic")

	var contexts: Dictionary = result.get("contexts", {})
	for environment_name in Matrix.ENVIRONMENT_ORDER:
		for density_name in Matrix.DENSITY_ORDER:
			var none_id := "%s/%s/NONE" % [environment_name, density_name]
			var mild_id := "%s/%s/MILD" % [environment_name, density_name]
			var severe_id := "%s/%s/SEVERE" % [environment_name, density_name]
			_check(contexts.has(none_id) and contexts.has(mild_id) and contexts.has(severe_id), "disturbance context triplet must exist: %s/%s" % [environment_name, density_name])
			if not contexts.has(none_id) or not contexts.has(mild_id) or not contexts.has(severe_id):
				continue
			for strategy_name in Matrix.STRATEGY_ORDER:
				var none_row := _row(contexts[none_id], strategy_name)
				var mild_row := _row(contexts[mild_id], strategy_name)
				var severe_row := _row(contexts[severe_id], strategy_name)
				_check(not none_row.is_empty() and not mild_row.is_empty() and not severe_row.is_empty(), "strategy row must exist across disturbance triplet: %s" % strategy_name)
				if none_row.is_empty() or mild_row.is_empty() or severe_row.is_empty():
					continue
				_check(float(none_row["disturbance_survival_fraction"]) + EPSILON >= float(mild_row["disturbance_survival_fraction"]), "MILD cannot improve survival over NONE")
				_check(float(mild_row["disturbance_survival_fraction"]) + EPSILON >= float(severe_row["disturbance_survival_fraction"]), "SEVERE cannot improve survival over MILD")
				_check(float(none_row["post_disturbance_seed_potential"]) + EPSILON >= float(mild_row["post_disturbance_seed_potential"]), "MILD cannot improve post-disturbance seeds over NONE")
				_check(float(mild_row["post_disturbance_seed_potential"]) + EPSILON >= float(severe_row["post_disturbance_seed_potential"]), "SEVERE cannot improve post-disturbance seeds over MILD")

	var reference_dense_none: Dictionary = contexts.get("REFERENCE/DENSE/NONE", {})
	var reference_sparse_none: Dictionary = contexts.get("REFERENCE/SPARSE/NONE", {})
	_check(not reference_dense_none.is_empty() and not reference_sparse_none.is_empty(), "reference density controls must exist")
	if not reference_dense_none.is_empty() and not reference_sparse_none.is_empty():
		var high_dense := _row(reference_dense_none, "HEIGHT_HIGH")
		var low_dense := _row(reference_dense_none, "HEIGHT_LOW")
		var high_sparse := _row(reference_sparse_none, "HEIGHT_HIGH")
		_check(float(high_dense["vertical_light_delta"]) > float(low_dense["vertical_light_delta"]), "dense HEIGHT_HIGH must receive more relative-light delta than HEIGHT_LOW")
		_check(float(high_dense["effective_seed_dispersal_m"]) > float(low_dense["effective_seed_dispersal_m"]), "same-stage taller morphology must release seeds farther")
		_check(float(high_dense["maturity_time_index_years"]) > float(low_dense["maturity_time_index_years"]), "taller morphology at matched growth rate must mature later")
		_check(absf(float(high_sparse["vertical_light_delta"])) <= EPSILON, "sparse HEIGHT_HIGH relative-light delta must be zero without overlap")

	for context_value in contexts.values():
		var context: Dictionary = context_value
		var summary: Dictionary = context.get("summary", {})
		_check(Array(summary.get("pareto_front", [])).size() >= 1, "every context must have a non-empty Pareto front")
		for row_value in Array(context.get("rows", [])):
			var row: Dictionary = row_value
			_check(not row.has("combined_fitness") and not row.has("weighted_fitness"), "CAL1-E must not smuggle an arbitrary weighted scalar")
			_check(String(row.get("row_hash", "")).length() == 64, "every row must have deterministic hash")

	var dense_summary: Dictionary = reference_dense_none.get("summary", {})
	var severe_summary: Dictionary = contexts.get("REFERENCE/DENSE/SEVERE", {}).get("summary", {})
	print("ECO.CAL1-E rows=%d contexts=%d dense_nonzero=%d sparse_nonzero=%d multiobjective_contexts=%d multi_pareto=%d pareto_signatures=%d" % [
		int(result["row_count"]), int(result["context_count"]), int(result["dense_nonzero_interaction_rows"]),
		int(result["sparse_nonzero_interaction_rows"]), int(result["multiobjective_contexts"]),
		int(result["multi_member_pareto_contexts"]), int(result["distinct_pareto_signatures"])
	])
	print("ECO.CAL1-E REFERENCE/DENSE/NONE pareto=%s resource=%s seed=%s dispersal=%s" % [
		str(dense_summary.get("pareto_front", [])), str(dense_summary.get("resource_winners", [])),
		str(dense_summary.get("seed_winners", [])), str(dense_summary.get("dispersal_winners", []))
	])
	print("ECO.CAL1-E REFERENCE/DENSE/SEVERE pareto=%s survival=%s recovery=%s" % [
		str(severe_summary.get("pareto_front", [])), str(severe_summary.get("survival_winners", [])), str(severe_summary.get("recovery_winners", []))
	])
	print("ECO.CAL1-E Combined Mechanism Matrix: PASS (%d assertions) aggregate_hash=%s cal1_d=%s" % [assertions, String(result["aggregate_hash"]), String(result["cal1_d_parent_hash"])])
	_finish()

func _row(context: Dictionary, strategy_name: String) -> Dictionary:
	for row_value in Array(context.get("rows", [])):
		var row: Dictionary = row_value
		if String(row.get("strategy", "")) == strategy_name:
			return row
	return {}

func _check(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)

func _finish() -> void:
	if failures.is_empty():
		quit(0)
		return
	for message in failures:
		push_error("ECO.CAL1-E ASSERTION FAILED: " + message)
	print("ECO.CAL1-E Combined Mechanism Matrix: FAIL (%d assertions, %d failures)" % [assertions, failures.size()])
	quit(1)
