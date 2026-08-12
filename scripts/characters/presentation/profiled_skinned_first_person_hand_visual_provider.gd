class_name ProfiledSkinnedFirstPersonHandVisualProvider
extends "res://scripts/characters/presentation/skinned_first_person_hand_visual_provider.gd"

const ProfileType = preload("res://scripts/characters/presentation/first_person_hand_asset_profile.gd")

var hand_asset_profile: Dictionary = {}
var hand_asset_profile_path := ""
var _source_scene: PackedScene
var _source_resource_path := ""


func setup_profiled(
	p_scene: PackedScene,
	p_profile: Dictionary,
	p_profile_path: String = "",
	p_resource_path: String = ""
) -> Dictionary:
	var validation: Dictionary = ProfileType.validate(p_profile)
	if not bool(validation.get("success", false)):
		return validation
	if p_scene == null:
		return _failure("FPE_HAND_PROFILE_SCENE_REQUIRED")
	var provider_kind := String(p_profile.get("provider", "")).strip_edges().to_upper()
	if provider_kind != ProfileType.PROVIDER_SKINNED_NAMED_BIND:
		return _failure("FPE_HAND_PROFILE_PROVIDER_NOT_SKINNED", {"provider": provider_kind})
	var layout := String(p_profile.get("hand_layout", "")).strip_edges().to_upper()
	if layout == "PAIRED_SINGLE_MESH":
		return _failure("FPE_HAND_PROFILE_PAIRED_SINGLE_MESH_REQUIRES_PAIRED_VIEWMODEL_ADAPTER", {
			"profile_id": String(p_profile.get("profile_id", "")),
		})
	var retarget := Dictionary(p_profile.get("retarget", {}))
	var rest_policy := String(retarget.get("rest_space_policy", "")).strip_edges().to_upper()
	if rest_policy != REST_SPACE_POLICY:
		return _failure("FPE_HAND_PROFILE_REST_SPACE_NOT_CALIBRATED", {
			"profile_id": String(p_profile.get("profile_id", "")),
			"actual": rest_policy,
			"required": REST_SPACE_POLICY,
		})
	if Dictionary(retarget.get("bone_map", {})).is_empty():
		return _failure("FPE_HAND_PROFILE_BONE_MAP_REQUIRED", {
			"profile_id": String(p_profile.get("profile_id", "")),
		})

	hand_asset_profile = p_profile.duplicate(true)
	hand_asset_profile_path = p_profile_path.strip_edges()
	_source_scene = p_scene
	_source_resource_path = p_resource_path.strip_edges()
	return _success({
		"profile_id": String(hand_asset_profile.get("profile_id", "")),
		"profile_path": hand_asset_profile_path,
		"resource_path": _source_resource_path,
		"portable_profile": true,
	})


func install_visuals(
	skeleton: Skeleton3D,
	hand_id: String,
	viewmodel_layer_index: int
) -> Dictionary:
	if _source_scene == null or hand_asset_profile.is_empty():
		return _failure("FPE_HAND_PROFILE_PROVIDER_NOT_CONFIGURED")
	var adapted_result := _build_adapted_scene(hand_id)
	if not bool(adapted_result.get("success", false)):
		return adapted_result
	var adapted_details := Dictionary(adapted_result.get("details", {}))
	var adapted_value: Variant = adapted_details.get("scene")
	if not adapted_value is PackedScene:
		return _failure("FPE_HAND_PROFILE_ADAPTED_SCENE_INVALID")
	var adapted_scene := adapted_value as PackedScene
	var parent_setup: Dictionary = super.setup(adapted_scene, _source_resource_path)
	if not bool(parent_setup.get("success", false)):
		return parent_setup
	var result: Dictionary = super.install_visuals(skeleton, hand_id, viewmodel_layer_index)
	if bool(result.get("success", false)):
		var details := Dictionary(result.get("details", {}))
		var report := Dictionary(details.get("report", {})).duplicate(true)
		report["profile_id"] = String(hand_asset_profile.get("profile_id", ""))
		report["profile_path"] = hand_asset_profile_path
		report["profiled_external_asset"] = bool(Dictionary(hand_asset_profile.get("asset", {})).get("external", false))
		report["portable_profile"] = true
		report["source_license"] = String(Dictionary(hand_asset_profile.get("license", {})).get("spdx", ""))
		details["report"] = report
		result["details"] = details
	return result


func _build_adapted_scene(hand_id: String) -> Dictionary:
	var normalized_hand := hand_id.strip_edges().to_lower()
	if normalized_hand not in ["left", "right"]:
		return _failure("FPE_HAND_PROFILE_INVALID_HAND", {"hand_id": hand_id})
	var source_instance: Node = _source_scene.instantiate()
	if not source_instance is Node3D:
		if source_instance != null:
			source_instance.free()
		return _failure("FPE_HAND_PROFILE_SOURCE_ROOT_NOT_NODE3D")
	var source_root := source_instance as Node3D
	var selection := Dictionary(hand_asset_profile.get("selection", {}))
	var selected := _select_skinned_meshes(source_root, selection, normalized_hand)
	if selected.is_empty():
		source_root.free()
		return _failure("FPE_HAND_PROFILE_NO_SKINNED_MESH_SELECTED", {
			"profile_id": String(hand_asset_profile.get("profile_id", "")),
			"hand_id": normalized_hand,
		})

	var wrapper := Node3D.new()
	wrapper.name = "ProfiledHandAsset"
	wrapper.set_meta("fpe_hand_visual_schema", ASSET_SCHEMA)
	wrapper.set_meta("fpe_compatible_skeleton_schema", SKELETON_SCHEMA)
	wrapper.set_meta("fpe_rest_space_policy", REST_SPACE_POLICY)
	wrapper.set_meta("fpe_hand", normalized_hand)
	wrapper.set_meta("fpe_provider_id", String(hand_asset_profile.get("profile_id", "profiled_hand")))
	var retarget := Dictionary(hand_asset_profile.get("retarget", {}))
	wrapper.set_meta("fpe_bone_map", Dictionary(retarget.get("bone_map", {})).duplicate(true))
	var presentation_transform := _profile_transform(Dictionary(hand_asset_profile.get("presentation", {})))

	for mesh_instance in selected:
		var relative := _relative_transform_to_root(mesh_instance, source_root)
		var parent := mesh_instance.get_parent()
		if parent != null:
			parent.remove_child(mesh_instance)
		wrapper.add_child(mesh_instance)
		mesh_instance.transform = presentation_transform * relative
		_set_owner_recursive(mesh_instance, wrapper)

	source_root.free()
	var packed := PackedScene.new()
	var pack_error := packed.pack(wrapper)
	wrapper.free()
	if pack_error != OK:
		return _failure("FPE_HAND_PROFILE_PACK_ADAPTED_SCENE_FAILED", {"error": int(pack_error)})
	return _success({
		"scene": packed,
		"selected_mesh_count": selected.size(),
		"profile_id": String(hand_asset_profile.get("profile_id", "")),
	})


func _select_skinned_meshes(
	root: Node3D,
	selection: Dictionary,
	hand_id: String
) -> Array[MeshInstance3D]:
	var selected: Array[MeshInstance3D] = []
	var by_hand_value: Variant = selection.get("mesh_node_paths_by_hand", {})
	var explicit_paths: Array = []
	if by_hand_value is Dictionary:
		var hand_value: Variant = Dictionary(by_hand_value).get(hand_id, [])
		if hand_value is Array:
			explicit_paths = hand_value
	if explicit_paths.is_empty():
		var common_value: Variant = selection.get("mesh_node_paths", [])
		if common_value is Array:
			explicit_paths = common_value
	if not explicit_paths.is_empty():
		for raw_path in explicit_paths:
			var node := root.get_node_or_null(NodePath(String(raw_path)))
			if node is MeshInstance3D:
				var mesh_instance := node as MeshInstance3D
				if mesh_instance.mesh != null and mesh_instance.skin != null:
					selected.append(mesh_instance)
		return selected
	if bool(selection.get("recursive_mesh_discovery", true)):
		_collect_skinned_recursive(root, selected)
	return selected


func _collect_skinned_recursive(node: Node, output: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh != null and mesh_instance.skin != null:
			output.append(mesh_instance)
	for child in node.get_children():
		_collect_skinned_recursive(child, output)


func _relative_transform_to_root(node: Node3D, root: Node3D) -> Transform3D:
	var chain: Array[Transform3D] = []
	var current: Node = node
	while current != null and current != root:
		if current is Node3D:
			chain.push_front((current as Node3D).transform)
		current = current.get_parent()
	var result := Transform3D.IDENTITY
	for transform in chain:
		result = result * transform
	return result


func _profile_transform(presentation: Dictionary) -> Transform3D:
	var position := _vector3_from_array(presentation.get("position", []), Vector3.ZERO)
	var rotation_deg := _vector3_from_array(presentation.get("rotation_degrees", []), Vector3.ZERO)
	var scale := _vector3_from_array(presentation.get("scale", []), Vector3.ONE)
	var basis := Basis.from_euler(Vector3(
		deg_to_rad(rotation_deg.x),
		deg_to_rad(rotation_deg.y),
		deg_to_rad(rotation_deg.z)
	)).scaled(scale)
	return Transform3D(basis, position)


func _vector3_from_array(value: Variant, fallback: Vector3) -> Vector3:
	if value is Vector3:
		return value as Vector3
	if value is Array and value.size() >= 3:
		return Vector3(float(value[0]), float(value[1]), float(value[2]))
	return fallback


func _set_owner_recursive(node: Node, owner: Node) -> void:
	node.owner = owner
	for child in node.get_children():
		_set_owner_recursive(child, owner)
