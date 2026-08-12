class_name FirstPersonHandVisualProvider
extends RefCounted

const PROVIDER_ID := "procedural_segments_v1"
const MODE := "PROCEDURAL_SEGMENTS"
const SKELETON_SCHEMA := "planet_simulator.fpe_hand_skeleton.v1"
const FINGERS: Array[String] = ["thumb", "index", "middle", "ring", "pinky"]
const SEGMENT_NAMES: Array[String] = ["Proximal", "Middle", "Distal"]


func install_visuals(
	skeleton: Skeleton3D,
	hand_id: String,
	viewmodel_layer_index: int
) -> Dictionary:
	if skeleton == null:
		return _failure("FPE_S6_HAND_VISUAL_SKELETON_REQUIRED")
	var normalized_hand := hand_id.strip_edges().to_lower()
	if normalized_hand not in ["left", "right"]:
		return _failure("FPE_S6_HAND_VISUAL_INVALID_HAND", {"hand_id": hand_id})
	if viewmodel_layer_index < 1 or viewmodel_layer_index > 20:
		return _failure("FPE_S6_HAND_VISUAL_INVALID_LAYER", {"layer": viewmodel_layer_index})
	if skeleton.get_bone_count() < 17:
		return _failure("FPE_S6_HAND_VISUAL_SKELETON_INCOMPATIBLE", {
			"bone_count": skeleton.get_bone_count(),
			"required_schema": SKELETON_SCHEMA,
		})

	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.72, 0.54, 0.43, 1.0)
	material.roughness = 0.82
	var visuals: Array[MeshInstance3D] = []

	var palm_index := skeleton.find_bone("Palm")
	if palm_index < 0:
		return _failure("FPE_S6_HAND_VISUAL_PALM_BONE_MISSING")
	var palm_attachment := _attachment_for_bone(skeleton, palm_index, "S6PalmVisualAttachment")
	var palm := MeshInstance3D.new()
	palm.name = "S6ArticulatedPalm"
	var palm_mesh := BoxMesh.new()
	palm_mesh.size = Vector3(0.105, 0.045, 0.115)
	palm.mesh = palm_mesh
	palm.position = Vector3(0.0, 0.0, -0.028)
	_configure_visual(palm, material, viewmodel_layer_index)
	palm_attachment.add_child(palm)
	visuals.append(palm)

	for finger in FINGERS:
		var lengths := _finger_lengths(finger)
		for segment_index in range(3):
			var bone_name := "%s%s" % [finger.capitalize(), SEGMENT_NAMES[segment_index]]
			var bone_index := skeleton.find_bone(bone_name)
			if bone_index < 0:
				return _failure("FPE_S6_HAND_VISUAL_FINGER_BONE_MISSING", {
					"finger": finger,
					"bone_name": bone_name,
				})
			var length := float(lengths[segment_index])
			var attachment := _attachment_for_bone(
				skeleton,
				bone_index,
				"S6%s%sVisualAttachment" % [finger.capitalize(), SEGMENT_NAMES[segment_index]]
			)
			var segment := MeshInstance3D.new()
			segment.name = "S6%s%sVisual" % [finger.capitalize(), SEGMENT_NAMES[segment_index]]
			var mesh := CapsuleMesh.new()
			var radius := 0.013 if finger != "thumb" else 0.014
			if segment_index == 2:
				radius *= 0.88
			mesh.radius = radius
			mesh.height = maxf(length, radius * 2.05)
			segment.mesh = mesh
			segment.position = Vector3(0.0, 0.0, -length * 0.5)
			segment.rotation_degrees.x = 90.0
			_configure_visual(segment, material, viewmodel_layer_index)
			attachment.add_child(segment)
			visuals.append(segment)

	return _success({
		"visuals": visuals,
		"report": create_report(visuals.size()),
	})


func create_report(installed_visual_count: int = 0) -> Dictionary:
	return {
		"schema": "planet_simulator.fpe_hand_visual_provider.v1",
		"provider_id": PROVIDER_ID,
		"mode": MODE,
		"compatible_skeleton_schema": SKELETON_SCHEMA,
		"installed_visual_count": installed_visual_count,
		"bone_driven": true,
		"substitutable": true,
		"external_provider_supported": true,
		"presentation_only": true,
		"owns_item_state": false,
		"owns_network_state": false,
		"owns_gameplay_transform": false,
	}


func _attachment_for_bone(
	skeleton: Skeleton3D,
	bone_index: int,
	attachment_name: String
) -> BoneAttachment3D:
	var attachment := BoneAttachment3D.new()
	attachment.name = attachment_name
	attachment.bone_name = skeleton.get_bone_name(bone_index)
	skeleton.add_child(attachment)
	return attachment


func _configure_visual(
	visual: MeshInstance3D,
	material: Material,
	viewmodel_layer_index: int
) -> void:
	visual.material_override = material
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	visual.layers = 0
	visual.set_layer_mask_value(viewmodel_layer_index, true)


func _finger_lengths(finger: String) -> Array[float]:
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


func _success(details: Dictionary = {}) -> Dictionary:
	return {"success": true, "error_code": "", "details": details}


func _failure(error_code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": error_code, "details": details.duplicate(true)}
