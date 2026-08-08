extends SceneTree

const SelectiveFactory = preload("res://scripts/characters/equipment/selective_garment_scene_factory.gd")
const InflationFactory = preload("res://scripts/characters/equipment/garment_vertex_inflation_scene_factory.gd")
const MALE_PEASANT_PATH := "res://assets/external/quaternius/modular_outfits_fantasy/Modular Character Outfits - Fantasy[Standard]/Exports/glTF (Godot-Unreal)/Outfits/Male_Peasant.gltf"

const LOWER_PROFILE := [
	{"t": 0.00, "offset_m": 0.0015},
	{"t": 0.18, "offset_m": 0.0040},
	{"t": 0.45, "offset_m": 0.0060},
	{"t": 0.72, "offset_m": 0.0050},
	{"t": 1.00, "offset_m": 0.0015},
]
const FEET_PROFILE := [
	{"t": 0.00, "offset_m": 0.0015},
	{"t": 0.35, "offset_m": 0.0025},
	{"t": 0.65, "offset_m": 0.0045},
	{"t": 1.00, "offset_m": 0.0070},
]

var failures: Array[String] = []
var assertions := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var loaded = load(MALE_PEASANT_PATH)
	_assert(loaded is PackedScene, "CH8C vertex inflation Male_Peasant source missing")
	if not loaded is PackedScene:
		_finish()
		return
	var source_scene := loaded as PackedScene

	_run_case(source_scene, "Male_Peasant_Legs", LOWER_PROFILE, 0.0060)
	_run_case(source_scene, "Male_Peasant_Feet", FEET_PROFILE, 0.0070)
	_finish()


func _run_case(source_scene: PackedScene, mesh_name: String, profile: Array, expected_max_offset: float) -> void:
	var selected: Dictionary = SelectiveFactory.create(source_scene, [mesh_name])
	_assert(bool(selected.get("success", false)), "CH8C vertex inflation selection failed for %s" % mesh_name)
	if not bool(selected.get("success", false)):
		return
	var base_scene = selected.get("details", {}).get("scene")
	_assert(base_scene is PackedScene, "CH8C vertex inflation base scene missing for %s" % mesh_name)
	if not base_scene is PackedScene:
		return

	var before = _snapshot_mesh(base_scene as PackedScene, mesh_name)
	_assert(bool(before.get("success", false)), "CH8C vertex inflation source snapshot failed for %s" % mesh_name)
	if not bool(before.get("success", false)):
		return

	var inflated_result: Dictionary = InflationFactory.create(base_scene as PackedScene, profile)
	_assert(bool(inflated_result.get("success", false)), "CH8C vertex inflation factory failed for %s: %s" % [mesh_name, JSON.stringify(inflated_result)])
	if not bool(inflated_result.get("success", false)):
		return
	var details: Dictionary = inflated_result.get("details", {})
	_assert(int(details.get("mesh_count", 0)) == 1, "CH8C vertex inflation expected one selected mesh for %s" % mesh_name)
	_assert(int(details.get("vertex_count", 0)) > 0, "CH8C vertex inflation reported no vertices for %s" % mesh_name)
	_assert(is_equal_approx(float(details.get("profile_max_offset_m", 0.0)), expected_max_offset), "CH8C vertex inflation configured max mismatch for %s" % mesh_name)
	_assert(float(details.get("max_offset_m", 0.0)) <= expected_max_offset + 0.000001, "CH8C vertex inflation observed max exceeded profile for %s" % mesh_name)
	_assert(float(details.get("max_offset_m", 0.0)) >= expected_max_offset * 0.90, "CH8C vertex inflation observed max missed profile peak too far for %s" % mesh_name)
	_assert(not bool(details.get("mutates_source_scene", true)), "CH8C vertex inflation claims source mutation for %s" % mesh_name)
	_assert(bool(details.get("preserves_skin_arrays", false)), "CH8C vertex inflation did not report skin preservation for %s" % mesh_name)

	var inflated_scene = details.get("scene")
	_assert(inflated_scene is PackedScene, "CH8C vertex inflation output scene missing for %s" % mesh_name)
	if not inflated_scene is PackedScene:
		return
	var after = _snapshot_mesh(inflated_scene as PackedScene, mesh_name)
	_assert(bool(after.get("success", false)), "CH8C vertex inflation output snapshot failed for %s" % mesh_name)
	if not bool(after.get("success", false)):
		return

	var original_again = _snapshot_mesh(base_scene as PackedScene, mesh_name)
	_assert(bool(original_again.get("success", false)), "CH8C vertex inflation source re-snapshot failed for %s" % mesh_name)
	if not bool(original_again.get("success", false)):
		return

	var before_vertices: PackedVector3Array = before.get("vertices", PackedVector3Array())
	var before_normals: PackedVector3Array = before.get("normals", PackedVector3Array())
	var after_vertices: PackedVector3Array = after.get("vertices", PackedVector3Array())
	var after_normals: PackedVector3Array = after.get("normals", PackedVector3Array())
	_assert(before_vertices.size() == after_vertices.size(), "CH8C vertex inflation vertex count changed for %s" % mesh_name)
	_assert(before_normals == after_normals, "CH8C vertex inflation normals changed for %s" % mesh_name)
	_assert(before.get("indices") == after.get("indices"), "CH8C vertex inflation indices changed for %s" % mesh_name)
	_assert(before.get("bones") == after.get("bones"), "CH8C vertex inflation bones changed for %s" % mesh_name)
	_assert(before.get("weights") == after.get("weights"), "CH8C vertex inflation weights changed for %s" % mesh_name)
	_assert(before_vertices == original_again.get("vertices"), "CH8C vertex inflation mutated source vertices for %s" % mesh_name)

	var min_y := INF
	var max_y := -INF
	for vertex in before_vertices:
		min_y = minf(min_y, vertex.y)
		max_y = maxf(max_y, vertex.y)
	var displacement_ok := true
	var outward_ok := true
	var observed_max := 0.0
	for vertex_index in range(before_vertices.size()):
		var t := clampf((before_vertices[vertex_index].y - min_y) / maxf(0.000001, max_y - min_y), 0.0, 1.0)
		var expected_offset := _sample_profile(profile, t)
		var delta := after_vertices[vertex_index] - before_vertices[vertex_index]
		observed_max = maxf(observed_max, delta.length())
		if not is_equal_approx(delta.length(), expected_offset):
			displacement_ok = false
		if delta.length() > 0.000001 and before_normals[vertex_index].length_squared() > 0.00000001:
			if delta.normalized().dot(before_normals[vertex_index].normalized()) < 0.999:
				outward_ok = false
	_assert(displacement_ok, "CH8C vertex inflation displacement profile mismatch for %s" % mesh_name)
	_assert(outward_ok, "CH8C vertex inflation did not move outward along normals for %s" % mesh_name)
	_assert(observed_max <= expected_max_offset + 0.000001, "CH8C vertex inflation observed displacement exceeded configured max for %s" % mesh_name)
	_assert(observed_max >= expected_max_offset * 0.90, "CH8C vertex inflation observed displacement did not reach configured profile closely enough for %s" % mesh_name)


func _snapshot_mesh(scene: PackedScene, mesh_name: String) -> Dictionary:
	var instance = scene.instantiate()
	if not instance is Node:
		return {"success": false}
	var mesh_instance := _find_mesh(instance as Node, mesh_name)
	if mesh_instance == null or not mesh_instance.mesh is ArrayMesh:
		(instance as Node).free()
		return {"success": false}
	var mesh := mesh_instance.mesh as ArrayMesh
	if mesh.get_surface_count() != 1:
		(instance as Node).free()
		return {"success": false}
	var arrays: Array = mesh.surface_get_arrays(0)
	var result := {
		"success": true,
		"vertices": (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).duplicate(),
		"normals": (arrays[Mesh.ARRAY_NORMAL] as PackedVector3Array).duplicate(),
		"indices": (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).duplicate(),
		"bones": (arrays[Mesh.ARRAY_BONES] as PackedInt32Array).duplicate(),
		"weights": (arrays[Mesh.ARRAY_WEIGHTS] as PackedFloat32Array).duplicate(),
	}
	(instance as Node).free()
	return result


func _find_mesh(root_node: Node, target_name: String) -> MeshInstance3D:
	if root_node is MeshInstance3D and String(root_node.name) == target_name:
		return root_node as MeshInstance3D
	for child in root_node.get_children():
		var found := _find_mesh(child, target_name)
		if found != null:
			return found
	return null


func _sample_profile(profile: Array, t: float) -> float:
	if t <= float(profile[0]["t"]):
		return float(profile[0]["offset_m"])
	for index in range(1, profile.size()):
		var right: Dictionary = profile[index]
		if t > float(right["t"]):
			continue
		var left: Dictionary = profile[index - 1]
		var span := float(right["t"]) - float(left["t"])
		var local_t := 0.0 if span <= 0.0 else clampf((t - float(left["t"])) / span, 0.0, 1.0)
		return lerpf(float(left["offset_m"]), float(right["offset_m"]), local_t)
	return float(profile[-1]["offset_m"])


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("CH8C Quaternius vertex inflation fit: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("CH8C Quaternius vertex inflation fit: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)
