extends SceneTree

const OUTFIT_ROOT := "res://assets/external/quaternius/modular_outfits_fantasy"
const BASE_ROOT := "res://assets/external/quaternius/base_characters"
const MAX_REPORT_CANDIDATES := 12


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	print("CH7.8 outfit probe: root=%s" % OUTFIT_ROOT)
	var outfit_files: Array[String] = []
	_collect_scene_files(OUTFIT_ROOT, outfit_files)
	if outfit_files.is_empty():
		push_error("CH7.8 outfit probe: no .gltf/.glb files found under %s" % OUTFIT_ROOT)
		print("CH7.8 outfit probe: extract Quaternius Modular Character Outfits - Fantasy [Standard] under the root above")
		quit(2)
		return

	var base_path := _find_best_base_scene()
	if base_path.is_empty():
		push_error("CH7.8 outfit probe: accepted Universal Base Characters asset root has no usable scene")
		quit(3)
		return
	var base_bones := _load_normalized_bones(base_path)
	if base_bones.is_empty():
		push_error("CH7.8 outfit probe: could not read base-character Skeleton3D from %s" % base_path)
		quit(4)
		return

	print("CH7.8 outfit probe: base=%s bones=%d" % [base_path, base_bones.size()])
	print("CH7.8 outfit probe: discovered_scene_files=%d" % outfit_files.size())

	var candidates: Array[Dictionary] = []
	for path in outfit_files:
		var report := _inspect_candidate(path, base_bones)
		if bool(report.get("rigged", false)):
			candidates.append(report)

	if candidates.is_empty():
		push_error("CH7.8 outfit probe: files exist but no rigged Skeleton3D candidate was found")
		quit(5)
		return

	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("score", 0)) > int(b.get("score", 0))
	)

	var report_count := mini(MAX_REPORT_CANDIDATES, candidates.size())
	for index in range(report_count):
		var candidate := candidates[index]
		print("CH7.8 outfit candidate %02d: %s" % [index + 1, JSON.stringify(candidate)])

	var best := candidates[0]
	print("CH7.8 outfit probe: RECOMMENDED=%s" % String(best.get("path", "")))
	print(
		"CH7.8 outfit probe: recommended matched_bones=%d base_overlap=%.3f garment_overlap=%.3f meshes=%d skinned_meshes=%d" % [
			int(best.get("matched_bones", 0)),
			float(best.get("base_overlap", 0.0)),
			float(best.get("garment_overlap", 0.0)),
			int(best.get("mesh_count", 0)),
			int(best.get("skinned_mesh_count", 0)),
		]
	)
	if float(best.get("base_overlap", 0.0)) < 0.60:
		push_error("CH7.8 outfit probe: best candidate has weak base-rig overlap; do not implement runtime garment binding yet")
		quit(6)
		return

	print("CH7.8 Quaternius outfit asset probe: PASS")
	quit(0)


func _inspect_candidate(path: String, base_bones: Dictionary) -> Dictionary:
	var packed = load(path)
	if not packed is PackedScene:
		return {"path": path, "rigged": false, "score": -100000}
	var instance = (packed as PackedScene).instantiate()
	if not instance is Node:
		return {"path": path, "rigged": false, "score": -100000}

	var skeleton := _find_first_skeleton(instance)
	if skeleton == null:
		instance.free()
		return {"path": path, "rigged": false, "score": -100000}

	var garment_bones: Dictionary = {}
	for index in range(skeleton.get_bone_count()):
		var normalized := _normalized_bone_name(skeleton.get_bone_name(index))
		if not normalized.is_empty():
			garment_bones[normalized] = true

	var matched := 0
	for normalized in garment_bones.keys():
		if base_bones.has(normalized):
			matched += 1

	var meshes: Array[MeshInstance3D] = []
	_collect_meshes(instance, meshes)
	var skinned_meshes := 0
	for mesh in meshes:
		if mesh.skin != null or not mesh.skeleton.is_empty():
			skinned_meshes += 1

	var base_overlap := float(matched) / float(maxi(1, base_bones.size()))
	var garment_overlap := float(matched) / float(maxi(1, garment_bones.size()))
	var normalized_path := path.to_lower()
	var score := matched * 4 + int(round(base_overlap * 100.0)) + int(round(garment_overlap * 100.0))
	if normalized_path.contains("peasant"):
		score += 120
	if normalized_path.contains("male") and not normalized_path.contains("female"):
		score += 50
	if normalized_path.contains("all_male") or normalized_path.contains("allmale"):
		score -= 25
	if normalized_path.contains("head") and not normalized_path.contains("peasant"):
		score -= 80
	if skinned_meshes > 0:
		score += 40

	var report := {
		"path": path,
		"rigged": true,
		"score": score,
		"bone_count": garment_bones.size(),
		"matched_bones": matched,
		"base_overlap": snappedf(base_overlap, 0.001),
		"garment_overlap": snappedf(garment_overlap, 0.001),
		"mesh_count": meshes.size(),
		"skinned_mesh_count": skinned_meshes,
		"skeleton_name": String(skeleton.name),
	}
	instance.free()
	return report


func _find_best_base_scene() -> String:
	var files: Array[String] = []
	_collect_scene_files(BASE_ROOT, files)
	var best_path := ""
	var best_score := -100000
	for path in files:
		var normalized := path.to_lower()
		var score := 0
		if normalized.contains("regular"):
			score += 50
		if normalized.contains("male") and not normalized.contains("female"):
			score += 25
		if normalized.contains("character") or normalized.contains("body"):
			score += 10
		if normalized.ends_with(".glb"):
			score += 5
		for unwanted in ["hair", "animation", "weapon", "outfit", "prop", "headonly", "head_only"]:
			if normalized.contains(unwanted):
				score -= 100
		if score > best_score:
			best_score = score
			best_path = path
	return best_path


func _load_normalized_bones(path: String) -> Dictionary:
	var result: Dictionary = {}
	var packed = load(path)
	if not packed is PackedScene:
		return result
	var instance = (packed as PackedScene).instantiate()
	if not instance is Node:
		return result
	var skeleton := _find_first_skeleton(instance)
	if skeleton != null:
		for index in range(skeleton.get_bone_count()):
			var normalized := _normalized_bone_name(skeleton.get_bone_name(index))
			if not normalized.is_empty():
				result[normalized] = true
	instance.free()
	return result


func _collect_scene_files(root_path: String, output: Array[String]) -> void:
	var directory := DirAccess.open(root_path)
	if directory == null:
		return
	directory.list_dir_begin()
	while true:
		var name := directory.get_next()
		if name.is_empty():
			break
		if name.begins_with("."):
			continue
		var path := root_path.path_join(name)
		if directory.current_is_dir():
			_collect_scene_files(path, output)
		else:
			var lower := name.to_lower()
			if lower.ends_with(".gltf") or lower.ends_with(".glb"):
				output.append(path)
	directory.list_dir_end()
	output.sort()


func _find_first_skeleton(root_node: Node) -> Skeleton3D:
	if root_node is Skeleton3D:
		return root_node as Skeleton3D
	for child in root_node.get_children():
		var found := _find_first_skeleton(child)
		if found != null:
			return found
	return null


func _collect_meshes(root_node: Node, output: Array[MeshInstance3D]) -> void:
	if root_node is MeshInstance3D:
		output.append(root_node as MeshInstance3D)
	for child in root_node.get_children():
		_collect_meshes(child, output)


func _normalized_bone_name(value: StringName) -> String:
	var normalized := String(value).to_lower()
	for token in ["_", "-", " ", "/", ".", ":"]:
		normalized = normalized.replace(token, "")
	for prefix in ["mixamorig", "def", "org", "armature"]:
		if normalized.begins_with(prefix):
			normalized = normalized.trim_prefix(prefix)
	return normalized.replace("left", "l").replace("right", "r")
