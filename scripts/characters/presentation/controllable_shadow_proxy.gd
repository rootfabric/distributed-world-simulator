class_name ControllableShadowProxy
extends Node3D

const PresentationProfile = preload("res://scripts/characters/presentation/controllable_presentation_profile.gd")

var source_root: Node
var custom_proxy_root: Node
var shadow_layer_mask := 0
var shadow_policy := PresentationProfile.FirstPersonShadowPolicy.NONE
var active := false

var _generated_entries: Array[Dictionary] = []
var _custom_visual_states: Array[Dictionary] = []
var _custom_root_original_visible := true
var _custom_root_visibility_captured := false
var _skinned_proxy_count := 0
var _skeleton_bound_proxy_count := 0
var _shared_mesh_resource_count := 0


func _ready() -> void:
	top_level = true
	set_process(false)


func configure(
	world_root: Node,
	custom_root: Node,
	policy: int,
	layer_mask: int
) -> Dictionary:
	clear()
	source_root = world_root
	custom_proxy_root = custom_root
	shadow_policy = policy
	shadow_layer_mask = layer_mask

	match shadow_policy:
		PresentationProfile.FirstPersonShadowPolicy.NONE:
			pass
		PresentationProfile.FirstPersonShadowPolicy.WORLD_PROXY:
			_build_world_proxies()
		PresentationProfile.FirstPersonShadowPolicy.CUSTOM_PROXY:
			_bind_custom_proxy()
		_:
			return _failure("UNKNOWN_SHADOW_POLICY")

	set_active(false)
	return _success(create_report())


func set_active(enabled: bool) -> void:
	active = enabled
	if shadow_policy == PresentationProfile.FirstPersonShadowPolicy.WORLD_PROXY:
		_sync_generated_proxies()
	elif shadow_policy == PresentationProfile.FirstPersonShadowPolicy.CUSTOM_PROXY:
		_apply_custom_visibility()
	set_process(active and shadow_policy == PresentationProfile.FirstPersonShadowPolicy.WORLD_PROXY)


func clear() -> void:
	set_process(false)
	active = false
	for entry in _generated_entries:
		var proxy = entry.get("proxy")
		if is_instance_valid(proxy):
			(proxy as Node).queue_free()
	_generated_entries.clear()
	_restore_custom_proxy()
	source_root = null
	custom_proxy_root = null
	shadow_layer_mask = 0
	shadow_policy = PresentationProfile.FirstPersonShadowPolicy.NONE
	_skinned_proxy_count = 0
	_skeleton_bound_proxy_count = 0
	_shared_mesh_resource_count = 0


func _process(_delta: float) -> void:
	_sync_generated_proxies()


func _build_world_proxies() -> void:
	if source_root == null or shadow_layer_mask == 0:
		return
	var source_meshes: Array[MeshInstance3D] = []
	_collect_mesh_instances(source_root, source_meshes)
	for source in source_meshes:
		if source.mesh == null:
			continue
		if source.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			continue
		var proxy := MeshInstance3D.new()
		proxy.name = "%s_FPShadowProxy" % String(source.name)
		proxy.mesh = source.mesh
		proxy.skin = source.skin
		proxy.layers = shadow_layer_mask
		proxy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		proxy.material_override = source.material_override
		proxy.extra_cull_margin = source.extra_cull_margin
		proxy.ignore_occlusion_culling = true
		for surface_index in range(source.get_surface_override_material_count()):
			var material := source.get_surface_override_material(surface_index)
			if material != null:
				proxy.set_surface_override_material(surface_index, material)
		add_child(proxy)
		proxy.top_level = true
		var skeleton_node: Node = null
		if not source.skeleton.is_empty():
			skeleton_node = source.get_node_or_null(source.skeleton)
		if source.skin != null:
			_skinned_proxy_count += 1
		if skeleton_node is Skeleton3D:
			proxy.skeleton = proxy.get_path_to(skeleton_node)
			_skeleton_bound_proxy_count += 1
		if proxy.mesh == source.mesh:
			_shared_mesh_resource_count += 1
		_generated_entries.append({"source": source, "proxy": proxy})
	_sync_generated_proxies()


func _bind_custom_proxy() -> void:
	if custom_proxy_root == null or shadow_layer_mask == 0:
		return
	if source_root != null and _is_same_or_descendant(custom_proxy_root, source_root):
		return
	if custom_proxy_root is Node3D:
		_custom_root_original_visible = (custom_proxy_root as Node3D).visible
		_custom_root_visibility_captured = true
	var visuals: Array[GeometryInstance3D] = []
	_collect_geometry_instances(custom_proxy_root, visuals)
	for visual in visuals:
		_custom_visual_states.append({
			"node": visual,
			"layers": visual.layers,
			"cast_shadow": visual.cast_shadow,
		})
		visual.layers = shadow_layer_mask
		visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	_apply_custom_visibility()


func _sync_generated_proxies() -> void:
	for entry in _generated_entries:
		var source = entry.get("source")
		var proxy = entry.get("proxy")
		if not (is_instance_valid(source) and source is MeshInstance3D):
			if is_instance_valid(proxy):
				(proxy as Node).queue_free()
			continue
		if not (is_instance_valid(proxy) and proxy is MeshInstance3D):
			continue
		var source_mesh := source as MeshInstance3D
		var proxy_mesh := proxy as MeshInstance3D
		proxy_mesh.global_transform = source_mesh.global_transform
		proxy_mesh.visible = active and source_mesh.is_visible_in_tree()
		proxy_mesh.material_override = source_mesh.material_override


func _apply_custom_visibility() -> void:
	if custom_proxy_root is Node3D:
		(custom_proxy_root as Node3D).visible = active


func _restore_custom_proxy() -> void:
	for state in _custom_visual_states:
		var node = state.get("node")
		if is_instance_valid(node) and node is GeometryInstance3D:
			(node as GeometryInstance3D).layers = int(state.get("layers", 1))
			(node as GeometryInstance3D).cast_shadow = int(state.get("cast_shadow", GeometryInstance3D.SHADOW_CASTING_SETTING_ON))
	_custom_visual_states.clear()
	if _custom_root_visibility_captured and is_instance_valid(custom_proxy_root) and custom_proxy_root is Node3D:
		(custom_proxy_root as Node3D).visible = _custom_root_original_visible
	_custom_root_visibility_captured = false


func _collect_mesh_instances(root_node: Node, output: Array[MeshInstance3D]) -> void:
	if root_node is MeshInstance3D:
		output.append(root_node as MeshInstance3D)
	for child in root_node.get_children():
		_collect_mesh_instances(child, output)


func _collect_geometry_instances(root_node: Node, output: Array[GeometryInstance3D]) -> void:
	if root_node is GeometryInstance3D:
		output.append(root_node as GeometryInstance3D)
	for child in root_node.get_children():
		_collect_geometry_instances(child, output)


func _is_same_or_descendant(candidate: Node, ancestor: Node) -> bool:
	var current: Node = candidate
	while current != null:
		if current == ancestor:
			return true
		current = current.get_parent()
	return false


func get_generated_proxies() -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	for entry in _generated_entries:
		var proxy = entry.get("proxy")
		if is_instance_valid(proxy) and proxy is MeshInstance3D:
			result.append(proxy as MeshInstance3D)
	return result


func create_report() -> Dictionary:
	var generated_count := get_generated_proxies().size()
	var custom_count := 0
	for state in _custom_visual_states:
		var node = state.get("node")
		if is_instance_valid(node):
			custom_count += 1
	var proxy_count := generated_count + custom_count
	return {
		"schema": "planet_simulator.controllable_shadow_proxy.v1",
		"shadow_policy": _shadow_policy_name(),
		"shadow_layer_mask": shadow_layer_mask,
		"active": active,
		"ready": proxy_count > 0 or shadow_policy == PresentationProfile.FirstPersonShadowPolicy.NONE,
		"proxy_count": proxy_count,
		"generated_proxy_count": generated_count,
		"custom_proxy_count": custom_count,
		"skinned_proxy_count": _skinned_proxy_count,
		"skeleton_bound_proxy_count": _skeleton_bound_proxy_count,
		"shared_mesh_resource_count": _shared_mesh_resource_count,
		"world_root_present": source_root != null,
		"custom_root_present": custom_proxy_root != null,
	}


func _shadow_policy_name() -> String:
	match shadow_policy:
		PresentationProfile.FirstPersonShadowPolicy.NONE:
			return "NONE"
		PresentationProfile.FirstPersonShadowPolicy.WORLD_PROXY:
			return "WORLD_PROXY"
		PresentationProfile.FirstPersonShadowPolicy.CUSTOM_PROXY:
			return "CUSTOM_PROXY"
		_:
			return "UNKNOWN"


func _success(details: Dictionary = {}) -> Dictionary:
	return {"success": true, "error_code": "", "details": details.duplicate(true)}


func _failure(code: String) -> Dictionary:
	return {"success": false, "error_code": code, "details": create_report()}
