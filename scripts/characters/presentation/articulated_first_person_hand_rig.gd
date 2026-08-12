class_name ArticulatedFirstPersonHandRig
extends Node3D

const HAND_LEFT := "left"
const HAND_RIGHT := "right"
const FINGERS: Array[String] = ["thumb", "index", "middle", "ring", "pinky"]
const SEGMENT_NAMES: Array[String] = ["Proximal", "Middle", "Distal"]
const DEFAULT_VIEWMODEL_LAYER := 19

var hand_id := ""
var viewmodel_layer_index := DEFAULT_VIEWMODEL_LAYER
var skeleton: Skeleton3D
var pose_root: Node3D
var current_pose_id := ""
var settled_pose_id := ""

var _finger_bones: Dictionary = {}
var _visual_segments: Array[MeshInstance3D] = []
var _hand_material: StandardMaterial3D
var _start_rotations: Dictionary = {}
var _target_rotations: Dictionary = {}
var _transition_elapsed := 0.0
var _transition_duration := 0.0
var _pose_apply_count := 0
var _configured := false


func setup(p_hand_id: String, p_viewmodel_layer_index: int = DEFAULT_VIEWMODEL_LAYER) -> Dictionary:
	var normalized := p_hand_id.strip_edges().to_lower()
	if normalized not in [HAND_LEFT, HAND_RIGHT]:
		return _failure("FPE_HAND_RIG_INVALID_HAND", {"hand_id": p_hand_id})
	if p_viewmodel_layer_index < 1 or p_viewmodel_layer_index > 20:
		return _failure("FPE_HAND_RIG_INVALID_LAYER", {"layer": p_viewmodel_layer_index})

	hand_id = normalized
	viewmodel_layer_index = p_viewmodel_layer_index
	position = Vector3(0.0, -0.08, -0.17)

	pose_root = Node3D.new()
	pose_root.name = "%sArticulatedPoseRoot" % hand_id.capitalize()
	add_child(pose_root)

	skeleton = Skeleton3D.new()
	skeleton.name = "%sHandSkeleton" % hand_id.capitalize()
	pose_root.add_child(skeleton)

	_hand_material = StandardMaterial3D.new()
	_hand_material.albedo_color = Color(0.72, 0.54, 0.43, 1.0)
	_hand_material.roughness = 0.82

	_build_skeleton()
	_build_visuals()
	_configured = skeleton.get_bone_count() >= 17 and _visual_segments.size() >= 16
	set_process(false)
	return _success(create_report()) if _configured else _failure("FPE_HAND_RIG_BUILD_INCOMPLETE", create_report())


func apply_pose(pose: Dictionary) -> Dictionary:
	if not _configured or skeleton == null:
		return _failure("FPE_HAND_RIG_NOT_CONFIGURED")
	var pose_id := String(pose.get("pose_id", "")).strip_edges()
	var finger_curl_value: Variant = pose.get("finger_curl_deg", {})
	if pose_id.is_empty() or not finger_curl_value is Dictionary:
		return _failure("FPE_HAND_POSE_INVALID", {"pose_id": pose_id})

	var finger_curl: Dictionary = finger_curl_value
	var opposition_deg := float(pose.get("thumb_opposition_deg", 0.0))
	_start_rotations.clear()
	_target_rotations.clear()
	for finger in FINGERS:
		var chain_value: Variant = _finger_bones.get(finger, [])
		if not chain_value is Array:
			continue
		var chain: Array = chain_value
		var curls_value: Variant = finger_curl.get(finger, [])
		var curls: Array = curls_value if curls_value is Array else []
		for segment_index in range(mini(chain.size(), 3)):
			var bone_index := int(chain[segment_index])
			var curl_deg := float(curls[segment_index]) if segment_index < curls.size() else 0.0
			var euler := Vector3(deg_to_rad(curl_deg), 0.0, 0.0)
			if finger == "thumb" and segment_index == 0:
				var side := -1.0 if hand_id == HAND_LEFT else 1.0
				euler.y = deg_to_rad(opposition_deg * side)
			_start_rotations[bone_index] = skeleton.get_bone_pose_rotation(bone_index)
			_target_rotations[bone_index] = Basis.from_euler(euler).get_rotation_quaternion()

	var wrist_rotation := _array_vector3(pose.get("wrist_rotation_deg", []), Vector3.ZERO)
	if hand_id == HAND_LEFT:
		wrist_rotation.y *= -1.0
		wrist_rotation.z *= -1.0
	pose_root.rotation_degrees = wrist_rotation

	_transition_elapsed = 0.0
	_transition_duration = maxf(float(pose.get("transition_ms", 100)) / 1000.0, 0.0)
	current_pose_id = pose_id
	_pose_apply_count += 1
	if _transition_duration <= 0.0001:
		_apply_transition(1.0)
		settled_pose_id = current_pose_id
		set_process(false)
	else:
		set_process(true)
	return _success({
		"pose_id": pose_id,
		"transition_ms": int(round(_transition_duration * 1000.0)),
		"bone_targets": _target_rotations.size(),
		"presentation_only": true,
	})


func _process(delta: float) -> void:
	if _transition_duration <= 0.0001:
		set_process(false)
		return
	_transition_elapsed += maxf(delta, 0.0)
	var weight := clampf(_transition_elapsed / _transition_duration, 0.0, 1.0)
	# Smoothstep keeps a visible pose change from snapping while remaining cheap:
	# only the 15 finger bones are touched, and processing stops when settled.
	var eased := weight * weight * (3.0 - 2.0 * weight)
	_apply_transition(eased)
	if weight >= 1.0:
		settled_pose_id = current_pose_id
		set_process(false)


func create_report() -> Dictionary:
	return {
		"schema": "planet_simulator.articulated_first_person_hand_rig.v1",
		"configured": _configured,
		"hand_id": hand_id,
		"skeleton_present": skeleton != null,
		"bone_count": skeleton.get_bone_count() if skeleton != null else 0,
		"finger_chains": _finger_bones.size(),
		"visual_segments": _visual_segments.size(),
		"viewmodel_layer_index": viewmodel_layer_index,
		"current_pose_id": current_pose_id,
		"settled_pose_id": settled_pose_id,
		"transitioning": is_processing(),
		"pose_apply_count": _pose_apply_count,
		"presentation_only": true,
		"owns_item_state": false,
		"owns_network_state": false,
		"owns_gameplay_transform": false,
	}


func _build_skeleton() -> void:
	var root_index := _add_bone("HandRoot", -1, Transform3D.IDENTITY)
	var palm_index := _add_bone("Palm", root_index, Transform3D.IDENTITY)
	var side := -1.0 if hand_id == HAND_LEFT else 1.0

	_add_finger_chain(
		"thumb",
		palm_index,
		Vector3(0.052 * side, -0.005, -0.018),
		[0.052, 0.043, 0.034],
		Basis.from_euler(Vector3(deg_to_rad(-8.0), deg_to_rad(34.0 * side), deg_to_rad(-18.0 * side)))
	)
	_add_finger_chain("index", palm_index, Vector3(0.040 * side, 0.0, -0.054), [0.062, 0.050, 0.038])
	_add_finger_chain("middle", palm_index, Vector3(0.013 * side, 0.0, -0.058), [0.068, 0.054, 0.040])
	_add_finger_chain("ring", palm_index, Vector3(-0.015 * side, -0.002, -0.054), [0.064, 0.050, 0.037])
	_add_finger_chain("pinky", palm_index, Vector3(-0.040 * side, -0.004, -0.047), [0.054, 0.043, 0.032])


func _add_finger_chain(
	finger: String,
	parent_index: int,
	base_origin: Vector3,
	lengths: Array,
	base_basis: Basis = Basis.IDENTITY
) -> void:
	var chain: Array = []
	var previous := parent_index
	for segment_index in range(3):
		var origin := base_origin if segment_index == 0 else Vector3(0.0, 0.0, -float(lengths[segment_index - 1]))
		var basis := base_basis if segment_index == 0 else Basis.IDENTITY
		var bone_name := "%s%s" % [finger.capitalize(), SEGMENT_NAMES[segment_index]]
		var index := _add_bone(bone_name, previous, Transform3D(basis, origin))
		chain.append(index)
		previous = index
	_finger_bones[finger] = chain


func _add_bone(bone_name: String, parent_index: int, rest: Transform3D) -> int:
	skeleton.add_bone(bone_name)
	var index := skeleton.get_bone_count() - 1
	if parent_index >= 0:
		skeleton.set_bone_parent(index, parent_index)
	skeleton.set_bone_rest(index, rest)
	return index


func _build_visuals() -> void:
	var palm_index := skeleton.find_bone("Palm")
	if palm_index >= 0:
		var palm_attachment := _attachment_for_bone(palm_index, "PalmVisualAttachment")
		var palm := MeshInstance3D.new()
		palm.name = "ArticulatedPalm"
		var palm_mesh := BoxMesh.new()
		palm_mesh.size = Vector3(0.105, 0.045, 0.115)
		palm.mesh = palm_mesh
		palm.position = Vector3(0.0, 0.0, -0.028)
		_configure_visual(palm)
		palm_attachment.add_child(palm)

	for finger in FINGERS:
		var chain_value: Variant = _finger_bones.get(finger, [])
		if not chain_value is Array:
			continue
		var chain: Array = chain_value
		var lengths := _finger_lengths(finger)
		for segment_index in range(chain.size()):
			var bone_index := int(chain[segment_index])
			var length := float(lengths[segment_index])
			var attachment := _attachment_for_bone(
				bone_index,
				"%s%sVisualAttachment" % [finger.capitalize(), SEGMENT_NAMES[segment_index]]
			)
			var segment := MeshInstance3D.new()
			segment.name = "%s%sVisual" % [finger.capitalize(), SEGMENT_NAMES[segment_index]]
			var mesh := CapsuleMesh.new()
			var radius := 0.013 if finger != "thumb" else 0.014
			if segment_index == 2:
				radius *= 0.88
			mesh.radius = radius
			mesh.height = maxf(length, radius * 2.05)
			segment.mesh = mesh
			segment.position = Vector3(0.0, 0.0, -length * 0.5)
			segment.rotation_degrees.x = 90.0
			_configure_visual(segment)
			attachment.add_child(segment)


func _attachment_for_bone(bone_index: int, attachment_name: String) -> BoneAttachment3D:
	var attachment := BoneAttachment3D.new()
	attachment.name = attachment_name
	attachment.bone_name = skeleton.get_bone_name(bone_index)
	skeleton.add_child(attachment)
	return attachment


func _configure_visual(visual: MeshInstance3D) -> void:
	visual.material_override = _hand_material
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	visual.layers = 0
	visual.set_layer_mask_value(viewmodel_layer_index, true)
	_visual_segments.append(visual)


func _finger_lengths(finger: String) -> Array:
	match finger:
		"thumb":
			return [0.052, 0.043, 0.034]
		"index":
			return [0.062, 0.050, 0.038]
		"middle":
			return [0.068, 0.054, 0.040]
		"ring":
			return [0.064, 0.050, 0.037]
		_:
			return [0.054, 0.043, 0.032]


func _apply_transition(weight: float) -> void:
	for key in _target_rotations.keys():
		var bone_index := int(key)
		var start_value: Variant = _start_rotations.get(bone_index, Quaternion.IDENTITY)
		var target_value: Variant = _target_rotations.get(bone_index, Quaternion.IDENTITY)
		if start_value is Quaternion and target_value is Quaternion:
			skeleton.set_bone_pose_rotation(
				bone_index,
				(start_value as Quaternion).slerp(target_value as Quaternion, weight)
			)


func _array_vector3(value: Variant, fallback: Vector3) -> Vector3:
	if value is Vector3:
		return value as Vector3
	if value is Array:
		var components: Array = value
		if components.size() >= 3:
			return Vector3(float(components[0]), float(components[1]), float(components[2]))
	return fallback


func _success(details: Dictionary = {}) -> Dictionary:
	return {"success": true, "error_code": "", "details": details.duplicate(true)}


func _failure(error_code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": error_code, "details": details.duplicate(true)}
