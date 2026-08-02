class_name HumanoidImportValidator
extends RefCounted

const Utils = preload("res://scripts/characters/contracts/character_contract_utils.gd")
const REQUIRED_BONES := ["root", "hips", "spine", "head", "hand_l", "hand_r", "foot_l", "foot_r"]

func validate_definition(definition, scene_parent: Node) -> Dictionary:
	if definition == null:
		return Utils.failure("MISSING_HUMANOID_DEFINITION")
	var definition_result: Dictionary = definition.validate()
	if not definition_result.success:
		return definition_result
	if scene_parent == null:
		return Utils.failure("MISSING_IMPORT_VALIDATION_PARENT")
	var packed = load(definition.presentation_scene_path)
	if not packed is PackedScene:
		return Utils.failure("HUMANOID_SCENE_LOAD_FAILED", {"path": definition.presentation_scene_path})
	var instance := (packed as PackedScene).instantiate()
	if not instance is Node3D:
		instance.free()
		return Utils.failure("HUMANOID_ROOT_MUST_BE_NODE3D")
	scene_parent.add_child(instance)
	if instance.has_method("build_now"):
		instance.call("build_now")
	var skeleton := _find_first(instance, "Skeleton3D") as Skeleton3D
	var animation_player := _find_first(instance, "AnimationPlayer") as AnimationPlayer
	if skeleton == null:
		instance.queue_free()
		return Utils.failure("HUMANOID_SKELETON_MISSING")
	if animation_player == null:
		instance.queue_free()
		return Utils.failure("HUMANOID_ANIMATION_PLAYER_MISSING")
	for bone_name in REQUIRED_BONES:
		if skeleton.find_bone(bone_name) < 0:
			instance.queue_free()
			return Utils.failure("HUMANOID_REQUIRED_BONE_MISSING", {"bone": bone_name})
	for semantic in definition.animation_profile.semantic_map:
		var animation_name: StringName = definition.animation_profile.resolve(semantic)
		if animation_name == &"" or not animation_player.has_animation(animation_name):
			instance.queue_free()
			return Utils.failure("HUMANOID_ANIMATION_MISSING", {"semantic": semantic, "animation": animation_name})
	for socket_id in definition.socket_profile.socket_paths:
		var path: NodePath = definition.socket_profile.resolve_path(socket_id)
		if path.is_empty() or instance.get_node_or_null(path) == null:
			instance.queue_free()
			return Utils.failure("HUMANOID_SOCKET_MISSING", {"socket_id": socket_id, "path": String(path)})
	var details := {"character_id": definition.character_id, "bone_count": skeleton.get_bone_count(), "animation_count": animation_player.get_animation_list().size(), "socket_count": definition.socket_profile.socket_paths.size()}
	instance.queue_free()
	return Utils.success(details)

func _find_first(root: Node, class_name_value: String) -> Node:
	if root.is_class(class_name_value):
		return root
	for child in root.get_children():
		var found := _find_first(child, class_name_value)
		if found != null:
			return found
	return null
