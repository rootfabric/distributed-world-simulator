extends SceneTree

const Representation = preload("res://scripts/research/ecology/plant_multiscale_representation_v1.gd")
const FarMaterializer = preload("res://scripts/research/ecology/plant_far_representation_materializer_v1.gd")
var assertions := 0

func _init() -> void:
	var description := {
		"source_graph_hash": "far-growth".sha256_text(),
		"render_description_hash": "far-render".sha256_text(),
		"branches": [],
		"foliage_anchors": [],
		"canopy": {"center": [1.0, 3.0, -2.0], "radius_xz_m": 2.0, "height_m": 5.0},
		"bounds": {"height_m": 7.0, "radius_xz_m": 2.5},
	}
	var truth := String(description["source_graph_hash"])
	var canopy := FarMaterializer.build(Representation.build(description, Representation.TIER_2_CANOPY))
	var impostor := FarMaterializer.build(Representation.build(description, Representation.TIER_3_IMPOSTOR))
	var population := FarMaterializer.build(Representation.build(description, Representation.TIER_4_POPULATION_ONLY))
	_assert(bool(canopy["success"]) and canopy["mesh"] is SphereMesh)
	_assert(bool(impostor["success"]) and impostor["mesh"] is QuadMesh)
	_assert(bool(impostor["billboard"]))
	_assert(bool(population["success"]) and population["mesh"] == null)
	_assert(not bool(population["individual_node_required"]))
	_assert(int(population["primitive_count"]) == 0)
	for item in [canopy, impostor, population]:
		_assert(String(item["ecological_truth_hash"]) == truth)
		_assert(String(item["materialization_hash"]).length() == 64)
	var canopy_again := FarMaterializer.build(Representation.build(description, Representation.TIER_2_CANOPY))
	_assert(String(canopy_again["materialization_hash"]) == String(canopy["materialization_hash"]))
	print("ECO.PH5-S3 Far Canopy/Impostor Materialization: PASS (%d assertions) canopy=%s impostor=%s" % [assertions, String(canopy["materialization_hash"]), String(impostor["materialization_hash"])])
	quit(0)

func _assert(condition: bool) -> void:
	assert(condition)
	assertions += 1
