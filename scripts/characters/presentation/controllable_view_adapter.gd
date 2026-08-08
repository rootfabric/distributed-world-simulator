class_name ControllableViewAdapter
extends Node

const PresentationProfile = preload("res://scripts/characters/presentation/controllable_presentation_profile.gd")

var presentation: Node
var profile: Resource
var first_person_camera: Camera3D
var third_person_camera: Camera3D
var world_visual_root: Node
var viewmodel_visual_root: Node
var first_person_enabled := false

var _world_visual_states: Array[Dictionary] = []
var _viewmodel_visual_states: Array[Dictionary] = []
var _first_person_original_cull_mask := -1
var _third_person_original_cull_mask := -1
var _viewmodel_original_visible := true


func bind_presentation(presenter: Node, profile_override: Resource = null) -> Dictionary:
	_restore_visual_layers()
	presentation = presenter
	profile = profile_override if profile_override != null else _resolve_profile(presenter)
	if profile == null:
		profile = PresentationProfile.new()
	world_visual_root = _resolve_world_visual_root(presenter)
	viewmodel_visual_root = _resolve_viewmodel_visual_root(presenter)
	_capture_and_move_visuals(world_visual_root, _world_render_layer_mask(), _world_visual_states)
	if viewmodel_visual_root != null and viewmodel_visual_root != world_visual_root:
		_capture_and_move_visuals(viewmodel_visual_root, _viewmodel_render_layer_mask(), _viewmodel_visual_states)
		if viewmodel_visual_root is Node3D:
			_viewmodel_original_visible = (viewmodel_visual_root as Node3D).visible
	_apply_camera_policy()
	_apply_viewmodel_visibility()
	return _success(create_report())


func unbind_presentation() -> void:
	_restore_visual_layers()
	if viewmodel_visual_root is Node3D:
		(viewmodel_visual_root as Node3D).visible = _viewmodel_original_visible
	presentation = null
	profile = null
	world_visual_root = null
	viewmodel_visual_root = null
	first_person_enabled = false
	_apply_camera_policy()


func bind_cameras(first_person: Camera3D, third_person: Camera3D = null) -> Dictionary:
	_restore_camera_masks()
	first_person_camera = first_person
	third_person_camera = third_person
	if first_person_camera != null:
		_first_person_original_cull_mask = first_person_camera.cull_mask
	if third_person_camera != null:
		_third_person_original_cull_mask = third_person_camera.cull_mask
	_apply_camera_policy()
	return _success(create_report())


func unbind_cameras() -> void:
	_restore_camera_masks()
	first_person_camera = null
	third_person_camera = null
	_first_person_original_cull_mask = -1
	_third_person_original_cull_mask = -1


func set_first_person_enabled(enabled: bool) -> Dictionary:
	first_person_enabled = enabled
	_apply_camera_policy()
	_apply_viewmodel_visibility()
	return _success(create_report())


func get_first_person_policy() -> int:
	if profile == null:
		return PresentationProfile.FirstPersonPolicy.HIDE_WORLD_MODEL
	return int(profile.first_person_policy)


func get_world_render_layer_mask() -> int:
	return _world_render_layer_mask()


func get_viewmodel_render_layer_mask() -> int:
	return _viewmodel_render_layer_mask()


func _resolve_profile(presenter: Node) -> Resource:
	if presenter != null and presenter.has_method("create_presentation_profile"):
		var candidate = presenter.call("create_presentation_profile")
		if candidate is Resource:
			return candidate as Resource
	return PresentationProfile.new()


func _resolve_world_visual_root(presenter: Node) -> Node:
	if presenter == null:
		return null
	if presenter.has_method("get_world_visual_root"):
		var candidate = presenter.call("get_world_visual_root")
		if candidate is Node:
			return candidate as Node
	return presenter


func _resolve_viewmodel_visual_root(presenter: Node) -> Node:
	if presenter == null or not presenter.has_method("get_first_person_viewmodel_root"):
		return null
	var candidate = presenter.call("get_first_person_viewmodel_root")
	return candidate as Node if candidate is Node else null


func _capture_and_move_visuals(root: Node, target_layer_mask: int, storage: Array[Dictionary]) -> void:
	storage.clear()
	if root == null:
		return
	var visuals: Array[VisualInstance3D] = []
	_collect_visual_instances(root, visuals)
	for visual in visuals:
		storage.append({"node": visual, "layers": visual.layers})
		visual.layers = target_layer_mask


func _collect_visual_instances(root: Node, output: Array[VisualInstance3D]) -> void:
	if root is VisualInstance3D:
		output.append(root as VisualInstance3D)
	for child in root.get_children():
		_collect_visual_instances(child, output)


func _restore_visual_layers() -> void:
	_restore_visual_state_array(_world_visual_states)
	_restore_visual_state_array(_viewmodel_visual_states)
	_world_visual_states.clear()
	_viewmodel_visual_states.clear()


func _restore_visual_state_array(states: Array[Dictionary]) -> void:
	for state in states:
		var node = state.get("node")
		if is_instance_valid(node) and node is VisualInstance3D:
			(node as VisualInstance3D).layers = int(state.get("layers", 1))


func _apply_camera_policy() -> void:
	var world_mask := _world_render_layer_mask()
	var viewmodel_mask := _viewmodel_render_layer_mask()
	var policy := get_first_person_policy()

	if first_person_camera != null and _first_person_original_cull_mask >= 0:
		var first_mask := _first_person_original_cull_mask
		match policy:
			PresentationProfile.FirstPersonPolicy.HIDE_WORLD_MODEL:
				first_mask &= ~world_mask
				first_mask &= ~viewmodel_mask
			PresentationProfile.FirstPersonPolicy.SHOW_WORLD_MODEL:
				first_mask |= world_mask
				first_mask &= ~viewmodel_mask
			PresentationProfile.FirstPersonPolicy.LEGACY_HEAD_MASK:
				first_mask |= world_mask
				first_mask &= ~viewmodel_mask
			PresentationProfile.FirstPersonPolicy.VIEWMODEL:
				first_mask &= ~world_mask
				first_mask |= viewmodel_mask
		first_person_camera.cull_mask = first_mask

	if third_person_camera != null and _third_person_original_cull_mask >= 0:
		var third_mask := _third_person_original_cull_mask | world_mask
		third_mask &= ~viewmodel_mask
		third_person_camera.cull_mask = third_mask


func _apply_viewmodel_visibility() -> void:
	if not viewmodel_visual_root is Node3D:
		return
	var should_show := (
		first_person_enabled
		and get_first_person_policy() == PresentationProfile.FirstPersonPolicy.VIEWMODEL
	)
	(viewmodel_visual_root as Node3D).visible = should_show


func _restore_camera_masks() -> void:
	if first_person_camera != null and _first_person_original_cull_mask >= 0:
		first_person_camera.cull_mask = _first_person_original_cull_mask
	if third_person_camera != null and _third_person_original_cull_mask >= 0:
		third_person_camera.cull_mask = _third_person_original_cull_mask


func _world_render_layer_mask() -> int:
	if profile != null and profile.has_method("world_render_layer_mask"):
		return int(profile.call("world_render_layer_mask"))
	return 1 << 19


func _viewmodel_render_layer_mask() -> int:
	if profile != null and profile.has_method("viewmodel_render_layer_mask"):
		return int(profile.call("viewmodel_render_layer_mask"))
	return 1 << 18


func _profile_report() -> Dictionary:
	if profile != null and profile.has_method("create_report"):
		return Dictionary(profile.call("create_report"))
	return {}


func create_report() -> Dictionary:
	var world_mask := _world_render_layer_mask()
	var first_person_hides_world := (
		first_person_camera != null
		and (first_person_camera.cull_mask & world_mask) == 0
	)
	var third_person_sees_world := (
		third_person_camera == null
		or (third_person_camera.cull_mask & world_mask) != 0
	)
	return {
		"schema": "planet_simulator.controllable_view_adapter.v1",
		"presentation_bound": presentation != null,
		"first_person_enabled": first_person_enabled,
		"first_person_policy": String(_profile_report().get("first_person_policy", "HIDE_WORLD_MODEL")),
		"profile_id": String(_profile_report().get("profile_id", "generic")),
		"entity_kind": String(_profile_report().get("entity_kind", "generic")),
		"world_visual_root_present": world_visual_root != null,
		"world_visual_count": _world_visual_states.size(),
		"viewmodel_visual_root_present": viewmodel_visual_root != null,
		"viewmodel_visual_count": _viewmodel_visual_states.size(),
		"first_person_camera_bound": first_person_camera != null,
		"third_person_camera_bound": third_person_camera != null,
		"world_render_layer_mask": world_mask,
		"viewmodel_render_layer_mask": _viewmodel_render_layer_mask(),
		"world_hidden_from_first_person": first_person_hides_world,
		"world_visible_to_third_person": third_person_sees_world,
		"world_animation_preserved": bool(_profile_report().get("keep_world_animation_active", true)),
		"shadow_caster_preserved": bool(_profile_report().get("allow_shadow_from_hidden_world_model", true)),
	}


func _success(details: Dictionary = {}) -> Dictionary:
	return {"success": true, "error_code": "", "details": details.duplicate(true)}
