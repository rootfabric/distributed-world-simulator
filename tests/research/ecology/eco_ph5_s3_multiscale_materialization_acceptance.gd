extends SceneTree

const RenderDescription = preload("res://scripts/research/ecology/plant_render_description_v1.gd")
const Representation = preload("res://scripts/research/ecology/plant_multiscale_representation_v1.gd")
const MultiscaleMaterializer = preload("res://scripts/research/ecology/plant_multiscale_materializer_v1.gd")
var assertions := 0

func _init() -> void:
	var description := _description(20, 40)
	var snapshot := JSON.stringify(description)
	var hashes := PackedStringArray()
	var previous_cost := 1000000000
	for tier in Representation.TIER_ORDER:
		var representation := Representation.build(description, tier)
		_assert(bool(representation["success"]))
		var built := MultiscaleMaterializer.build(description, representation)
		_assert(bool(built["success"]))
		_assert(String(built["ecological_truth_hash"]) == String(description["source_graph_hash"]))
		_assert(String(built["representation_hash"]) == String(representation["representation_hash"]))
		_assert(String(built["materialization_hash"]).length() == 64)
		_assert(int(representation["cost_units"]) < previous_cost)
		previous_cost = int(representation["cost_units"])
		_assert(int(built["branch_primitive_count"]) == int(representation["branch_primitive_count"]))
		_assert(int(built["foliage_instance_count"]) == int(representation["foliage_instance_count"]))
		_assert(int(built["far_primitive_count"]) == int(representation["canopy_primitive_count"]) + int(representation["impostor_count"]))
		if tier == Representation.TIER_0_FULL:
			_assert(built["branch_mesh"] is ArrayMesh)
			_assert(built["foliage_multimesh"] is MultiMesh)
		if tier == Representation.TIER_1_REDUCED:
			_assert(int(built["branch_primitive_count"]) == 7)
			_assert(int(built["foliage_instance_count"]) == 8)
		if tier == Representation.TIER_2_CANOPY:
			_assert(built["far_mesh"] is SphereMesh)
		if tier == Representation.TIER_3_IMPOSTOR:
			_assert(built["far_mesh"] is QuadMesh)
			_assert(bool(built["billboard"]))
		if tier == Representation.TIER_4_POPULATION_ONLY:
			_assert(not bool(built["individual_node_required"]))
			_assert(built["branch_mesh"] == null and built["foliage_multimesh"] == null and built["far_mesh"] == null)
		hashes.append(String(built["materialization_hash"]))
		var rebuilt := MultiscaleMaterializer.build(description, representation)
		_assert(String(rebuilt["materialization_hash"]) == String(built["materialization_hash"]))
	_assert(JSON.stringify(description) == snapshot)
	_assert(hashes.size() == 5)
	var matrix_hash := "|".join(hashes).sha256_text()
	print("ECO.PH5-S3 Multiscale Materialization: PASS (%d assertions) matrix_hash=%s" % [assertions, matrix_hash])
	quit(0)

func _description(branch_count: int, foliage_count: int) -> Dictionary:
	var branches: Array = []
	for index in range(branch_count):
		var y := float(index) * 0.1
		branches.append({
			"segment_id": "s%03d" % index,
			"parent_segment_id": "" if index == 0 else "s%03d" % (index - 1),
			"main_axis": index < 10,
			"axis_order": 0 if index < 10 else 1,
			"start": [0.0, y, 0.0],
			"end": [0.02 * float(index % 3), y + 0.1, 0.01 * float(index % 5)],
			"radius_start_m": 0.03,
			"radius_end_m": 0.02,
			"length_m": 0.1,
		})
	var foliage: Array = []
	for index in range(foliage_count):
		foliage.append({"anchor_id": "l%03d" % index, "segment_id": "s%03d" % (index % branch_count), "position": [0.1, 0.1 + 0.03 * index, 0.0], "size_m": 0.06, "azimuth_deg": float(index * 37 % 360), "bud": false})
	var result := {
		"schema": RenderDescription.SCHEMA,
		"version": RenderDescription.VERSION,
		"derived_representation": true,
		"source_graph_hash": "multiscale-materialization-growth".sha256_text(),
		"individual_seed": 4242,
		"development_traits_checksum": "multiscale-materialization-traits".sha256_text(),
		"branches": branches,
		"foliage_anchors": foliage,
		"canopy": {"center": [0.0, 1.0, 0.0], "radius_xz_m": 0.8, "height_m": 1.5, "base_y_m": 0.2},
		"bounds": {"height_m": 2.0, "radius_xz_m": 0.8},
	}
	result["render_description_hash"] = RenderDescription.compute_hash(result)
	return result

func _assert(condition: bool) -> void:
	assert(condition)
	assertions += 1
