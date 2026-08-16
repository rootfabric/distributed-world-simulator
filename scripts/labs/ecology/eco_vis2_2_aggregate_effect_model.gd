extends RefCounted

const ComparisonModel = preload("res://scripts/labs/ecology/eco_vis2_1_comparison_model.gd")

const STAGE := "ECO.VIS2.2-B"
const MODE := "REPLICATED_CAUSAL_EFFECT_AGGREGATE"
const SERIES_WINDOW := 64
const HASH_PRECISION_DECIMALS := 12
const FLOAT_SIGN_EPSILON := 0.000000000001

var _configured := false
var _fork_generation := -1
var _replicate_count := 0
var _points: Array[Dictionary] = []


func configure(fork_generation: int, replicate_count: int) -> Dictionary:
	clear()
	if fork_generation < 0:
		return _failure("INVALID_FORK_GENERATION")
	if replicate_count < 2 or replicate_count > 16:
		return _failure("INVALID_REPLICATE_COUNT")
	_fork_generation = fork_generation
	_replicate_count = replicate_count
	_configured = true
	return {
		"success": true,
		"stage": STAGE,
		"mode": MODE,
		"fork_generation": _fork_generation,
		"replicate_count": _replicate_count,
		"series_window": SERIES_WINDOW,
		"hash_precision_decimals": HASH_PRECISION_DECIMALS,
	}


func append_generation(replicate_pairs: Array) -> Dictionary:
	if not _configured:
		return _failure("NOT_CONFIGURED")
	var build_result := build_point(replicate_pairs, _fork_generation, _replicate_count)
	if not bool(build_result.get("success", false)):
		return build_result
	var point: Dictionary = Dictionary(build_result.get("point", {})).duplicate(true)
	var generation := int(point.get("generation", -1))
	if generation < _fork_generation:
		return _failure("GENERATION_BEFORE_FORK")

	if _points.is_empty():
		if generation != _fork_generation:
			return _failure("FIRST_POINT_MUST_BE_FORK")
	else:
		var latest := int(_points[-1].get("generation", -1))
		if generation <= latest:
			var retained: Array[Dictionary] = []
			for existing in _points:
				if int(existing.get("generation", -1)) < generation:
					retained.append(existing.duplicate(true))
			_points = retained
		if _points.is_empty():
			if generation != _fork_generation:
				return _failure("REPLACEMENT_LOST_FORK_SEQUENCE")
		else:
			var expected_generation := int(_points[-1].get("generation", -1)) + 1
			if generation != expected_generation:
				return _failure("NON_CONTIGUOUS_GENERATION")

	_points.append(point)
	while _points.size() > SERIES_WINDOW:
		_points.pop_front()
	return {
		"success": true,
		"generation": generation,
		"point_count": _points.size(),
		"oldest_generation": oldest_generation(),
		"latest_generation": latest_generation(),
		"point_hash": String(point.get("point_hash", "")),
		"series_hash": series_hash(),
	}


func truncate_after(generation: int) -> Dictionary:
	if not _configured:
		return _failure("NOT_CONFIGURED")
	if not _points.is_empty() and generation < oldest_generation():
		return _failure("GENERATION_BEFORE_AGGREGATE_CACHE")
	var retained: Array[Dictionary] = []
	for point in _points:
		if int(point.get("generation", -1)) <= generation:
			retained.append(point.duplicate(true))
	_points = retained
	return {
		"success": true,
		"generation": generation,
		"point_count": _points.size(),
		"oldest_generation": oldest_generation(),
		"latest_generation": latest_generation(),
		"series_hash": series_hash(),
	}


func clear() -> void:
	_configured = false
	_fork_generation = -1
	_replicate_count = 0
	_points.clear()


func points() -> Array[Dictionary]:
	return _points.duplicate(true)


func point_at_generation(generation: int) -> Dictionary:
	for point in _points:
		if int(point.get("generation", -1)) == generation:
			return point.duplicate(true)
	return {}


func latest_point() -> Dictionary:
	if _points.is_empty():
		return {}
	return _points[-1].duplicate(true)


func point_count() -> int:
	return _points.size()


func oldest_generation() -> int:
	if _points.is_empty():
		return -1
	return int(_points[0].get("generation", -1))


func latest_generation() -> int:
	if _points.is_empty():
		return -1
	return int(_points[-1].get("generation", -1))


func series_hash() -> String:
	if not _configured:
		return ""
	var tokens := PackedStringArray([
		STAGE,
		MODE,
		"fork=%d" % _fork_generation,
		"replicates=%d" % _replicate_count,
		"window=%d" % SERIES_WINDOW,
		"hash_decimals=%d" % HASH_PRECISION_DECIMALS,
	])
	for point in _points:
		tokens.append(String(point.get("point_hash", "")))
	return "\n".join(tokens).sha256_text()


func summary() -> Dictionary:
	if not _configured:
		return _failure("NOT_CONFIGURED")
	return {
		"success": true,
		"stage": STAGE,
		"mode": MODE,
		"fork_generation": _fork_generation,
		"replicate_count": _replicate_count,
		"point_count": _points.size(),
		"oldest_generation": oldest_generation(),
		"latest_generation": latest_generation(),
		"series_window": SERIES_WINDOW,
		"hash_precision_decimals": HASH_PRECISION_DECIMALS,
		"points": points(),
		"series_hash": series_hash(),
	}


static func build_point(replicate_pairs: Array, fork_generation: int, expected_replicate_count: int) -> Dictionary:
	if fork_generation < 0:
		return _failure("INVALID_FORK_GENERATION")
	if expected_replicate_count < 2 or expected_replicate_count > 16:
		return _failure("INVALID_REPLICATE_COUNT")
	if replicate_pairs.size() != expected_replicate_count:
		return _failure("REPLICATE_COUNT_MISMATCH")

	var by_index := {}
	var roots := {}
	for pair_variant in replicate_pairs:
		if typeof(pair_variant) != TYPE_DICTIONARY:
			return _failure("INVALID_REPLICATE_PAIR")
		var pair: Dictionary = pair_variant
		if typeof(pair.get("replicate_index", null)) != TYPE_INT:
			return _failure("INVALID_REPLICATE_INDEX")
		var replicate_index := int(pair.get("replicate_index", -1))
		if replicate_index < 0 or replicate_index >= expected_replicate_count:
			return _failure("INVALID_REPLICATE_INDEX")
		if by_index.has(replicate_index):
			return _failure("DUPLICATE_REPLICATE_INDEX")
		var root := String(pair.get("root", ""))
		if not _is_valid_seed_hash(root):
			return _failure("INVALID_REPLICATE_ROOT")
		if roots.has(root):
			return _failure("DUPLICATE_REPLICATE_ROOT")
		roots[root] = true
		by_index[replicate_index] = pair.duplicate(true)

	var generation := -1
	var treatment_experiment_id := ""
	var population_deltas: Array[float] = []
	var fitness_deltas: Array[float] = []
	var genome_deltas: Array[float] = []
	var birth_deltas: Array[float] = []
	var death_deltas: Array[float] = []
	var survivor_deltas: Array[float] = []
	var biomass_deltas: Array[float] = []
	var alpha_share_deltas: Array[float] = []
	var replicate_identities: Array[Dictionary] = []

	for replicate_index in range(expected_replicate_count):
		if not by_index.has(replicate_index):
			return _failure("MISSING_REPLICATE_INDEX")
		var pair: Dictionary = by_index[replicate_index]
		var root := String(pair.get("root", ""))
		var control_variant: Variant = pair.get("control", null)
		var treatment_variant: Variant = pair.get("treatment", null)
		if typeof(control_variant) != TYPE_DICTIONARY or typeof(treatment_variant) != TYPE_DICTIONARY:
			return _failure("INVALID_TRACE_POINT")
		var control: Dictionary = Dictionary(control_variant).duplicate(true)
		var treatment: Dictionary = Dictionary(treatment_variant).duplicate(true)
		if String(control.get("branch_id", "")) != "CONTROL":
			return _failure("INVALID_CONTROL_BRANCH")
		if String(treatment.get("branch_id", "")) != "TREATMENT":
			return _failure("INVALID_TREATMENT_BRANCH")
		var control_generation := int(control.get("generation", -1))
		var treatment_generation := int(treatment.get("generation", -1))
		if control_generation != treatment_generation:
			return _failure("PAIR_GENERATION_MISMATCH")
		if generation < 0:
			generation = control_generation
		elif control_generation != generation:
			return _failure("REPLICATE_GENERATION_MISMATCH")
		if generation < fork_generation:
			return _failure("GENERATION_BEFORE_FORK")

		var comparison: Dictionary = ComparisonModel.summarize(
			[control],
			[treatment],
			fork_generation,
			true
		)
		if not bool(comparison.get("success", false)):
			return _failure("PAIR_COMPARISON_REJECTED", replicate_index, String(comparison.get("error", comparison.get("reason", ""))))
		var comparison_points: Array = comparison.get("points", [])
		if comparison_points.size() != 1 or typeof(comparison_points[0]) != TYPE_DICTIONARY:
			return _failure("PAIR_COMPARISON_POINT_MISSING")
		var paired: Dictionary = Dictionary(comparison_points[0]).duplicate(true)
		var pair_treatment_experiment := String(paired.get("treatment_experiment_id", ""))
		if treatment_experiment_id.is_empty():
			treatment_experiment_id = pair_treatment_experiment
		elif pair_treatment_experiment != treatment_experiment_id:
			return _failure("TREATMENT_EXPERIMENT_MISMATCH")

		var population_delta := float(paired.get("delta_population", 0))
		var fitness_delta := _canonical_float(float(paired.get("delta_mean_fitness", 0.0)))
		var genome_delta := float(paired.get("delta_unique_genomes", 0))
		var birth_delta := float(paired.get("delta_births", 0))
		var death_delta := float(paired.get("delta_deaths", 0))
		var survivor_delta := float(paired.get("delta_survivors", 0))
		var biomass_delta := _canonical_float(
			float(paired.get("treatment_represented_biomass_kg", 0.0)) -
			float(paired.get("control_represented_biomass_kg", 0.0))
		)
		var alpha_share_delta := _canonical_float(float(paired.get("delta_alpha_share", 0.0)))

		population_deltas.append(population_delta)
		fitness_deltas.append(fitness_delta)
		genome_deltas.append(genome_delta)
		birth_deltas.append(birth_delta)
		death_deltas.append(death_delta)
		survivor_deltas.append(survivor_delta)
		biomass_deltas.append(biomass_delta)
		alpha_share_deltas.append(alpha_share_delta)

		replicate_identities.append({
			"replicate_index": replicate_index,
			"root": root,
			"pair_hash": String(comparison.get("summary_hash", "")),
			"control_field_hash": String(paired.get("control_field_hash", "")),
			"treatment_field_hash": String(paired.get("treatment_field_hash", "")),
			"control_environment_revision": String(paired.get("control_environment_revision", "")),
			"treatment_environment_revision": String(paired.get("treatment_environment_revision", "")),
			"control_experiment_id": String(paired.get("control_experiment_id", "")),
			"treatment_experiment_id": pair_treatment_experiment,
			"delta_population": int(paired.get("delta_population", 0)),
			"delta_mean_fitness": fitness_delta,
			"delta_unique_genomes": int(paired.get("delta_unique_genomes", 0)),
			"delta_births": int(paired.get("delta_births", 0)),
			"delta_deaths": int(paired.get("delta_deaths", 0)),
			"delta_survivors": int(paired.get("delta_survivors", 0)),
			"delta_represented_biomass_kg": biomass_delta,
			"delta_alpha_share": alpha_share_delta,
		})

	if generation < 0:
		return _failure("EMPTY_REPLICATE_SET")

	var population_stats := _stats(population_deltas, 0.0)
	var fitness_stats := _stats(fitness_deltas, FLOAT_SIGN_EPSILON)
	var genome_stats := _stats(genome_deltas, 0.0)
	var birth_stats := _stats(birth_deltas, 0.0)
	var death_stats := _stats(death_deltas, 0.0)
	var survivor_stats := _stats(survivor_deltas, 0.0)
	var biomass_stats := _stats(biomass_deltas, FLOAT_SIGN_EPSILON)
	var alpha_share_stats := _stats(alpha_share_deltas, FLOAT_SIGN_EPSILON)

	var point := {
		"stage": STAGE,
		"mode": MODE,
		"generation": generation,
		"fork_generation": fork_generation,
		"replicate_count": expected_replicate_count,
		"treatment_experiment_id": treatment_experiment_id,
		"hash_precision_decimals": HASH_PRECISION_DECIMALS,
		"mean_population_delta": float(population_stats["mean"]),
		"median_population_delta": float(population_stats["median"]),
		"min_population_delta": int(round(float(population_stats["min"]))),
		"max_population_delta": int(round(float(population_stats["max"]))),
		"mean_fitness_delta": float(fitness_stats["mean"]),
		"median_fitness_delta": float(fitness_stats["median"]),
		"min_fitness_delta": float(fitness_stats["min"]),
		"max_fitness_delta": float(fitness_stats["max"]),
		"mean_unique_genomes_delta": float(genome_stats["mean"]),
		"mean_birth_delta": float(birth_stats["mean"]),
		"mean_death_delta": float(death_stats["mean"]),
		"mean_survivor_delta": float(survivor_stats["mean"]),
		"mean_represented_biomass_delta": float(biomass_stats["mean"]),
		"mean_alpha_share_delta": float(alpha_share_stats["mean"]),
		"population_positive_count": int(population_stats["positive_count"]),
		"population_zero_count": int(population_stats["zero_count"]),
		"population_negative_count": int(population_stats["negative_count"]),
		"population_effect_direction": String(population_stats["dominant_direction"]),
		"population_consensus_fraction": float(population_stats["dominant_fraction"]),
		"fitness_positive_count": int(fitness_stats["positive_count"]),
		"fitness_zero_count": int(fitness_stats["zero_count"]),
		"fitness_negative_count": int(fitness_stats["negative_count"]),
		"fitness_effect_direction": String(fitness_stats["dominant_direction"]),
		"fitness_consensus_fraction": float(fitness_stats["dominant_fraction"]),
		"metrics": {
			"population": population_stats,
			"mean_fitness": fitness_stats,
			"unique_genomes": genome_stats,
			"births": birth_stats,
			"deaths": death_stats,
			"survivors": survivor_stats,
			"represented_biomass_kg": biomass_stats,
			"alpha_share": alpha_share_stats,
		},
		"replicate_identities": replicate_identities,
	}
	point["point_hash"] = compute_point_hash(point)
	return {"success": true, "point": point}


static func compute_point_hash(point: Dictionary) -> String:
	var tokens := PackedStringArray([
		STAGE,
		MODE,
		"G=%d" % int(point.get("generation", -1)),
		"fork=%d" % int(point.get("fork_generation", -1)),
		"replicates=%d" % int(point.get("replicate_count", 0)),
		"experiment=%s" % String(point.get("treatment_experiment_id", "")),
		"mean_pop=%s" % _format_float(float(point.get("mean_population_delta", 0.0))),
		"median_pop=%s" % _format_float(float(point.get("median_population_delta", 0.0))),
		"min_pop=%d" % int(point.get("min_population_delta", 0)),
		"max_pop=%d" % int(point.get("max_population_delta", 0)),
		"mean_fit=%s" % _format_float(float(point.get("mean_fitness_delta", 0.0))),
		"median_fit=%s" % _format_float(float(point.get("median_fitness_delta", 0.0))),
		"min_fit=%s" % _format_float(float(point.get("min_fitness_delta", 0.0))),
		"max_fit=%s" % _format_float(float(point.get("max_fitness_delta", 0.0))),
		"mean_genomes=%s" % _format_float(float(point.get("mean_unique_genomes_delta", 0.0))),
		"mean_birth=%s" % _format_float(float(point.get("mean_birth_delta", 0.0))),
		"mean_death=%s" % _format_float(float(point.get("mean_death_delta", 0.0))),
		"mean_survivor=%s" % _format_float(float(point.get("mean_survivor_delta", 0.0))),
		"mean_biomass=%s" % _format_float(float(point.get("mean_represented_biomass_delta", 0.0))),
		"mean_alpha=%s" % _format_float(float(point.get("mean_alpha_share_delta", 0.0))),
		"pop_sign=%d/%d/%d/%s/%s" % [
			int(point.get("population_positive_count", 0)),
			int(point.get("population_zero_count", 0)),
			int(point.get("population_negative_count", 0)),
			String(point.get("population_effect_direction", "")),
			_format_float(float(point.get("population_consensus_fraction", 0.0))),
		],
		"fit_sign=%d/%d/%d/%s/%s" % [
			int(point.get("fitness_positive_count", 0)),
			int(point.get("fitness_zero_count", 0)),
			int(point.get("fitness_negative_count", 0)),
			String(point.get("fitness_effect_direction", "")),
			_format_float(float(point.get("fitness_consensus_fraction", 0.0))),
		],
	])
	for identity_variant in Array(point.get("replicate_identities", [])):
		if typeof(identity_variant) != TYPE_DICTIONARY:
			continue
		var identity: Dictionary = identity_variant
		tokens.append(
			"R%d|root=%s|pair=%s|cf=%s|tf=%s|ce=%s|te=%s|cx=%s|tx=%s|dp=%d|df=%s|dg=%d|db=%d|dd=%d|ds=%d|dm=%s|da=%s" % [
				int(identity.get("replicate_index", -1)),
				String(identity.get("root", "")),
				String(identity.get("pair_hash", "")),
				String(identity.get("control_field_hash", "")),
				String(identity.get("treatment_field_hash", "")),
				String(identity.get("control_environment_revision", "")),
				String(identity.get("treatment_environment_revision", "")),
				String(identity.get("control_experiment_id", "")),
				String(identity.get("treatment_experiment_id", "")),
				int(identity.get("delta_population", 0)),
				_format_float(float(identity.get("delta_mean_fitness", 0.0))),
				int(identity.get("delta_unique_genomes", 0)),
				int(identity.get("delta_births", 0)),
				int(identity.get("delta_deaths", 0)),
				int(identity.get("delta_survivors", 0)),
				_format_float(float(identity.get("delta_represented_biomass_kg", 0.0))),
				_format_float(float(identity.get("delta_alpha_share", 0.0))),
			]
		)
	return "\n".join(tokens).sha256_text()


static func _stats(values: Array[float], sign_epsilon: float) -> Dictionary:
	if values.is_empty():
		return {}
	var total := 0.0
	var positive_count := 0
	var zero_count := 0
	var negative_count := 0
	for value in values:
		total += value
		if value > sign_epsilon:
			positive_count += 1
		elif value < -sign_epsilon:
			negative_count += 1
		else:
			zero_count += 1
	var sorted_values: Array[float] = values.duplicate()
	sorted_values.sort()
	var middle := int(sorted_values.size() / 2)
	var median := 0.0
	if sorted_values.size() % 2 == 0:
		median = (sorted_values[middle - 1] + sorted_values[middle]) * 0.5
	else:
		median = sorted_values[middle]
	var dominant := _dominant_direction(positive_count, zero_count, negative_count)
	var dominant_count := maxi(positive_count, maxi(zero_count, negative_count))
	return {
		"mean": _canonical_float(total / float(values.size())),
		"median": _canonical_float(median),
		"min": _canonical_float(sorted_values[0]),
		"max": _canonical_float(sorted_values[-1]),
		"positive_count": positive_count,
		"zero_count": zero_count,
		"negative_count": negative_count,
		"dominant_direction": dominant,
		"dominant_fraction": _canonical_float(float(dominant_count) / float(values.size())),
	}


static func _dominant_direction(positive_count: int, zero_count: int, negative_count: int) -> String:
	var best := maxi(positive_count, maxi(zero_count, negative_count))
	var winners := 0
	if positive_count == best:
		winners += 1
	if zero_count == best:
		winners += 1
	if negative_count == best:
		winners += 1
	if winners != 1:
		return "MIXED"
	if positive_count == best:
		return "POSITIVE"
	if negative_count == best:
		return "NEGATIVE"
	return "ZERO"


static func _canonical_float(value: float) -> float:
	if not is_finite(value):
		return value
	if absf(value) <= 0.0000000000005:
		return 0.0
	return value


static func _format_float(value: float) -> String:
	return ("%.12f" % _canonical_float(value))


static func _is_valid_seed_hash(value: String) -> bool:
	if value.length() != 64:
		return false
	for byte_value in value.to_ascii_buffer():
		var is_digit := byte_value >= 48 and byte_value <= 57
		var is_lower_hex := byte_value >= 97 and byte_value <= 102
		if not is_digit and not is_lower_hex:
			return false
	return true


static func _failure(reason: String, replicate_index: int = -1, detail: String = "") -> Dictionary:
	var result := {"success": false, "reason": reason}
	if replicate_index >= 0:
		result["replicate_index"] = replicate_index
	if not detail.is_empty():
		result["detail"] = detail
	return result
