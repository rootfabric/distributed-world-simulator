extends SceneTree

const SelectiveFactory = preload("res://scripts/characters/equipment/selective_garment_scene_factory.gd")
const SurfaceFitFactory = preload("res://scripts/characters/equipment/garment_surface_fit_scene_factory.gd")
const MALE_PEASANT_PATH := "res://assets/external/quaternius/modular_outfits_fantasy/Modular Character Outfits - Fantasy[Standard]/Exports/glTF (Godot-Unreal)/Outfits/Male_Peasant.gltf"
const LOWER_GROW_M := 0.010
const FEET_GROW_M := 0.008

var failures: Array[String] = []
var assertions := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var loaded = load(MALE_PEASANT_PATH)
	_assert(loaded is PackedScene, "CH8C surface-fit source scene missing")
	if not loaded is PackedScene:
		_finish()
		return
	var source_scene := loaded as PackedScene

	var lower_selected: Dictionary = SelectiveFactory.create(source_scene, ["Male_Peasant_Legs"])
	_assert(bool(lower_selected.get("success", false)), "CH8C lower selective scene failed")
	var lower_scene = lower_selected.get("details", {}).get("scene")
	_assert(lower_scene is PackedScene, "CH8C lower selective scene was not packed")
	if lower_scene is PackedScene:
		var lower_fit: Dictionary = SurfaceFitFactory.create(lower_scene as PackedScene, LOWER_GROW_M)
		_assert(bool(lower_fit.get("success", false)), "CH8C lower surface fit failed")
		_assert(not bool(lower_fit.get("details", {}).get("mutates_source_scene", true)), "CH8C lower surface fit claims source mutation")
		var fitted_lower = lower_fit.get("details", {}).get("scene")
		_assert(fitted_lower is PackedScene, "CH8C fitted lower was not packed")
		if fitted_lower is PackedScene:
			_assert(_scene_has_grow(fitted_lower as PackedScene, "Male_Peasant_Legs", LOWER_GROW_M), "CH8C fitted lower lacks expected grow")
		_assert(not _scene_has_any_grow(lower_scene as PackedScene), "CH8C fitting lower mutated selected source material")

	var feet_selected: Dictionary = SelectiveFactory.create(source_scene, ["Male_Peasant_Feet"])
	_assert(bool(feet_selected.get("success", false)), "CH8C feet selective scene failed")
	var feet_scene = feet_selected.get("details", {}).get("scene")
	_assert(feet_scene is PackedScene, "CH8C feet selective scene was not packed")
	if feet_scene is PackedScene:
		var feet_fit: Dictionary = SurfaceFitFactory.create(feet_scene as PackedScene, FEET_GROW_M)
		_assert(bool(feet_fit.get("success", false)), "CH8C feet surface fit failed")
		var fitted_feet = feet_fit.get("details", {}).get("scene")
		_assert(fitted_feet is PackedScene, "CH8C fitted feet was not packed")
		if fitted_feet is PackedScene:
			_assert(_scene_has_grow(fitted_feet as PackedScene, "Male_Peasant_Feet", FEET_GROW_M), "CH8C fitted feet lacks expected grow")
		_assert(not _scene_has_any_grow(feet_scene as PackedScene), "CH8C fitting feet mutated selected source material")

	var invalid_zero: Dictionary = SurfaceFitFactory.create(source_scene, 0.0)
	_assert(not bool(invalid_zero.get("success", true)), "CH8C surface fit accepted zero grow")
	_assert(String(invalid_zero.get("code", "")) == "INVALID_GARMENT_GROW_AMOUNT", "CH8C zero grow returned wrong error")

	var invalid_large: Dictionary = SurfaceFitFactory.create(source_scene, 0.10)
	_assert(not bool(invalid_large.get("success", true)), "CH8C surface fit accepted excessive grow")
	_assert(String(invalid_large.get("code", "")) == "INVALID_GARMENT_GROW_AMOUNT", "CH8C excessive grow returned wrong error")

	_finish()


func _scene_has_grow(scene: PackedScene, mesh_name: String, expected_grow: float) -> bool:
	var instance = scene.instantiate()
	if not instance is Node:
		return false
	var root_node := instance as Node
	var target := _find_mesh(root_node, mesh_name)
	var result := false
	if target != null and target.mesh != null:
		for surface_index in range(target.mesh.get_surface_count()):
			var material: Material = target.get_surface_override_material(surface_index)
			if material == null:
				material = target.mesh.surface_get_material(surface_index)
			if material is BaseMaterial3D:
				var base := material as BaseMaterial3D
				if base.is_grow_enabled() and is_equal_approx(base.get_grow(), expected_grow):
					result = true
				else:
					result = false
					break
	root_node.free()
	return result


func _scene_has_any_grow(scene: PackedScene) -> bool:
	var instance = scene.instantiate()
	if not instance is Node:
		return false
	var root_node := instance as Node
	var meshes: Array[MeshInstance3D] = []
	_collect_meshes(root_node, meshes)
	var result := false
	for mesh in meshes:
		if mesh.mesh == null:
			continue
		for surface_index in range(mesh.mesh.get_surface_count()):
			var material: Material = mesh.get_surface_override_material(surface_index)
			if material == null:
				material = mesh.mesh.surface_get_material(surface_index)
			if material is BaseMaterial3D and (material as BaseMaterial3D).is_grow_enabled():
				result = true
				break
		if result:
			break
	root_node.free()
	return result


func _find_mesh(root_node: Node, target_name: String) -> MeshInstance3D:
	if root_node is MeshInstance3D and String(root_node.name) == target_name:
		return root_node as MeshInstance3D
	for child in root_node.get_children():
		var found := _find_mesh(child, target_name)
		if found != null:
			return found
	return null


func _collect_meshes(root_node: Node, output: Array[MeshInstance3D]) -> void:
	if root_node is MeshInstance3D:
		output.append(root_node as MeshInstance3D)
	for child in root_node.get_children():
		_collect_meshes(child, output)


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("CH8C garment surface-fit scene factory: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("CH8C garment surface-fit scene factory: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)
