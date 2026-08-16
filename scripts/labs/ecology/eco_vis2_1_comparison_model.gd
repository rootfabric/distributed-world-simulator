extends RefCounted

const STAGE := "ECO.VIS2.1"
const MODE := "CONTROL_TREATMENT_COMPARATOR"
const SERIES_WINDOW := 64

const REQUIRED_KEYS := [
	"generation",
	"branch_id",
	"experiment_id",
	"visual_count",
	"birth_count",
	"death_count",
	"survivor_count",
	"mean_fitness",
	"unique_genomes",
	"alpha_count",
	"beta_count",
	"represented_biomass_kg",
	"field_hash",
	"environment_revision",
]

const INTEGER_KEYS := [
	"generation",
	"visual_count",
	"birth_count",
	"death_count",
	"survivor_count",
	"unique_genomes",
	"alpha_count",
	"beta_count",
]

static func summarize(control_trace: Array, treatment_trace: Array, fork_generation: int, strict: bool = true) -> Dictionary:
	if fork_generation < 0:
		return _failure("INVALID_FORK_GENERATION", "fork_generation must be non-negative")

	var control_result := _index_trace(control_trace, "control")
	if not bool(control_result.get("success", false)):
		return control_result
	var treatment_result := _index_trace(treatment_trace, "treatment")
	if not bool(treatment_result.get("success", false)):
		return treatment_result

	var control_by_generation: Dictionary = control_result.get("points", {})
	var treatment_by_generation: Dictionary = treatment_result.get("points", {})
	if strict:
		var control_generations := _sorted_generations(control_by_generation)
		var treatment_generations := _sorted_generations(treatment_by_generation)
		for generation in control_generations:
			if not treatment_by_generation.has(generation):
				return _failure("MISSING_TREATMENT_COUNTERPART", "missing treatment point for generation %d" % generation)
		for generation in treatment_generations:
			if not control_by_generation.has(generation):
				return _failure("MISSING_CONTROL_COUNTERPART", "missing control point for generation %d" % generation)

	var generations: Array[int] = []
	for generation_variant in control_by_generation.keys():
		var generation := int(generation_variant)
		if treatment_by_generation.has(generation):
			generations.append(generation)
	generations.sort()

	var all_points: Array[Dictionary] = []
	for generation in generations:
		var control_point: Dictionary = control_by_generation[generation]
		var treatment_point: Dictionary = treatment_by_generation[generation]
		var paired := _pair_point(control_point, treatment_point)
		if generation <= fork_generation and not _has_pre_fork_identity(paired):
			return _failure(
				"PRE_FORK_DIVERGENCE",
				"control and treatment diverge at generation %d; divergence is only allowed after fork generation %d" % [generation, fork_generation]
			)
		all_points.append(paired)

	var points: Array[Dictionary] = all_points.duplicate(true)
	while points.size() > SERIES_WINDOW:
		points.pop_front()

	var ranges := {
		"population": _triple_range(points, "control_population", "treatment_population", "delta_population", true),
		"mean_fitness": _triple_range(points, "control_mean_fitness", "treatment_mean_fitness", "delta_mean_fitness", false),
		"genetic_diversity": _triple_range(points, "control_unique_genomes", "treatment_unique_genomes", "delta_unique_genomes", true),
		"mortality": _triple_range(points, "control_deaths", "treatment_deaths", "delta_deaths", true),
		"alpha_share": _triple_range(points, "control_alpha_share", "treatment_alpha_share", "delta_alpha_share", false),
	}
	return {
		"success": true,
		"stage": STAGE,
		"mode": MODE,
		"strict": strict,
		"fork_generation": fork_generation,
		"source_pair_count": all_points.size(),
		"point_count": points.size(),
		"points": points,
		"ranges": ranges,
		"summary_hash": compute_summary_hash(points, fork_generation, strict),
	}

static func compute_summary_hash(points: Array[Dictionary], fork_generation: int, strict: bool = true) -> String:
	var tokens := PackedStringArray([STAGE, MODE, "fork=%d" % fork_generation, "strict=%d" % int(strict)])
	for point in points:
		tokens.append(
			"G%d|cb=%s|tb=%s|ce=%s|te=%s|cp=%d|tp=%d|dp=%d|cbirth=%d|tbirth=%d|dbirth=%d|cdeath=%d|tdeath=%d|ddeath=%d|csurv=%d|tsurv=%d|dsurv=%d|cf=%.12f|tf=%.12f|df=%.12f|cu=%d|tu=%d|du=%d|ca=%.12f|ta=%.12f|da=%.12f|cz=%.12f|tz=%.12f|dz=%.12f|cfh=%s|tfh=%s|cer=%s|ter=%s" % [
				int(point.get("generation", 0)),
				String(point.get("control_branch_id", "")),
				String(point.get("treatment_branch_id", "")),
				String(point.get("control_experiment_id", "")),
				String(point.get("treatment_experiment_id", "")),
				int(point.get("control_population", 0)),
				int(point.get("treatment_population", 0)),
				int(point.get("delta_population", 0)),
				int(point.get("control_births", 0)),
				int(point.get("treatment_births", 0)),
				int(point.get("delta_births", 0)),
				int(point.get("control_deaths", 0)),
				int(point.get("treatment_deaths", 0)),
				int(point.get("delta_deaths", 0)),
				int(point.get("control_survivors", 0)),
				int(point.get("treatment_survivors", 0)),
				int(point.get("delta_survivors", 0)),
				float(point.get("control_mean_fitness", 0.0)),
				float(point.get("treatment_mean_fitness", 0.0)),
				float(point.get("delta_mean_fitness", 0.0)),
				int(point.get("control_unique_genomes", 0)),
				int(point.get("treatment_unique_genomes", 0)),
				int(point.get("delta_unique_genomes", 0)),
				float(point.get("control_alpha_share", 0.0)),
				float(point.get("treatment_alpha_share", 0.0)),
				float(point.get("delta_alpha_share", 0.0)),
				float(point.get("control_beta_share", 0.0)),
				float(point.get("treatment_beta_share", 0.0)),
				float(point.get("delta_beta_share", 0.0)),
				String(point.get("control_field_hash", "")),
				String(point.get("treatment_field_hash", "")),
				String(point.get("control_environment_revision", "")),
				String(point.get("treatment_environment_revision", "")),
			]
		)
	return "\n".join(tokens).sha256_text()

static func _index_trace(trace: Array, trace_name: String) -> Dictionary:
	var points := {}
	for index in range(trace.size()):
		var point_variant = trace[index]
		if typeof(point_variant) != TYPE_DICTIONARY:
			return _failure("MALFORMED_TRACE_POINT", "%s trace point %d is not a Dictionary" % [trace_name, index])
		var point: Dictionary = Dictionary(point_variant)
		var validation := _validate_point(point, trace_name, index)
		if not bool(validation.get("success", false)):
			return validation
		var generation := int(point["generation"])
		if points.has(generation):
			return _failure("DUPLICATE_GENERATION", "%s trace contains duplicate generation %d" % [trace_name, generation])
		points[generation] = _canonical_point(point)
	return {"success": true, "points": points}

static func _sorted_generations(points_by_generation: Dictionary) -> Array[int]:
	var generations: Array[int] = []
	for generation_variant in points_by_generation.keys():
		generations.append(int(generation_variant))
	generations.sort()
	return generations

static func _validate_point(point: Dictionary, trace_name: String, index: int) -> Dictionary:
	for key in REQUIRED_KEYS:
		if not point.has(key):
			return _failure("MALFORMED_TRACE_POINT", "%s trace point %d is missing %s" % [trace_name, index, key])
	for key in INTEGER_KEYS:
		if typeof(point[key]) != TYPE_INT:
			return _failure("MALFORMED_TRACE_POINT", "%s trace point %d field %s must be an int" % [trace_name, index, key])
		if int(point[key]) < 0:
			return _failure("MALFORMED_TRACE_POINT", "%s trace point %d field %s must be non-negative" % [trace_name, index, key])
	for key in ["branch_id", "experiment_id", "field_hash", "environment_revision"]:
		if typeof(point[key]) != TYPE_STRING or String(point[key]).strip_edges().is_empty():
			return _failure("MALFORMED_TRACE_POINT", "%s trace point %d field %s must be a non-empty String" % [trace_name, index, key])
	for key in ["mean_fitness", "represented_biomass_kg"]:
		var value_variant = point[key]
		if typeof(value_variant) != TYPE_FLOAT and typeof(value_variant) != TYPE_INT:
			return _failure("MALFORMED_TRACE_POINT", "%s trace point %d field %s must be numeric" % [trace_name, index, key])
		var value := float(value_variant)
		if is_nan(value) or is_inf(value) or value < 0.0:
			return _failure("MALFORMED_TRACE_POINT", "%s trace point %d field %s must be finite and non-negative" % [trace_name, index, key])
	return {"success": true}

static func _canonical_point(point: Dictionary) -> Dictionary:
	return {
		"generation": int(point["generation"]),
		"branch_id": String(point["branch_id"]),
		"experiment_id": String(point["experiment_id"]),
		"visual_count": int(point["visual_count"]),
		"birth_count": int(point["birth_count"]),
		"death_count": int(point["death_count"]),
		"survivor_count": int(point["survivor_count"]),
		"mean_fitness": float(point["mean_fitness"]),
		"unique_genomes": int(point["unique_genomes"]),
		"alpha_count": int(point["alpha_count"]),
		"beta_count": int(point["beta_count"]),
		"represented_biomass_kg": float(point["represented_biomass_kg"]),
		"field_hash": String(point["field_hash"]),
		"environment_revision": String(point["environment_revision"]),
	}

static func _pair_point(control: Dictionary, treatment: Dictionary) -> Dictionary:
	var control_alpha_share := _share(int(control["alpha_count"]), int(control["beta_count"]))
	var treatment_alpha_share := _share(int(treatment["alpha_count"]), int(treatment["beta_count"]))
	var control_beta_share := _share(int(control["beta_count"]), int(control["alpha_count"]))
	var treatment_beta_share := _share(int(treatment["beta_count"]), int(treatment["alpha_count"]))

	var population := _int_metric(int(control["visual_count"]), int(treatment["visual_count"]))
	var births := _int_metric(int(control["birth_count"]), int(treatment["birth_count"]))
	var deaths := _int_metric(int(control["death_count"]), int(treatment["death_count"]))
	var survivors := _int_metric(int(control["survivor_count"]), int(treatment["survivor_count"]))
	var mean_fitness := _float_metric(float(control["mean_fitness"]), float(treatment["mean_fitness"]))
	var unique_genomes := _int_metric(int(control["unique_genomes"]), int(treatment["unique_genomes"]))
	var alpha_share := _float_metric(control_alpha_share, treatment_alpha_share)
	var beta_share := _float_metric(control_beta_share, treatment_beta_share)

	return {
		"generation": int(control["generation"]),
		"control_branch_id": String(control["branch_id"]),
		"treatment_branch_id": String(treatment["branch_id"]),
		"control_experiment_id": String(control["experiment_id"]),
		"treatment_experiment_id": String(treatment["experiment_id"]),
		"control_population": int(population["control"]),
		"treatment_population": int(population["treatment"]),
		"delta_population": int(population["delta"]),
		"control_births": int(births["control"]),
		"treatment_births": int(births["treatment"]),
		"delta_births": int(births["delta"]),
		"control_deaths": int(deaths["control"]),
		"treatment_deaths": int(deaths["treatment"]),
		"delta_deaths": int(deaths["delta"]),
		"control_survivors": int(survivors["control"]),
		"treatment_survivors": int(survivors["treatment"]),
		"delta_survivors": int(survivors["delta"]),
		"control_mean_fitness": float(mean_fitness["control"]),
		"treatment_mean_fitness": float(mean_fitness["treatment"]),
		"delta_mean_fitness": float(mean_fitness["delta"]),
		"control_unique_genomes": int(unique_genomes["control"]),
		"treatment_unique_genomes": int(unique_genomes["treatment"]),
		"delta_unique_genomes": int(unique_genomes["delta"]),
		"control_alpha_share": float(alpha_share["control"]),
		"treatment_alpha_share": float(alpha_share["treatment"]),
		"delta_alpha_share": float(alpha_share["delta"]),
		"control_beta_share": float(beta_share["control"]),
		"treatment_beta_share": float(beta_share["treatment"]),
		"delta_beta_share": float(beta_share["delta"]),
		"control_represented_biomass_kg": float(control["represented_biomass_kg"]),
		"treatment_represented_biomass_kg": float(treatment["represented_biomass_kg"]),
		"control_field_hash": String(control["field_hash"]),
		"treatment_field_hash": String(treatment["field_hash"]),
		"control_environment_revision": String(control["environment_revision"]),
		"treatment_environment_revision": String(treatment["environment_revision"]),
		"metrics": {
			"population": population,
			"births": births,
			"deaths": deaths,
			"survivors": survivors,
			"mean_fitness": mean_fitness,
			"unique_genomes": unique_genomes,
			"alpha_share": alpha_share,
			"beta_share": beta_share,
		},
	}

static func _int_metric(control: int, treatment: int) -> Dictionary:
	var delta := treatment - control
	var metric := {
		"control": control,
		"treatment": treatment,
		"delta": delta,
		"absolute_delta": absi(delta),
	}
	if control != 0:
		metric["relative_delta"] = float(delta) / float(control)
	return metric

static func _float_metric(control: float, treatment: float) -> Dictionary:
	var delta := treatment - control
	var metric := {
		"control": control,
		"treatment": treatment,
		"delta": delta,
		"absolute_delta": absf(delta),
	}
	if not is_zero_approx(control):
		metric["relative_delta"] = delta / control
	return metric

static func _share(numerator: int, other: int) -> float:
	var total := numerator + other
	if total <= 0:
		return 0.0
	return float(numerator) / float(total)

static func _has_pre_fork_identity(point: Dictionary) -> bool:
	return (
		_has_zero_deltas(point)
		and String(point.get("control_field_hash", "")) == String(point.get("treatment_field_hash", ""))
		and String(point.get("control_environment_revision", "")) == String(point.get("treatment_environment_revision", ""))
	)

static func _has_zero_deltas(point: Dictionary) -> bool:
	return (
		int(point.get("delta_population", 0)) == 0
		and int(point.get("delta_births", 0)) == 0
		and int(point.get("delta_deaths", 0)) == 0
		and int(point.get("delta_survivors", 0)) == 0
		and float(point.get("delta_mean_fitness", 0.0)) == 0.0
		and int(point.get("delta_unique_genomes", 0)) == 0
		and float(point.get("delta_alpha_share", 0.0)) == 0.0
		and float(point.get("delta_beta_share", 0.0)) == 0.0
	)

static func _triple_range(points: Array[Dictionary], key_a: String, key_b: String, key_c: String, integral: bool) -> Dictionary:
	if points.is_empty():
		return {"min": 0.0, "max": 1.0}
	var minimum := INF
	var maximum := -INF
	for point in points:
		for key in [key_a, key_b, key_c]:
			var value := float(point.get(key, 0.0))
			minimum = minf(minimum, value)
			maximum = maxf(maximum, value)
	if is_equal_approx(minimum, maximum):
		var padding := 1.0 if integral else 0.05
		minimum -= padding
		maximum += padding
	return {"min": minimum, "max": maximum}

static func _failure(code: String, message: String) -> Dictionary:
	return {
		"success": false,
		"stage": STAGE,
		"mode": MODE,
		"error_code": code,
		"error": message,
		"point_count": 0,
		"points": [],
	}
