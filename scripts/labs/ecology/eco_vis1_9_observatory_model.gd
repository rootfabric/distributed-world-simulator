extends RefCounted

const STAGE := "ECO.VIS1.9"
const MODE := "EVOLUTION_OBSERVATORY"
const SERIES_WINDOW := 64

static func summarize(history: Array[Dictionary], selected_generation: int = -1) -> Dictionary:
	var points: Array[Dictionary] = []
	for point_variant in history:
		if typeof(point_variant) != TYPE_DICTIONARY:
			continue
		var point: Dictionary = Dictionary(point_variant)
		points.append({
			"generation": int(point.get("generation", 0)),
			"visual_count": int(point.get("visual_count", 0)),
			"birth_count": int(point.get("birth_count", 0)),
			"death_count": int(point.get("death_count", 0)),
			"mean_fitness": float(point.get("mean_fitness", 0.0)),
			"unique_genomes": int(point.get("unique_genomes", 0)),
			"alpha_count": int(point.get("alpha_count", 0)),
			"beta_count": int(point.get("beta_count", 0)),
		})
	while points.size() > SERIES_WINDOW:
		points.pop_front()

	var selected := {}
	if not points.is_empty():
		var target := selected_generation
		if target < 0:
			target = int(points.back().get("generation", 0))
		var best_distance := 2147483647
		for point in points:
			var distance := absi(int(point.get("generation", 0)) - target)
			if selected.is_empty() or distance < best_distance:
				selected = point.duplicate(true)
				best_distance = distance

	var ranges := {
		"visual_count": _range(points, "visual_count", true),
		"turnover": _dual_range(points, "birth_count", "death_count", true),
		"mean_fitness": _range(points, "mean_fitness", false),
		"unique_genomes": _range(points, "unique_genomes", true),
		"composition": _dual_range(points, "alpha_count", "beta_count", true),
	}
	return {
		"stage": STAGE,
		"mode": MODE,
		"point_count": points.size(),
		"points": points,
		"selected": selected,
		"ranges": ranges,
		"history_hash": compute_history_hash(points),
	}

static func compute_history_hash(points: Array[Dictionary]) -> String:
	var tokens := PackedStringArray([STAGE, MODE])
	for point in points:
		tokens.append("G%d|n=%d|b=%d|d=%d|f=%.9f|u=%d|a=%d|z=%d" % [
			int(point.get("generation", 0)),
			int(point.get("visual_count", 0)),
			int(point.get("birth_count", 0)),
			int(point.get("death_count", 0)),
			float(point.get("mean_fitness", 0.0)),
			int(point.get("unique_genomes", 0)),
			int(point.get("alpha_count", 0)),
			int(point.get("beta_count", 0)),
		])
	return "\n".join(tokens).sha256_text()

static func _range(points: Array[Dictionary], key: String, integral: bool) -> Dictionary:
	if points.is_empty():
		return {"min": 0.0, "max": 1.0}
	var minimum := INF
	var maximum := -INF
	for point in points:
		var value := float(point.get(key, 0.0))
		minimum = minf(minimum, value)
		maximum = maxf(maximum, value)
	if is_equal_approx(minimum, maximum):
		var padding := 1.0 if integral else 0.05
		minimum -= padding
		maximum += padding
	return {"min": minimum, "max": maximum}

static func _dual_range(points: Array[Dictionary], key_a: String, key_b: String, integral: bool) -> Dictionary:
	if points.is_empty():
		return {"min": 0.0, "max": 1.0}
	var minimum := INF
	var maximum := -INF
	for point in points:
		for key in [key_a, key_b]:
			var value := float(point.get(key, 0.0))
			minimum = minf(minimum, value)
			maximum = maxf(maximum, value)
	if is_equal_approx(minimum, maximum):
		var padding := 1.0 if integral else 0.05
		minimum -= padding
		maximum += padding
	return {"min": minimum, "max": maximum}
