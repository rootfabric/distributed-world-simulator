class_name SkinnedFirstPersonHandVisualProvider
extends RefCounted

const ASSET_SCHEMA := "planet_simulator.fpe_skinned_hand_visual_asset.v1"
const SKELETON_SCHEMA := "planet_simulator.fpe_hand_skeleton.v1"
const MODE := "RESOURCE_SKINNED_RETARGETED"
const REST_SPACE_POLICY := "CANONICAL_COMPATIBLE_BIND_SPACE"
const REQUIRED_BONES: Array[String] = [
	"HandRoot", "Palm",
	"ThumbProximal", "ThumbMiddle", "ThumbDistal",
	"IndexProximal", "IndexMiddle", "IndexDistal",
	"MiddleProximal", "MiddleMiddle", "MiddleDistal",
	"RingProximal", "RingMiddle", "RingDistal",
	"PinkyProximal", "PinkyMiddle", "PinkyDistal",
]

var packed_scene: PackedScene
var resource_path := ""
var provider_id := ""
var _last_report: Dictionary = {}


func setup(p_scene: PackedScene, p_resource_path: String = "") -> Dictionary:
	if p_scene == null:
		return _failure("FPE_S8_SKINNED_HAND_SCENE_REQUIRED")
	packed_scene = p_scene
	resource_path = p_resource_path.strip_edges()
	provider_id = resource_path if not resource_path.is_empty() else "packed_scene_skinned_hand"
	return _success({
		"resource_path": resource_path,
		"provider_id": provider_id,
		"asset_schema": ASSET_SCHEMA,
		"rest_space_policy": REST_SPACE_POLICY,
	})


func install_visuals(
	skeleton: Skeleton3D,
	hand_id: String,
	viewmodel_layer_index: int
) -> Dictionary:
	if packed_scene == null:
		return _failure("FPE_S8_SKINNED_HAND_PROVIDER_NOT_CONFIGURED")
	if skeleton == null:
		return _failure("FPE_S8_SKINNED_HAND_SKELETON_REQUIRED")
	var normalized_hand := hand_id.strip_edges().to_lower()
	if normalized_hand not in ["left", "right"]:
		return _failure("FPE_S8_SKINNED_HAND_INVALID_HAND", {"hand_id": hand_id})
	if viewmodel_layer_index < 1 or viewmodel_layer_index > 20:
		return _failure("FPE_S8_SKINNED_HAND_INVALID_LAYER", {"layer": viewmodel_layer_index})

	for bone_name in REQUIRED_BONES:
		if skeleton.find_bone(bone_name) < 0:
			return _failure("FPE_S8_CANONICAL_SKELETON_INCOMPATIBLE", {
				"missing_bone": bone_name,
				"required_schema": SKELETON_SCHEMA,
			})

	var instance: Node = packed_scene.instantiate()
	if not instance is Node3D:
		if instance != null:
			instance.free()
		return _failure("FPE_S8_SKINNED_HAND_ROOT_MUST_BE_NODE3D")
	var asset_root := instance as Node3D
	var asset_schema := String(asset_root.get_meta("fpe_hand_visual_schema", ""))
	var skeleton_schema := String(asset_root.get_meta("fpe_compatible_skeleton_schema", ""))
	var asset_hand := String(asset_root.get_meta("fpe_hand", "both")).strip_edges().to_lower()
	var rest_space := String(asset_root.get_meta("fpe_rest_space_policy", ""))
	var asset_provider_id := String(asset_root.get_meta("fpe_provider_id", provider_id)).strip_edges()
	var bone_map_value: Variant = asset_root.get_meta("fpe_bone_map", {})
	var bone_map: Dictionary = Dictionary(bone_map_value) if bone_map_value is Dictionary else {}

	if asset_schema != ASSET_SCHEMA:
		asset_root.free()
		return _failure("FPE_S8_SKINNED_HAND_ASSET_SCHEMA_MISMATCH", {
			"actual": asset_schema,
			"required": ASSET_SCHEMA,
		})
	if skeleton_schema != SKELETON_SCHEMA:
		asset_root.free()
		return _failure("FPE_S8_SKINNED_HAND_SKELETON_SCHEMA_MISMATCH", {
			"actual": skeleton_schema,
			"required": SKELETON_SCHEMA,
		})
	if rest_space != REST_SPACE_POLICY:
		asset_root.free()
		return _failure("FPE_S8_SKINNED_HAND_REST_SPACE_UNSUPPORTED", {
			"actual": rest_space,
			"required": REST_SPACE_POLICY,
		})
	if asset_hand not in ["both", normalized_hand]:
		asset_root.free()
		return _failure("FPE_S8_SKINNED_HAND_HAND_MISMATCH", {
			"asset_hand": asset_hand,
			"requested_hand": normalized_hand,
		})

	var skinned_meshes: Array[MeshInstance3D] = []
	for child in asset_root.get_children():
		if child is MeshInstance3D:
			var mesh_instance := child as MeshInstance3D
			if mesh_instance.mesh != null and mesh_instance.skin != null:
				skinned_meshes.append(mesh_instance)
	if skinned_meshes.is_empty():
		asset_root.free()
		return _failure("FPE_S8_SKINNED_HAND_NO_DIRECT_SKINNED_MESHES")

	var total_bind_count := 0
	var mapped_bind_count := 0
	var identity_bind_count := 0
	var weighted_surface_count := 0
	var resolved_bindings: Dictionary = {}
	var installed_visuals: Array[MeshInstance3D] = []

	for mesh_instance in skinned_meshes:
		if not mesh_instance.mesh is ArrayMesh:
			asset_root.free()
			return _failure("FPE_S8_SKINNED_HAND_MESH_MUST_BE_ARRAY_MESH", {
				"mesh": mesh_instance.name,
			})
		var array_mesh := mesh_instance.mesh as ArrayMesh
		var weighted_result := _validate_weighted_mesh(array_mesh, mesh_instance.name)
		if not bool(weighted_result.get("success", false)):
			asset_root.free()
			return weighted_result
		weighted_surface_count += int(Dictionary(weighted_result.get("details", {})).get("weighted_surfaces", 0))

		var source_skin := mesh_instance.skin
		if source_skin == null or source_skin.get_bind_count() <= 0:
			asset_root.free()
			return _failure("FPE_S8_SKINNED_HAND_SKIN_BINDS_REQUIRED", {"mesh": mesh_instance.name})
		var target_skin := Skin.new()
		target_skin.set_bind_count(source_skin.get_bind_count())
		for bind_index in range(source_skin.get_bind_count()):
			var source_name := String(source_skin.get_bind_name(bind_index)).strip_edges()
			if source_name.is_empty():
				asset_root.free()
				return _failure("FPE_S8_INDEX_ONLY_SKIN_UNSUPPORTED", {
					"mesh": mesh_instance.name,
					"bind_index": bind_index,
				})
			var canonical_name := _resolve_canonical_bone(source_name, bone_map, skeleton)
			if canonical_name.is_empty():
				asset_root.free()
				return _failure("FPE_S8_SKIN_BIND_RETARGET_UNRESOLVED", {
					"mesh": mesh_instance.name,
					"source_bone": source_name,
				})
			var canonical_index := skeleton.find_bone(canonical_name)
			if canonical_index < 0:
				asset_root.free()
				return _failure("FPE_S8_SKIN_BIND_TARGET_MISSING", {
					"source_bone": source_name,
					"canonical_bone": canonical_name,
				})
			target_skin.set_bind_name(bind_index, StringName(canonical_name))
			target_skin.set_bind_bone(bind_index, canonical_index)
			target_skin.set_bind_pose(bind_index, source_skin.get_bind_pose(bind_index))
			resolved_bindings[source_name] = canonical_name
			total_bind_count += 1
			if source_name == canonical_name:
				identity_bind_count += 1
			else:
				mapped_bind_count += 1

		mesh_instance.skin = target_skin
		mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mesh_instance.layers = 0
		mesh_instance.set_layer_mask_value(viewmodel_layer_index, true)
		_clear_owner_recursive(mesh_instance)
		asset_root.remove_child(mesh_instance)
		skeleton.add_child(mesh_instance)
		# Godot 4.6+ defaults MeshInstance3D.skeleton to an empty NodePath,
		# so bind explicitly to the canonical Skeleton3D parent.
		mesh_instance.skeleton = NodePath("..")
		installed_visuals.append(mesh_instance)

	asset_root.free()
	provider_id = asset_provider_id if not asset_provider_id.is_empty() else provider_id
	_last_report = create_report(
		installed_visuals.size(),
		total_bind_count,
		mapped_bind_count,
		identity_bind_count,
		weighted_surface_count,
		normalized_hand,
		resolved_bindings
	)
	return _success({
		"visuals": installed_visuals,
		"report": _last_report.duplicate(true),
	})


func create_report(
	installed_visual_count: int = 0,
	bind_count: int = 0,
	mapped_bind_count: int = 0,
	identity_bind_count: int = 0,
	weighted_surface_count: int = 0,
	hand_id: String = "",
	resolved_bindings: Dictionary = {}
) -> Dictionary:
	return {
		"schema": "planet_simulator.fpe_skinned_hand_visual_provider.v1",
		"provider_id": provider_id,
		"mode": MODE,
		"asset_schema": ASSET_SCHEMA,
		"compatible_skeleton_schema": SKELETON_SCHEMA,
		"rest_space_policy": REST_SPACE_POLICY,
		"resource_path": resource_path,
		"hand_id": hand_id,
		"installed_visual_count": installed_visual_count,
		"skinned_mesh_count": installed_visual_count,
		"skin_bind_count": bind_count,
		"retargeted_bind_count": mapped_bind_count,
		"identity_bind_count": identity_bind_count,
		"weighted_surface_count": weighted_surface_count,
		"resolved_bindings": resolved_bindings.duplicate(true),
		"skinned": true,
		"bone_driven": true,
		"resource_backed": true,
		"retargeted": true,
		"substitutable": true,
		"presentation_only": true,
		"owns_item_state": false,
		"owns_network_state": false,
		"owns_gameplay_transform": false,
	}


func _validate_weighted_mesh(array_mesh: ArrayMesh, mesh_name: String) -> Dictionary:
	var weighted_surfaces := 0
	for surface_index in range(array_mesh.get_surface_count()):
		var arrays: Array = array_mesh.surface_get_arrays(surface_index)
		if arrays.size() < Mesh.ARRAY_MAX:
			continue
		var vertices_value: Variant = arrays[Mesh.ARRAY_VERTEX]
		var bones_value: Variant = arrays[Mesh.ARRAY_BONES]
		var weights_value: Variant = arrays[Mesh.ARRAY_WEIGHTS]
		if typeof(vertices_value) != TYPE_PACKED_VECTOR3_ARRAY:
			continue
		var vertex_count := (vertices_value as PackedVector3Array).size()
		if vertex_count <= 0:
			continue
		var bones_count := _packed_numeric_size(bones_value)
		var weights_count := _packed_numeric_size(weights_value)
		if bones_count == vertex_count * 4 and weights_count == vertex_count * 4:
			weighted_surfaces += 1
	if weighted_surfaces <= 0:
		return _failure("FPE_S8_SKINNED_HAND_WEIGHT_DATA_REQUIRED", {"mesh": mesh_name})
	return _success({"mesh": mesh_name, "weighted_surfaces": weighted_surfaces})


func _packed_numeric_size(value: Variant) -> int:
	match typeof(value):
		TYPE_PACKED_INT32_ARRAY:
			return (value as PackedInt32Array).size()
		TYPE_PACKED_FLOAT32_ARRAY:
			return (value as PackedFloat32Array).size()
		TYPE_PACKED_FLOAT64_ARRAY:
			return (value as PackedFloat64Array).size()
		_:
			return 0


func _resolve_canonical_bone(
	source_name: String,
	bone_map: Dictionary,
	skeleton: Skeleton3D
) -> String:
	if bone_map.has(source_name):
		return String(bone_map.get(source_name, "")).strip_edges()
	if skeleton.find_bone(source_name) >= 0:
		return source_name
	return ""


func _clear_owner_recursive(node: Node) -> void:
	node.owner = null
	for child in node.get_children():
		_clear_owner_recursive(child)


func _success(details: Dictionary = {}) -> Dictionary:
	return {"success": true, "error_code": "", "details": details}


func _failure(error_code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": error_code, "details": details.duplicate(true)}
