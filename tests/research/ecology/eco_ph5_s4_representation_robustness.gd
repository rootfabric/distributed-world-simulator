extends SceneTree

const Representation = preload("res://scripts/research/ecology/plant_multiscale_representation_v1.gd")
var assertions := 0

func _init() -> void:
	var description := _description(128, 256)
	var truth_snapshot := JSON.stringify(description)

	# Invalid projection inputs fail closed to the cheapest non-individual representation.
	_assert(Representation.select_tier(NAN) == Representation.TIER_4_POPULATION_ONLY)
	_assert(Representation.select_tier(INF) == Representation.TIER_4_POPULATION_ONLY)
	_assert(Representation.select_tier(-INF) == Representation.TIER_4_POPULATION_ONLY)
	_assert(Representation.select_tier(-1.0) == Representation.TIER_4_POPULATION_ONLY)

	# Hysteresis keeps a stable tier during threshold noise and changes only after leaving the expanded band.
	var tier := Representation.TIER_2_CANOPY
	for index in range(1000):
		var px := 96.0 + (-1.0 if index % 2 == 0 else 1.0)
		tier = Representation.select_tier_hysteretic(px, tier)
		_assert(tier == Representation.TIER_2_CANOPY)
	_assert(Representation.select_tier_hysteretic(120.0, Representation.TIER_2_CANOPY) == Representation.TIER_1_REDUCED)
	_assert(Representation.select_tier_hysteretic(20.0, Representation.TIER_2_CANOPY) == Representation.TIER_3_IMPOSTOR)

	# Dematerialize/rematerialize is deterministic and leaves ecology truth untouched.
	var full_before := Representation.build(description, Representation.TIER_0_FULL)
	var population := Representation.build(description, Representation.TIER_4_POPULATION_ONLY)
	var full_after := Representation.build(description, Representation.TIER_0_FULL)
	_assert(String(full_before["representation_hash"]) == String(full_after["representation_hash"]))
	_assert(String(full_before["ecological_truth_hash"]) == String(population["ecological_truth_hash"]))
	_assert(JSON.stringify(description) == truth_snapshot)

	# Empty geometry is legal ecological truth; no representation invents individual primitives.
	var empty := _description(0, 0)
	for current_tier in Representation.TIER_ORDER:
		var built := Representation.build(empty, current_tier)
		_assert(bool(built.get("success", false)))
		if current_tier in [Representation.TIER_0_FULL, Representation.TIER_1_REDUCED]:
			_assert(int(built["branch_primitive_count"]) == 0)
			_assert(int(built["foliage_instance_count"]) == 0)

	# Invalid source descriptions are rejected without partial representation output.
	var invalid_hash := description.duplicate(true)
	invalid_hash["source_graph_hash"] = "bad"
	_assert(not bool(Representation.build(invalid_hash, Representation.TIER_0_FULL).get("success", false)))
	var invalid_hex_hash := description.duplicate(true)
	invalid_hex_hash["source_graph_hash"] = "z".repeat(64)
	_assert(not bool(Representation.build(invalid_hex_hash, Representation.TIER_0_FULL).get("success", false)))
	var invalid_render_hex := description.duplicate(true)
	invalid_render_hex["render_description_hash"] = "_".repeat(64)
	_assert(not bool(Representation.build(invalid_render_hex, Representation.TIER_0_FULL).get("success", false)))
	var uppercase_hash := description.duplicate(true)
	uppercase_hash["source_graph_hash"] = String(description["source_graph_hash"]).to_upper()
	_assert(bool(Representation.build(uppercase_hash, Representation.TIER_0_FULL).get("success", false)))
	var invalid_arrays := description.duplicate(true)
	invalid_arrays["branches"] = {"not": "array"}
	_assert(not bool(Representation.build(invalid_arrays, Representation.TIER_0_FULL).get("success", false)))
	_assert(not bool(Representation.build(description, "TIER_99_UNKNOWN").get("success", false)))

	# Repeated rebuild and broad deterministic tier churn remain stable.
	var digest_tokens := PackedStringArray()
	var previous := Representation.TIER_4_POPULATION_ONLY
	for index in range(2000):
		var px := absf(sin(float(index) * 0.173)) * 420.0
		previous = Representation.select_tier_hysteretic(px, previous)
		var built := Representation.build(description, previous)
		_assert(bool(built.get("success", false)))
		_assert(String(built["ecological_truth_hash"]) == String(description["source_graph_hash"]))
		digest_tokens.append("%d|%s|%s" % [index, previous, String(built["representation_hash"])])
	var digest_a := "\n".join(digest_tokens).sha256_text()
	var digest_b := _churn_digest(description)
	_assert(digest_a == digest_b)
	_assert(JSON.stringify(description) == truth_snapshot)

	print("ECO.PH5-S4 Representation Robustness: PASS (%d assertions) digest=%s" % [assertions, digest_a])
	quit(0)

func _churn_digest(description: Dictionary) -> String:
	var tokens := PackedStringArray()
	var previous := Representation.TIER_4_POPULATION_ONLY
	for index in range(2000):
		var px := absf(sin(float(index) * 0.173)) * 420.0
		previous = Representation.select_tier_hysteretic(px, previous)
		var built := Representation.build(description, previous)
		tokens.append("%d|%s|%s" % [index, previous, String(built["representation_hash"])])
	return "\n".join(tokens).sha256_text()

func _description(branch_count: int, foliage_count: int) -> Dictionary:
	var branches: Array = []
	var foliage: Array = []
	for index in range(branch_count):
		branches.append({"segment_id": "s%05d" % index})
	for index in range(foliage_count):
		foliage.append({"anchor_id": "l%05d" % index})
	return {
		"source_graph_hash": "robust-growth-truth".sha256_text(),
		"render_description_hash": "robust-render-truth".sha256_text(),
		"development_traits_checksum": "robust-traits".sha256_text(),
		"individual_seed": 1701,
		"branches": branches,
		"foliage_anchors": foliage,
		"canopy": {"center": [0.0, 1000000.0, 0.0], "radius_xz_m": 0.000001, "height_m": 2000000.0},
		"bounds": {"height_m": 2000000.0, "radius_xz_m": 1000000.0},
	}

func _assert(condition: bool) -> void:
	assert(condition)
	assertions += 1
