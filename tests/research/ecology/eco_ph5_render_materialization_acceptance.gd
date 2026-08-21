extends SceneTree

const SourceProbes = preload("res://scripts/research/ecology/plant_environment_coupled_development_probes_v1.gd")
const RendererProfile = preload("res://scripts/research/ecology/plant_renderer_profile_v1.gd")
const RenderDescription = preload("res://scripts/research/ecology/plant_render_description_v1.gd")
const Probes = preload("res://scripts/research/ecology/plant_render_description_probes_v1.gd")

var assertions := 0

func _init() -> void:
	var profiles := RendererProfile.create_all()
	_assert(profiles.size() == RendererProfile.PROFILE_ORDER.size())
	var profile_hashes := {}
	for profile_id in RendererProfile.PROFILE_ORDER:
		var profile: Dictionary = profiles[profile_id]
		_assert(bool(RendererProfile.validate(profile).get("success", false)))
		_assert(String(profile["profile_id"]) == profile_id)
		_assert(not profile_hashes.has(String(profile["profile_hash"])))
		profile_hashes[String(profile["profile_hash"])] = true

	var source := SourceProbes.run_all()
	var results := Probes.run_all()
	_assert(source.size() == SourceProbes.PROBE_ORDER.size())
	_assert(results.size() == SourceProbes.PROBE_ORDER.size())
	var description_hashes := {}
	for environment_name in SourceProbes.PROBE_ORDER:
		var source_graph: Dictionary = source[environment_name]["growth_graph"]
		var source_snapshot := JSON.stringify(source_graph)
		var item: Dictionary = results[environment_name]
		var graph: Dictionary = item["growth_graph"]
		var description: Dictionary = item["render_description"]
		_assert(String(graph["graph_hash"]) == String(source_graph["graph_hash"]))
		_assert(JSON.stringify(graph) == source_snapshot)
		_assert(bool(RenderDescription.validate(description).get("success", false)))
		_assert(bool(description["derived_representation"]))
		_assert(String(description["source_graph_hash"]) == String(source_graph["graph_hash"]))
		_assert(Array(description["branches"]).size() == Array(source_graph["segments"]).size())
		_assert(Array(description["foliage_anchors"]).size() > 0)
		_assert(float(description["canopy"]["radius_xz_m"]) > 0.0)
		_assert(float(description["canopy"]["height_m"]) > 0.0)
		_assert(not description.has("tree_type"))
		_assert(not description.has("bush_type"))
		_assert(not description.has("grass_type"))
		var rebuilt := RenderDescription.build(source_graph)
		_assert(String(rebuilt["render_description_hash"]) == String(description["render_description_hash"]))
		description_hashes[String(description["render_description_hash"])] = true
		for branch in Array(description["branches"]):
			_assert(float(branch["radius_start_m"]) > 0.0)
			_assert(float(branch["radius_end_m"]) > 0.0)
			_assert(float(branch["radius_start_m"]) >= float(branch["radius_end_m"]))
		var materialization_hashes := {}
		for profile_id in RendererProfile.PROFILE_ORDER:
			var profile: Dictionary = profiles[profile_id]
			var materialization: Dictionary = item["materializations"][profile_id]
			_assert(not materialization.is_empty())
			_assert(String(materialization["source_graph_hash"]) == String(source_graph["graph_hash"]))
			_assert(String(materialization["render_description_hash"]) == String(description["render_description_hash"]))
			_assert(String(materialization["profile_id"]) == profile_id)
			_assert(String(materialization["profile_hash"]) == String(profile["profile_hash"]))
			_assert(not materialization_hashes.has(String(materialization["materialization_hash"])))
			materialization_hashes[String(materialization["materialization_hash"])] = true
		_assert(int(item["materializations"]["DEBUG_SKELETON"]["foliage_instance_count"]) == 0)
		_assert(int(item["materializations"]["BRANCH_TUBES"]["branch_sides"]) == 6)
		_assert(int(item["materializations"]["BRANCH_LEAF_INSTANCED"]["foliage_instance_count"]) > 0)
		_assert(int(item["materializations"]["CANOPY_APPROXIMATION"]["canopy_primitive_count"]) == 1)
		_assert(int(item["materializations"]["FULL_PROCEDURAL"]["foliage_instance_count"]) == Array(description["foliage_anchors"]).size())
		_assert(int(item["materializations"]["FULL_PROCEDURAL"]["branch_primitive_count"]) == Array(description["branches"]).size())
		_assert(int(item["materializations"]["IMPOSTOR_BILLBOARD"]["impostor_count"]) == 1)
		_assert(int(item["materializations"]["IMPOSTOR_BILLBOARD"]["branch_primitive_count"]) == 0)
		_assert(JSON.stringify(source_graph) == source_snapshot)
	_assert(description_hashes.size() >= 3)

	var reference: Dictionary = results["REFERENCE"]
	var reference_description: Dictionary = reference["render_description"]
	var reference_full: Dictionary = reference["materializations"]["FULL_PROCEDURAL"]
	var matrix_hash := Probes.compute_profile_matrix_hash(results)
	_assert(matrix_hash.length() == 64)
	print("ECO.PH5 reference_description_hash=%s profile_matrix_hash=%s full_materialization_hash=%s" % [String(reference_description["render_description_hash"]), matrix_hash, String(reference_full["materialization_hash"])])
	print("ECO.PH5 Extensible Procedural Visual Materialization: PASS (%d assertions)" % assertions)
	quit(0)

func _assert(condition: bool) -> void:
	assert(condition)
	assertions += 1
