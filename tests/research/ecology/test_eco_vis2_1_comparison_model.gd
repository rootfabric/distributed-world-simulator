extends SceneTree

const ComparisonModel = preload("res://scripts/labs/ecology/eco_vis2_1_comparison_model.gd")
const ComparisonPanelScript = preload("res://scripts/labs/ecology/eco_vis2_1_comparison_panel.gd")

var _assertions := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var fixtures := _fixture_traces()
	var control: Array = fixtures["control"]
	var treatment: Array = fixtures["treatment"]
	var summary := ComparisonModel.summarize(control, treatment, 10, true)
	_check(bool(summary.get("success", false)), "fixture comparison succeeds")
	_check(String(summary.get("stage", "")) == "ECO.VIS2.1", "stage")
	_check(String(summary.get("mode", "")) == "CONTROL_TREATMENT_COMPARATOR", "mode")
	_check(int(summary.get("source_pair_count", -1)) == 5, "shared generations paired exactly")

	var points: Array = summary.get("points", [])
	for point_variant in points:
		var point: Dictionary = point_variant
		if int(point.get("generation", -1)) <= 10:
			_check(int(point.get("delta_population", 1)) == 0, "population delta zero before and at fork")
			_check(int(point.get("delta_births", 1)) == 0, "birth delta zero before and at fork")
			_check(int(point.get("delta_deaths", 1)) == 0, "death delta zero before and at fork")
			_check(int(point.get("delta_survivors", 1)) == 0, "survivor delta zero before and at fork")
			_check(float(point.get("delta_mean_fitness", 1.0)) == 0.0, "fitness delta zero before and at fork")
			_check(int(point.get("delta_unique_genomes", 1)) == 0, "genome delta zero before and at fork")
			_check(float(point.get("delta_alpha_share", 1.0)) == 0.0, "alpha share delta zero before and at fork")
			_check(float(point.get("delta_beta_share", 1.0)) == 0.0, "beta share delta zero before and at fork")

	var g11 := _point_for_generation(points, 11)
	_check(int(g11.get("delta_population", 0)) == -12, "G11 population delta")
	_check(int(g11.get("delta_births", 0)) == -6, "G11 births delta")
	_check(int(g11.get("delta_deaths", 0)) == 6, "G11 deaths delta")
	_check(int(g11.get("delta_survivors", 0)) == -8, "G11 survivors delta")
	_check(is_equal_approx(float(g11.get("delta_mean_fitness", 0.0)), -0.08), "G11 mean fitness delta")
	_check(int(g11.get("delta_unique_genomes", 0)) == -1, "G11 unique genomes delta")
	_check(is_equal_approx(float(g11.get("control_alpha_share", 0.0)), 0.60), "control alpha share")
	_check(is_equal_approx(float(g11.get("treatment_alpha_share", 0.0)), 0.40), "treatment alpha share")
	_check(is_equal_approx(float(g11.get("delta_alpha_share", 0.0)), -0.20), "alpha share delta")
	_check(is_equal_approx(float(g11.get("control_beta_share", 0.0)), 0.40), "control beta share")
	_check(is_equal_approx(float(g11.get("treatment_beta_share", 0.0)), 0.60), "treatment beta share")
	_check(is_equal_approx(float(g11.get("delta_beta_share", 0.0)), 0.20), "beta share delta")
	var population_metric: Dictionary = Dictionary(g11.get("metrics", {})).get("population", {})
	_check(int(population_metric.get("control", 0)) == 112, "metric exposes control value")
	_check(int(population_metric.get("treatment", 0)) == 100, "metric exposes treatment value")
	_check(int(population_metric.get("absolute_delta", 0)) == 12, "metric exposes absolute delta")
	_check(is_equal_approx(float(population_metric.get("relative_delta", 0.0)), -12.0 / 112.0), "metric exposes relative delta")
	print("ECO.VIS2.1 comparison progress: deltas_checked")

	var long_control: Array = []
	var long_treatment: Array = []
	for generation in range(80):
		long_control.append(_trace_point(generation, "control", "BASELINE", 100 + generation, 20, 10, 90, 0.75, 8, 60, 40, 1000.0 + generation, 1))
		long_treatment.append(_trace_point(generation, "treatment", "BASELINE", 100 + generation, 20, 10, 90, 0.75, 8, 60, 40, 1000.0 + generation, 1))
	var bounded := ComparisonModel.summarize(long_control, long_treatment, 79, true)
	_check(bool(bounded.get("success", false)), "bounded fixture succeeds")
	_check(int(bounded.get("source_pair_count", -1)) == 80, "all source pairs validated")
	_check(int(bounded.get("point_count", -1)) == ComparisonModel.SERIES_WINDOW, "history bounded to series window")
	var bounded_points: Array = bounded.get("points", [])
	_check(int(Dictionary(bounded_points.front()).get("generation", -1)) == 16, "bounded history keeps newest generations")
	_check(int(Dictionary(bounded_points.back()).get("generation", -1)) == 79, "bounded history ends at latest generation")

	var repeat := ComparisonModel.summarize(control.duplicate(true), treatment.duplicate(true), 10, true)
	_check(String(summary.get("summary_hash", "")).length() == 64, "summary hash is SHA-256")
	_check(String(summary.get("summary_hash", "")) == String(repeat.get("summary_hash", "")), "summary hash deterministic on repeat")
	var reversed_control := control.duplicate(true)
	var reversed_treatment := treatment.duplicate(true)
	reversed_control.reverse()
	reversed_treatment.reverse()
	var reordered := ComparisonModel.summarize(reversed_control, reversed_treatment, 10, true)
	_check(String(summary.get("summary_hash", "")) == String(reordered.get("summary_hash", "")), "summary hash independent of trace ordering")
	print("ECO.VIS2.1 comparison progress: boundedness_and_hash_checked")

	var duplicate_control := control.duplicate(true)
	duplicate_control.append(Dictionary(control[0]).duplicate(true))
	var duplicate_result := ComparisonModel.summarize(duplicate_control, treatment, 10, true)
	_check(not bool(duplicate_result.get("success", true)), "duplicate generation rejected")
	_check(String(duplicate_result.get("error_code", "")) == "DUPLICATE_GENERATION", "duplicate rejection code")

	var malformed_control := control.duplicate(true)
	var malformed_point: Dictionary = Dictionary(malformed_control[0]).duplicate(true)
	malformed_point.erase("survivor_count")
	malformed_control[0] = malformed_point
	var malformed_result := ComparisonModel.summarize(malformed_control, treatment, 10, true)
	_check(not bool(malformed_result.get("success", true)), "malformed trace point rejected")
	_check(String(malformed_result.get("error_code", "")) == "MALFORMED_TRACE_POINT", "malformed rejection code")

	var missing_treatment := treatment.duplicate(true)
	missing_treatment.pop_back()
	var strict_missing := ComparisonModel.summarize(control, missing_treatment, 10, true)
	_check(not bool(strict_missing.get("success", true)), "strict missing counterpart rejected")
	_check(String(strict_missing.get("error_code", "")) == "MISSING_TREATMENT_COUNTERPART", "strict counterpart rejection code")
	var non_strict := ComparisonModel.summarize(control, missing_treatment, 10, false)
	_check(bool(non_strict.get("success", false)), "non-strict mode compares shared generations")
	_check(int(non_strict.get("source_pair_count", -1)) == 4, "non-strict mode pairs intersection only")

	var divergent_treatment := treatment.duplicate(true)
	var divergent_point: Dictionary = Dictionary(divergent_treatment[1]).duplicate(true)
	divergent_point["visual_count"] = int(divergent_point["visual_count"]) + 1
	divergent_treatment[1] = divergent_point
	var divergence := ComparisonModel.summarize(control, divergent_treatment, 10, true)
	_check(not bool(divergence.get("success", true)), "pre-fork divergence rejected")
	_check(String(divergence.get("error_code", "")) == "PRE_FORK_DIVERGENCE", "pre-fork rejection code")
	print("ECO.VIS2.1 comparison progress: rejection_rules_checked")

	var panel := ComparisonPanelScript.new() as Control
	_check(panel != null, "comparison panel instantiates")
	if panel != null:
		panel.size = Vector2(760.0, 380.0)
		_check(panel.mouse_filter == Control.MOUSE_FILTER_IGNORE, "panel ignores mouse immediately")
		get_root().add_child(panel)
		await process_frame
		_check(panel.mouse_filter == Control.MOUSE_FILTER_IGNORE, "panel ignores mouse after ready")
		_check(bool(panel.set_comparison_data(control, treatment, 10, true)), "panel accepts fixture traces")
		await process_frame
		var panel_summary: Dictionary = panel.get_comparison_summary()
		_check(bool(panel_summary.get("success", false)), "panel stores valid comparison summary")
		_check(String(panel_summary.get("summary_hash", "")) == String(summary.get("summary_hash", "")), "panel uses deterministic model summary")
		panel.queue_free()
		await process_frame
	print("ECO.VIS2.1 comparison progress: panel_checked")

	print("ECO.VIS2.1 comparison model: PASS (%d assertions)" % _assertions)
	quit(0)

func _fixture_traces() -> Dictionary:
	var control: Array = [
		_trace_point(8, "control", "BASELINE", 100, 20, 10, 90, 0.80, 10, 60, 40, 1000.0, 2),
		_trace_point(9, "control", "BASELINE", 105, 18, 13, 92, 0.81, 11, 63, 42, 1040.0, 2),
		_trace_point(10, "control", "BASELINE", 110, 20, 15, 95, 0.82, 12, 66, 44, 1080.0, 2),
		_trace_point(11, "control", "BASELINE", 112, 18, 16, 96, 0.83, 12, 60, 40, 1100.0, 2),
		_trace_point(12, "control", "BASELINE", 115, 20, 17, 98, 0.84, 13, 60, 40, 1120.0, 2),
	]
	var treatment: Array = [
		_trace_point(8, "treatment", "BASELINE", 100, 20, 10, 90, 0.80, 10, 60, 40, 1000.0, 2),
		_trace_point(9, "treatment", "BASELINE", 105, 18, 13, 92, 0.81, 11, 63, 42, 1040.0, 2),
		_trace_point(10, "treatment", "BASELINE", 110, 20, 15, 95, 0.82, 12, 66, 44, 1080.0, 2),
		_trace_point(11, "treatment", "DROUGHT", 100, 12, 22, 88, 0.75, 11, 40, 60, 930.0, 3),
		_trace_point(12, "treatment", "DROUGHT", 92, 8, 30, 75, 0.70, 10, 30, 70, 850.0, 4),
	]
	return {"control": control, "treatment": treatment}

func _trace_point(generation: int, branch_id: String, experiment_id: String, visual_count: int, birth_count: int, death_count: int, survivor_count: int, mean_fitness: float, unique_genomes: int, alpha_count: int, beta_count: int, represented_biomass_kg: float, environment_revision: int) -> Dictionary:
	return {
		"generation": generation,
		"branch_id": branch_id,
		"experiment_id": experiment_id,
		"visual_count": visual_count,
		"birth_count": birth_count,
		"death_count": death_count,
		"survivor_count": survivor_count,
		"mean_fitness": mean_fitness,
		"unique_genomes": unique_genomes,
		"alpha_count": alpha_count,
		"beta_count": beta_count,
		"represented_biomass_kg": represented_biomass_kg,
		"field_hash": ("%d:%d:%d:%d:%d:%.12f:%d:%d:%d:%.12f:%d" % [generation, visual_count, birth_count, death_count, survivor_count, mean_fitness, unique_genomes, alpha_count, beta_count, represented_biomass_kg, environment_revision]).sha256_text(),
		"environment_revision": environment_revision,
	}

func _point_for_generation(points: Array, generation: int) -> Dictionary:
	for point_variant in points:
		var point: Dictionary = point_variant
		if int(point.get("generation", -1)) == generation:
			return point
	return {}

func _check(condition: bool, label: String) -> void:
	_assertions += 1
	if condition:
		return
	push_error("ECO.VIS2.1 assertion failed: %s" % label)
	quit(1)
