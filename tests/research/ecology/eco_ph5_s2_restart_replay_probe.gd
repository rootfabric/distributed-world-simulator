extends SceneTree

const Probes = preload("res://scripts/research/ecology/plant_render_description_probes_v1.gd")
const RendererProfile = preload("res://scripts/research/ecology/plant_renderer_profile_v1.gd")
const Materializer3D = preload("res://scripts/research/ecology/plant_3d_materializer_v1.gd")

var assertions := 0

func _init() -> void:
	var results := Probes.run_all()
	var reference: Dictionary = results["REFERENCE"]
	var description: Dictionary = reference["render_description"]
	var branch_leaf := Materializer3D.build(description, RendererProfile.create("BRANCH_LEAF_INSTANCED"))
	var full := Materializer3D.build(description, RendererProfile.create("FULL_PROCEDURAL"))
	_assert(not branch_leaf.is_empty())
	_assert(not full.is_empty())
	_assert(String(branch_leaf["source_graph_hash"]) == String(reference["growth_graph"]["graph_hash"]))
	_assert(String(branch_leaf["geometry_hash"]).length() == 64)
	_assert(String(full["geometry_hash"]).length() == 64)
	print("ECO.PH5-S2 Restart Replay: PASS (%d assertions) branch_leaf=%s full=%s" % [assertions, String(branch_leaf["geometry_hash"]), String(full["geometry_hash"])])
	quit(0)

func _assert(condition: bool) -> void:
	assert(condition)
	assertions += 1
