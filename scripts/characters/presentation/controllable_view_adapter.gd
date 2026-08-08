class_name ControllableViewAdapter
extends Node

const PresentationProfile = preload("res://scripts/characters/presentation/controllable_presentation_profile.gd")
const ShadowProxy = preload("res://scripts/characters/presentation/controllable_shadow_proxy.gd")

var presentation: Node
var profile: Resource
var first_person_camera: Camera3D
var third_person_camera: Camera3D
var world_visual_root: Node
var viewmodel_visual_root: Node
var custom_shadow_proxy_root: Node
var first_person_enabled := false

var _world_visual_states: Array[Dictionary] = []
var _viewmodel_visual_states: Array[Dictionary] = []
var _first_person_original_cull_mask := -1
var _third_person_original_cull_mask := -1
var _viewmodel_original_visible := true
var _shadow_proxy: Node


func bind_presentation(presenter: Node, profile_override: Resource = null) -> Dictionary:
	_clear_shadow_proxy()
	if viewmodel_visual_root is Node3D:
		(viewmodel_visual_root as Node3D).visible = _viewmodel_original_visible
	_restore_visual_layers()
	presentation = presenter
	profile = profile_override if profile_override != null else _resolve_profile(presenter)
	if profile == null:
		profile = PresentationProfile.new()
	world_visual_root = _resolve_world_visual_root(presenter)
	viewmodel_visual_root = _resolve_viewmodel_visual_root(presenter)
	custom_shadow_proxy_root = _resolve_custom_shadow_proxy_root(presenter)
	_capture_and_move_visuals(world_visual_root, _world_render_layer_mask(), _world_visual_states)
	if viewmodel_visual_root != null and viewmodel_visual_root != world_visual_root:
		_capture_and_move_visuals(viewmodel_visual_root, _viewmodel_render_layer_mask(), _viewmodel_visual_states)
		if viewmodel_visual_root is Node3D:
			_viewmodel_original_visible = (viewmodel_visual_root as Node3D).visible
	_build_shadow_proxy()
	_apply_camera_policy()
	_apply_viewmodel_visibility()
	_apply_shadow_visibility()
	return _success(create_report())


func unbind_presentation() -> void:
	_clear_shadow_proxy()
	_restore_visual_layers()
	if viewmodel_visual_root is Node3D:
		(viewmodel_visual_root as Node3D).visible = _viewmodel_original_visible
	presentation = null
	profile = null
	world_visual_root = null
	viewmodel_visual_root = null
	custom_shadow_proxy_root = null
	first_person_enabled = false
	_restore_camera_masks()


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
	_apply_shadow_visibility()
	return _success(create_report())


func get_first_person_policy() -> int:
	if profile == null:
		return PresentationProfile.FirstPersonPolicy.HIDE_WORLD_MODEL
	return int(profile.first_person_policy)


func get_first_person_shadow_policy() -> int:
	if profile == null:
		return PresentationProfile.FirstPersonShadowPolicy.NONE
	return int(profile.first_person_shadow_policy)


func get_world_render_layer_mask() -> int:
	return _world_render_layer_mask()


func get_viewmodel_render_layer_mask() -> int:
	return _viewmodel_render_layer_mask()


func get_shadow_render_layer_mask() -> int:
	return _shadow_render_layer_mask()


func get_shadow_proxy_root() -> Node:
	return _shadow_proxy


func _resolve_profile(presenter: Node) -> Resource:
	if presenter != null and presenter.has_method("create_presentation_profile"):
		var candidate = presenter.call("create_presentation_profile")
		if candidate is Resource:
			return candidate
	return PresentationProfile.new()


func _resolve_world_visual_root(presenter: Node) -> Node:
	if presenter == null:
		return null
	if presenter.has_method("get_world_visual_root"):
		var candidate = presenter.call("get_world_visual_root")
		if candidate is Node:
			return candidate
	return presenter


func _resolve_viewmodel_visual_root(presenter: Node) -> Node:
	if presenter == null or not presenter.has_method("get_first_person_viewmodel_root"):
		return null
	var candidate = presenter.call("get_first_person_viewmodel_root")
	if candidate is Node:
		return candidate
	return null


func _resolve_custom_shadow_proxy_root(presenter: Node) -> Node:
	if presenter == null or not presenter.has_method("get_first_person_shadow_proxy_root"):
		return null
	var candidate = presenter.call("get_first_person_shadow_proxy_root")
	if candidate is Node:
		return candidate
	return null


func _capture_and_move_visuals(root_node: Node, target_layer_mask: int, storage: Array[Dictionary]) -> void:
	storage.clear()
	if root_node == null:
		return
	var visuals: Array[VisualInstance3D] = []
	_collect_visual_instances(root_node, visuals)
	for visual in visuals:
		storage.append({"node": visual, "layers": visual.layers})
		visual.layers = target_layer_mask


func _collect_visual_instances(root_node: Node, output: Array[VisualInstance3D]) -> void:
	if root_node is VisualInstance3D:
		output.append(root_node as VisualInstance3D)
	for child in root_node.get_children():
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


func _build_shadow_proxy() -> void:
	_clear_shadow_proxy()
	if presentation == null or profile == null:
		return
	if not _shadow_preservation_enabled():
		return
	_shadow_proxy = ShadowProxy.new()
	_shadow_proxy.name = "FirstPersonShadowProxy"
	add_child(_shadow_proxy)
	_shadow_proxy.call(
		"configure",
		world_visual_root,
		custom_shadow_proxy_root,
		get_first_person_shadow_policy(),
		_shadow_render_layer_mask()
	)


func _clear_shadow_proxy() -> void:
	if is_instance_valid(_shadow_proxy):
		_shadow_proxy.call("clear")
		(_shadow_proxy as Node).queue_free()
	_shadow_proxy = null


func _apply_camera_policy() -> void:
	if presentation == null or profile == null:
		_restore_camera_masks()
		return
	var world_mask := _world_render_layer_mask()
	var viewmodel_mask := _viewmodel_render_layer_mask()
	var shadow_mask := _shadow_render_layer_mask()
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
		if _should_use_shadow_proxy():
			first_mask |= shadow_mask
		first_person_camera.cull_mask = first_mask

	if third_person_camera != null and _third_person_original_cull_mask >= 0:
		var third_mask := _third_person_original_cull_mask | world_mask
		third_mask &= ~viewmodel_mask
		third_person_camera.cull_mask = third_mask


func _apply_viewmodel_visibility() -> void:
	if not (viewmodel_visual_root is Node3D):
		return
	var should_show := (
		first_person_enabled
		and get_first_person_policy() == PresentationProfile.FirstPersonPolicy.VIEWMODEL
	)
	(viewmodel_visual_root as Node3D).visible = should_show


func _apply_shadow_visibility() -> void:
	if not is_instance_valid(_shadow_proxy):
		return
	_shadow_proxy.call("set_active", _should_use_shadow_proxy())


func _should_use_shadow_proxy() -> bool:
	if not first_person_enabled or not _shadow_preservation_enabled():
		return false
	return get_first_person_policy() in [
		PresentationProfile.FirstPersonPolicy.HIDE_WORLD_MODEL,
		PresentationProfile.FirstPersonPolicy.VIEWMODEL,
	]


func _shadow_preservation_enabled() -> bool:
	if profile == null:
		return false
	if profile.has_method("shadow_preservation_enabled"):
		return bool(profile.call("shadow_preservation_enabled"))
	return bool(profile.get("allow_shadow_from_hidden_world_model"))


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


func _shadow_render_layer_mask() -> int:
	if profile != null and profile.has_method("shadow_render_layer_mask"):
		return int(profile.call("shadow_render_layer_mask"))
	return 1 << 17


func _profile_report() -> Dictionary:
	if profile != null and profile.has_method("create_report"):
		var candidate = profile.call("create_report")
		if candidate is Dictionary:
			return candidate
	return {}


func _shadow_proxy_report() -> Dictionary:
	if is_instance_valid(_shadow_proxy) and _shadow_proxy.has_method("create_report"):
		var candidate = _shadow_proxy.call("create_report")
		if candidate is Dictionary:
			return candidate
	return {}


func create_report() -> Dictionary:
	var world_mask := _world_render_layer_mask()
	var first_person_hides_world := (
		first_person_camera != null
		and presentation != null
		and (first_person_camera.cull_mask & world_mask) == 0
	)
	var third_person_sees_world := (
		presentation != null
		and (
			third_person_camera == null
			or (third_person_camera.cull_mask & world_mask) != 0
		)
	)
	var profile_report := _profile_report()
	var shadow_report := _shadow_proxy_report()
	var shadow_active := bool(shadow_report.get("active", false))
	var shadow_ready := bool(shadow_report.get("ready", false))
	var shadow_preserved := (
		_should_use_shadow_proxy()
		and shadow_active
		and shadow_ready
		and int(shadow_report.get("proxy_count", 0)) > 0
	)
	return {
		"schema": "planet_simulator.controllable_view_adapter.v2",
		"presentation_bound": presentation != null,
		"first_person_enabled": first_person_enabled,
		"first_person_policy": String(profile_report.get("first_person_policy", "HIDE_WORLD_MODEL")),
		"first_person_shadow_policy": String(profile_report.get("first_person_shadow_policy", "NONE")),
		"profile_id": String(profile_report.get("profile_id", "generic")),
		"entity_kind": String(profile_report.get("entity_kind", "generic")),
		"world_visual_root_present": world_visual_root != null,
		"world_visual_count": _world_visual_states.size(),
		"viewmodel_visual_root_present": viewmodel_visual_root != null,
		"viewmodel_visual_count": _viewmodel_visual_states.size(),
		"first_person_camera_bound": first_person_camera != null,
		"third_person_camera_bound": third_person_camera != null,
		"world_render_layer_mask": world_mask,
		"viewmodel_render_layer_mask": _viewmodel_render_layer_mask(),
		"shadow_render_layer_mask": _shadow_render_layer_mask(),
		"render_layers_distinct": bool(profile_report.get("render_layers_distinct", true)),
		"world_hidden_from_first_person": first_person_hides_world,
		"world_visible_to_third_person": third_person_sees_world,
		"world_animation_preserved": bool(profile_report.get("keep_world_animation_active", true)),
		"shadow_preservation_enabled": _shadow_preservation_enabled(),
		"shadow_proxy_ready": shadow_ready,
		"shadow_proxy_active": shadow_active,
		"shadow_proxy_count": int(shadow_report.get("proxy_count", 0)),
		"shadow_proxy_generated_count": int(shadow_report.get("generated_proxy_count", 0)),
		"shadow_proxy_custom_count": int(shadow_report.get("custom_proxy_count", 0)),
		"shadow_proxy_skinned_count": int(shadow_report.get("skinned_proxy_count", 0)),
		"shadow_proxy_skeleton_bound_count": int(shadow_report.get("skeleton_bound_proxy_count", 0)),
		"shadow_proxy_shared_mesh_count": int(shadow_report.get("shared_mesh_resource_count", 0)),
		"shadow_caster_preserved": shadow_preserved,
	}


func _success(details: Dictionary = {}) -> Dictionary:
	return {"success": true, "error_code": "", "details": details.duplicate(true)}
