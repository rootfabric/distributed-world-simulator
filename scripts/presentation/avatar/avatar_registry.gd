extends RefCounted
# Pluggable avatar provider registry. The caller supplies an optional mapping of
# appearance IDs to PackedScene paths; network/player code sees only the port.
const DEFAULT_APPEARANCE := "default"
const DefaultVisual = preload("res://scripts/presentation/avatar/humanoid_avatar_visual.gd")

var _providers: Dictionary = {}

func register_scene(appearance_id: String, scene_path: String) -> bool:
	var key := appearance_id.strip_edges().to_lower()
	if key.is_empty() or not scene_path.begins_with("res://") or not scene_path.ends_with(".tscn"):
		return false
	_providers[key] = scene_path
	return true

func create_visual(appearance_id: String) -> Node3D:
	var key := appearance_id.strip_edges().to_lower()
	if _providers.has(key):
		var resource = load(String(_providers[key]))
		if resource is PackedScene:
			var instance: Node = resource.instantiate()
			if instance is Node3D and instance.has_method("apply_avatar_state") and instance.has_method("get_avatar_report"):
				return instance
			instance.free()
	# A missing or invalid pack never makes a player disappear.
	return DefaultVisual.new()
