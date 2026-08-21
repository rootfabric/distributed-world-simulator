extends SceneTree

const Representation = preload("res://scripts/research/ecology/plant_multiscale_representation_v1.gd")
var assertions := 0

func _init() -> void:
	var description := _description()
	var source_snapshot := JSON.stringify(description)
	var previous_cost := 1 << 30
	var hashes := {}
	for tier in Representation.TIER_ORDER:
		var built := Representation.build(description, tier)
		_assert(bool(built.get("success", false)))
		_assert(String(built["ecological_truth_hash"]) == String(description["source_graph_hash"]))
		_assert(String(built["render_description_hash"]) == String(description["render_description_hash"]))
		_assert(String(built["representation_hash"]).length() == 64)
		_assert(int(built["cost_units"]) < previous_cost)
		_assert(JSON.stringify(description) == source_snapshot)
		previous_cost = int(built["cost_units"])
		hashes[String(built["representation_hash"])] = true
	_assert(hashes.size() == 5)
	_assert(int(Representation.build(description, Representation.TIER_0_FULL)["branch_primitive_count"]) == 20)
	_assert(int(Representation.build(description, Representation.TIER_1_REDUCED)["branch_primitive_count"]) == 7)
	_assert(int(Representation.build(description, Representation.TIER_2_CANOPY)["canopy_primitive_count"]) == 1)
	_assert(int(Representation.build(description, Representation.TIER_3_IMPOSTOR)["impostor_count"]) == 1)
	var population := Representation.build(description, Representation.TIER_4_POPULATION_ONLY)
	_assert(not bool(population["individual_materialized"]))
	_assert(bool(population["population_projection_required"]))
	_assert(int(population["branch_primitive_count"]) == 0)
	_assert(int(population["foliage_instance_count"]) == 0)
	_assert(Representation.select_tier(300.0) == Representation.TIER_0_FULL)
	_assert(Representation.select_tier(120.0) == Representation.TIER_1_REDUCED)
	_assert(Representation.select_tier(40.0) == Representation.TIER_2_CANOPY)
	_assert(Representation.select_tier(8.0) == Representation.TIER_3_IMPOSTOR)
	_assert(Representation.select_tier(1.0) == Representation.TIER_4_POPULATION_ONLY)
	for tier in Representation.TIER_ORDER:
		var a := Representation.build(description, tier)
		var b := Representation.build(description, tier)
		_assert(String(a["representation_hash"]) == String(b["representation_hash"]))
	print("ECO.PH5-S3 Multi-scale Representation: PASS (%d assertions)" % assertions)
	quit(0)

func _description() -> Dictionary:
	var branches: Array = []
	var foliage: Array = []
	for index in range(20):
		branches.append({"segment_id": "s%02d" % index})
	for index in range(40):
		foliage.append({"anchor_id": "l%02d" % index})
	return {
		"source_graph_hash": "growth-truth".sha256_text(),
		"render_description_hash": "render-truth".sha256_text(),
		"development_traits_checksum": "traits".sha256_text(),
		"individual_seed": 731,
		"branches": branches,
		"foliage_anchors": foliage,
		"canopy": {"center": [0.0, 2.0, 0.0], "radius_xz_m": 1.5, "height_m": 2.6},
		"bounds": {"height_m": 4.2, "radius_xz_m": 1.8},
	}

func _assert(condition: bool) -> void:
	assert(condition)
	assertions += 1
