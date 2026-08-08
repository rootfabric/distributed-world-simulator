extends SceneTree

const BASE_ROOT := "res://assets/external/quaternius/base_characters"
const SOURCE_PATH := "res://assets/external/quaternius/base_characters/Universal Base Characters[Standard]/Base Characters/Godot - UE/Superhero_Male_FullBody.gltf"

var scene_files: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_collect_scene_files(BASE_ROOT, scene_files)
	scene_files.sort()
	print("CH7.8 base variant probe: root=%s" % BASE_ROOT)
	print("CH7.8 base variant probe: discovered_scene_files=%d" % scene_files.size())
	for path in scene_files:
		print("CH7.8 base scene: %s" % path)

	if not ResourceLoader.exists(SOURCE_PATH):
		push_error("CH7.8 base variant probe: source full-body scene missing: %s" % SOURCE_PATH)
		quit(2)
		return
	var source_packed = load(SOURCE_PATH)
	if not source_packed is PackedScene:
		push_error("CH7.8 base variant probe: source full-body resource is not PackedScene")
		quit(2)
		return
	var source_instance = (source_packed as PackedScene).instantiate()
	if not source_instance is Node:
		push_error("CH7.8 base variant probe: source full-body scene did not instantiate")
		quit(2)
		return
	var source_skeleton := _find_first_skeleton(source_instance as Node)
	if source_skeleton == null:
		(source_instance as Node).free()
		push_error("CH7.8 base variant probe: source full-body skeleton missing")
		quit(2)
		return
	var source_bones := _normalized_bone_set(source_skeleton)
	print("CH7.8 base variant probe: source=%s bones=%d" % [SOURCE_PATH, source_skeleton.get_bone_count()])

	var candidates: Array[Dictionary] = []
	for path in scene_files:
		var lower := path.get_file().to_lower()
		if not lower.contains("head") and not lower.contains("upperbody"):
			continue
		var report := _inspect_candidate(path, source_bones)
		if not report.is_empty():
			candidates.append(report)
	candidates.sort_custom(_sort_candidates)

	print("CH7.8 base variant probe: candidate_count=%d" % candidates.size())
	for index in range(candidates.size()):
		print("CH7.8 base candidate %02d: %s" % [index + 1, JSON.stringify(candidates[index])])

	(source_instance as Node).free()
	if candidates.is_empty():
		print("CH7.8 base variant probe: OUTDATED_OR_INCOMPATIBLE_BASE_PACK — no Head/Upperbody glTF variants found")
		quit(3)
		return

	var recommended: Dictionary = candidates[0]
	var recommended_path := String(recommended.get("path", ""))
	var recommended_name := recommended_path.get_file().to_lower()
	var recommended_overlap := float(recommended.get("source_overlap", 0.0))
	if not recommended_name.contains("head") or recommended_overlap < 0.9:
		print("CH7.8 base variant probe: NO_SAFE_HEAD_REPLACEMENT — best=%s overlap=%.3f" % [recommended_path, recommended_overlap])
		quit(4)
		return

	print("CH7.8 base variant probe: RECOMMENDED=%s" % recommended_path)
	print("CH7.8 base variant probe: recommended bones=%d overlap=%.3f skinned_meshes=%d" % [
		int(recommended.get("bone_count", 0)),
		recommended_overlap,
		int(recommended.get("skinned_mesh_count", 0)),
	])
	print("CH7.8 Quaternius base character variant probe: PASS")
	quit(0)


func _inspect_candidate(path: String, source_bones: Dictionary) -> Dictionary:
	if not ResourceLoader.exists(path):
		return {}
	var packed = load(path)
	if not packed is PackedScene:
		return {}
	var instance = (packed as PackedScene).instantiate()
	if not instance is Node:
		return {}
	var skeleton := _find_first_skeleton(instance as Node)
	if skeleton == null:
		(instance as Node).free()
		return {}
	var candidate_bones := _normalized_bone_set(skeleton)
	var matched := 0
	for key in candidate_bones.keys():
		if source_bones.has(key):
			matched += 1
	var overlap := float(matched) / float(maxi(1, candidate_bones.size()))
	var source_overlap := float(matched) / float(maxi(1, source_bones.size()))
	var meshes: Array[MeshInstance3D] = []
	_collect_meshes(instance as Node, meshes)
	var skinned_meshes := 0
	for mesh in meshes:
		if mesh.skin != null or not mesh.skeleton.is_empty():
			skinned_meshes += 1
	var score := int(round(source_overlap * 1000.0))
	var lower := path.get_file().to_lower()
	if lower.contains("head"):
		score += 500
	if lower.contains("upperbody"):
		score += 100
	if lower.contains("superhero"):
		score += 100
	if lower.contains("male") and not lower.contains("female"):
		score += 80
	if lower.contains("female"):
		score -= 500
	var result := {
		"path": path,
		"bone_count": skeleton.get_bone_count(),
		"matched_bones": matched,
		"candidate_overlap": overlap,
		"source_overlap": source_overlap,
		"mesh_count": meshes.size(),
		"skinned_mesh_count": skinned_meshes,
		"score": score,
	}
	(instance as Node).free()
	return result


func _sort_candidates(left: Dictionary, right: Dictionary) -> bool:
	var left_score := int(left.get("score", 0))
	var right_score := int(right.get("score", 0))
	if left_score == right_score:
		return String(left.get("path", "")) < String(right.get("path", ""))
	return left_score > right_score


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


func _normalized_bone_set(skeleton: Skeleton3D) -> Dictionary:
	var result: Dictionary = {}
	for index in range(skeleton.get_bone_count()):
		result[_normalized_bone_name(String(skeleton.get_bone_name(index)))] = true
	return result


func _normalized_bone_name(value: String) -> String:
	var normalized := value.to_lower()
	for token in ["_", "-", " ", "/", ".", ":", "|"]:
		normalized = normalized.replace(token, "")
	for prefix in ["mixamorig", "def", "org", "armature"]:
		if normalized.begins_with(prefix):
			normalized = normalized.trim_prefix(prefix)
	return normalized.replace("left", "l").replace("right", "r")
