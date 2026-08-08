extends SceneTree

const OUTFIT_ROOT := "res://assets/external/quaternius/modular_outfits_fantasy/Modular Character Outfits - Fantasy[Standard]/Exports/glTF (Godot-Unreal)/Outfits"

var scene_files: Array[String] = []
var inspected_scenes := 0
var inspected_meshes := 0
var category_counts: Dictionary = {}


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_collect_scene_files(OUTFIT_ROOT, scene_files)
	scene_files.sort()
	print("CH8 Quaternius layered-part probe: root=%s" % OUTFIT_ROOT)
	print("CH8 Quaternius layered-part probe: scene_files=%d" % scene_files.size())
	if scene_files.is_empty():
		push_error("CH8 layered-part probe found no outfit glTF scenes")
		quit(2)
		return

	for scene_path in scene_files:
		_inspect_scene(scene_path)

	var category_names: Array[String] = []
	for raw_category in category_counts.keys():
		category_names.append(String(raw_category))
	category_names.sort()
	for category in category_names:
		print("CH8 layered-part category: %s=%d" % [category, int(category_counts[category])])
	print("CH8 Quaternius layered-part probe: inspected_scenes=%d inspected_meshes=%d" % [inspected_scenes, inspected_meshes])
	print("CH8 Quaternius layered-part probe: PASS")
	quit(0)


func _inspect_scene(scene_path: String) -> void:
	if not ResourceLoader.exists(scene_path):
		print("CH8 layered-part scene skipped missing=%s" % scene_path)
		return
	var packed = load(scene_path)
	if not packed is PackedScene:
		print("CH8 layered-part scene skipped non_packed=%s" % scene_path)
		return
	var instance = (packed as PackedScene).instantiate()
	if not instance is Node:
		print("CH8 layered-part scene skipped instantiate_failed=%s" % scene_path)
		return

	inspected_scenes += 1
	var skeletons: Array[Skeleton3D] = []
	var meshes: Array[MeshInstance3D] = []
	_collect_skeletons(instance as Node, skeletons)
	_collect_meshes(instance as Node, meshes)
	var bone_counts: Array[int] = []
	for skeleton in skeletons:
		bone_counts.append(skeleton.get_bone_count())
	print("CH8 layered-part scene: file=%s skeletons=%d bones=%s meshes=%d" % [
		scene_path.get_file(),
		skeletons.size(),
		str(bone_counts),
		meshes.size(),
	])

	for mesh in meshes:
		inspected_meshes += 1
		var category := _classify_mesh(mesh)
		category_counts[category] = int(category_counts.get(category, 0)) + 1
		var material_names: Array[String] = []
		if mesh.mesh != null:
			for surface_index in range(mesh.mesh.get_surface_count()):
				var material: Material = mesh.get_surface_override_material(surface_index)
				if material == null:
					material = mesh.mesh.surface_get_material(surface_index)
				var material_name := ""
				if material != null:
					material_name = String(material.resource_name)
				if material_name.is_empty():
					material_name = mesh.mesh.surface_get_name(surface_index)
				material_names.append(material_name)
		print("CH8 layered-part mesh: scene=%s name=%s category=%s skinned=%s surfaces=%d materials=%s aabb_pos=%s aabb_size=%s" % [
			scene_path.get_file(),
			String(mesh.name),
			category,
			mesh.skin != null or not mesh.skeleton.is_empty(),
			mesh.mesh.get_surface_count() if mesh.mesh != null else 0,
			str(material_names),
			str(mesh.get_aabb().position),
			str(mesh.get_aabb().size),
		])

	(instance as Node).free()


func _classify_mesh(mesh: MeshInstance3D) -> String:
	var text := String(mesh.name).to_lower()
	if mesh.mesh != null:
		for surface_index in range(mesh.mesh.get_surface_count()):
			text += " " + mesh.mesh.surface_get_name(surface_index).to_lower()
			var material: Material = mesh.get_surface_override_material(surface_index)
			if material == null:
				material = mesh.mesh.surface_get_material(surface_index)
			if material != null:
				text += " " + String(material.resource_name).to_lower()

	if _contains_any(text, ["boot", "shoe", "feet", "foot", "sandal"]):
		return "FEET"
	if _contains_any(text, ["trouser", "pants", "pant", "skirt", "lower", "legwear", "legs"]):
		return "LOWER"
	if _contains_any(text, ["shirt", "tunic", "jacket", "coat", "robe", "upper", "torso", "chest", "top", "vest"]):
		return "UPPER"
	if _contains_any(text, ["sleeve", "glove", "arm", "hand"]):
		return "ARMS_HANDS"
	if _contains_any(text, ["belt", "pouch", "bag", "cape", "hood", "hat", "collar", "accessory"]):
		return "ACCESSORY"
	return "UNKNOWN"


func _contains_any(text: String, tokens: Array) -> bool:
	for raw_token in tokens:
		if text.contains(String(raw_token)):
			return true
	return false


func _collect_scene_files(root_path: String, output: Array[String]) -> void:
	var directory := DirAccess.open(root_path)
	if directory == null:
		return
	directory.list_dir_begin()
	while true:
		var entry := directory.get_next()
		if entry.is_empty():
			break
		if entry.begins_with("."):
			continue
		var path := root_path.path_join(entry)
		if directory.current_is_dir():
			_collect_scene_files(path, output)
		elif entry.to_lower().ends_with(".gltf") or entry.to_lower().ends_with(".glb"):
			output.append(path)
	directory.list_dir_end()


func _collect_skeletons(root_node: Node, output: Array[Skeleton3D]) -> void:
	if root_node is Skeleton3D:
		output.append(root_node as Skeleton3D)
	for child in root_node.get_children():
		_collect_skeletons(child, output)


func _collect_meshes(root_node: Node, output: Array[MeshInstance3D]) -> void:
	if root_node is MeshInstance3D:
		output.append(root_node as MeshInstance3D)
	for child in root_node.get_children():
		_collect_meshes(child, output)
