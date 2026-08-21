extends SceneTree

const Probes = preload("res://scripts/research/ecology/plant_render_description_probes_v1.gd")
const RendererProfile = preload("res://scripts/research/ecology/plant_renderer_profile_v1.gd")
const Materializer3D = preload("res://scripts/research/ecology/plant_3d_materializer_v1.gd")

const PROFILE_IDS := ["BRANCH_TUBES", "BRANCH_LEAF_INSTANCED", "FULL_PROCEDURAL"]
var assertions := 0

func _init() -> void:
	var results := Probes.run_all()
	var geometry_hashes := {}
	for environment_name in Probes.ENVIRONMENT_ORDER:
		var item: Dictionary = results[environment_name]
		var graph: Dictionary = item["growth_graph"]
		var description: Dictionary = item["render_description"]
		var graph_snapshot := JSON.stringify(graph)
		for profile_id in PROFILE_IDS:
			var profile := RendererProfile.create(profile_id)
			var built := Materializer3D.build(description, profile)
			_assert(not built.is_empty())
			_assert(bool(built["derived_representation"]))
			_assert(String(built["source_graph_hash"]) == String(graph["graph_hash"]))
			_assert(String(built["render_description_hash"]) == String(description["render_description_hash"]))
			_assert(String(built["profile_id"]) == profile_id)
			_assert(String(built["geometry_hash"]).length() == 64)
			_assert(int(built["branch_count"]) > 0)
			_assert(int(built["branch_sides"]) == int(profile["branch_sides"]))
			_assert(int(built["branch_vertex_count"]) == int(built["branch_count"]) * int(built["branch_sides"]) * 6)
			_assert(int(built["branch_triangle_count"]) * 3 == int(built["branch_vertex_count"]))
			var mesh: ArrayMesh = built["branch_mesh"]
			_assert(mesh != null)
			_assert(mesh.get_surface_count() == 1)
			_assert(mesh.get_aabb().size.y > 0.0)
			if profile_id == "BRANCH_TUBES":
				_assert(int(built["foliage_instance_count"]) == 0)
				_assert(built["foliage_multimesh"] == null)
			else:
				_assert(int(built["foliage_instance_count"]) > 0)
				var multimesh: MultiMesh = built["foliage_multimesh"]
				_assert(multimesh != null)
				_assert(multimesh.instance_count == int(built["foliage_instance_count"]))
				_assert(multimesh.mesh is QuadMesh)
			var rebuilt := Materializer3D.build(description, profile)
			_assert(String(rebuilt["geometry_hash"]) == String(built["geometry_hash"]))
			geometry_hashes[String(built["geometry_hash"])] = true
			_assert(JSON.stringify(graph) == graph_snapshot)
	_assert(geometry_hashes.size() >= 9)

	var reference: Dictionary = results["REFERENCE"]
	var description: Dictionary = reference["render_description"]
	var branch_leaf := Materializer3D.build(description, RendererProfile.create("BRANCH_LEAF_INSTANCED"))
	var full := Materializer3D.build(description, RendererProfile.create("FULL_PROCEDURAL"))
	_assert(String(branch_leaf["geometry_hash"]) != String(full["geometry_hash"]))
	print("ECO.PH5-S2 reference_branch_leaf_geometry_hash=%s full_geometry_hash=%s" % [String(branch_leaf["geometry_hash"]), String(full["geometry_hash"])])
	print("ECO.PH5-S2 3D Tapered Branch Tubes + Instanced Foliage: PASS (%d assertions)" % assertions)
	quit(0)

func _assert(condition: bool) -> void:
	assert(condition)
	assertions += 1
