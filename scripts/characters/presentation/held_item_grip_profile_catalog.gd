class_name HeldItemGripProfileCatalog
extends RefCounted


func resolve(
	definition_id: String,
	visual_descriptor: Dictionary,
	tags = [],
	metadata: Dictionary = {}
) -> Dictionary:
	var visual_kind := String(visual_descriptor.get("visual_kind", "BOX")).to_upper()
	var visual_profile := String(visual_descriptor.get("profile_id", "generic_box"))
	var normalized_id := _normalize_token(definition_id)
	var normalized_tags := _normalize_tags(tags)
	var profile_id := visual_profile

	var first_position := Vector3(0.0, 0.0, -0.17)
	var first_rotation := Vector3(-12.0, 0.0, 0.0)
	var first_scale := Vector3.ONE
	var third_position := Vector3(0.0, -0.035, -0.075)
	var third_rotation := Vector3(5.0, 0.0, 90.0)
	var third_scale := Vector3.ONE

	var two_hand_required := false
	var secondary_pose_id := "support_wrap"
	var secondary_anchor_position := Vector3(-0.18, 0.0, 0.02)
	var secondary_anchor_rotation := Vector3(0.0, 0.0, 0.0)
	var secondary_anchor_scale := Vector3.ONE
	var secondary_hand_position := Vector3.ZERO
	var secondary_hand_rotation := Vector3(0.0, 0.0, 0.0)
	var secondary_hand_scale := Vector3.ONE

	if _contains_any(normalized_id, normalized_tags, ["flashlight", "torch", "lamp"]):
		profile_id = "flashlight_forward"
		first_position = Vector3(0.0, -0.005, -0.20)
		first_rotation = Vector3(0.0, 0.0, 90.0)
		third_position = Vector3(0.0, -0.025, -0.095)
		third_rotation = Vector3(0.0, 0.0, 0.0)
	elif _contains_any(normalized_id, normalized_tags, ["beacon", "signal", "locator"]):
		profile_id = "beacon_vertical"
		first_position = Vector3(0.0, -0.015, -0.18)
		first_rotation = Vector3(0.0, 0.0, 0.0)
		third_position = Vector3(0.0, -0.045, -0.055)
		third_rotation = Vector3(0.0, 0.0, 8.0)
	elif _contains_any(normalized_id, normalized_tags, ["mountbase", "mount-base", "fixturebase", "structuralbase"]):
		# The playable CH9.6 sandbox seeds item/mount-base into hotbar slot 2.
		# Treat it as the bounded S4 two-hand demonstration object: the item itself
		# remains canonical, while only the local presentation asks the left hand
		# to occupy a secondary support anchor.
		profile_id = "mount_base_two_hand"
		first_position = Vector3(0.0, 0.005, -0.205)
		first_rotation = Vector3(-8.0, 8.0, 4.0)
		third_position = Vector3(0.0, -0.055, -0.10)
		third_rotation = Vector3(8.0, 0.0, 78.0)
		two_hand_required = true
		secondary_pose_id = "support_cradle"
		secondary_anchor_position = Vector3(-0.20, 0.01, 0.01)
		secondary_anchor_rotation = Vector3(0.0, 0.0, -8.0)
	elif _contains_any(normalized_id, normalized_tags, ["rifle", "carbine", "longgun", "twohand", "two-handed", "large_tool"]):
		profile_id = "two_hand_long"
		first_position = Vector3(0.015, -0.01, -0.22)
		first_rotation = Vector3(0.0, 0.0, 90.0)
		third_position = Vector3(0.0, -0.04, -0.10)
		third_rotation = Vector3(0.0, 0.0, 0.0)
		two_hand_required = true
		secondary_pose_id = "support_wrap"
		secondary_anchor_position = Vector3(0.0, -0.16, 0.0)
		secondary_anchor_rotation = Vector3(0.0, 0.0, 0.0)
	elif _contains_any(normalized_id, normalized_tags, ["backpack", "rucksack", "pack"]):
		profile_id = "bulky_carry"
		first_position = Vector3(0.02, 0.015, -0.20)
		first_rotation = Vector3(-15.0, 10.0, 0.0)
		first_scale = Vector3(0.85, 0.85, 0.85)
		third_position = Vector3(0.0, -0.06, -0.10)
		third_rotation = Vector3(10.0, 0.0, 75.0)
		third_scale = Vector3(0.85, 0.85, 0.85)
	elif _contains_any(normalized_id, normalized_tags, ["helmet", "headgear"]):
		profile_id = "bulky_round"
		first_position = Vector3(0.0, 0.015, -0.19)
		first_rotation = Vector3(-10.0, 0.0, 0.0)
		first_scale = Vector3(0.85, 0.85, 0.85)
		third_position = Vector3(0.0, -0.06, -0.08)
		third_rotation = Vector3(0.0, 0.0, 75.0)
		third_scale = Vector3(0.85, 0.85, 0.85)
	elif visual_kind in ["CYLINDER", "CAPSULE"]:
		profile_id = "generic_long"
		first_position = Vector3(0.0, -0.01, -0.19)
		first_rotation = Vector3(0.0, 0.0, 90.0)
		third_position = Vector3(0.0, -0.035, -0.085)
		third_rotation = Vector3(0.0, 0.0, 0.0)

	var metadata_profile := String(metadata.get("held_grip_profile", "")).strip_edges()
	if not metadata_profile.is_empty():
		profile_id = metadata_profile

	first_position = _metadata_vector3(metadata, "held_fp_position", first_position)
	first_rotation = _metadata_vector3(metadata, "held_fp_rotation_deg", first_rotation)
	first_scale = _metadata_vector3(metadata, "held_fp_scale", first_scale)
	third_position = _metadata_vector3(metadata, "held_tp_position", third_position)
	third_rotation = _metadata_vector3(metadata, "held_tp_rotation_deg", third_rotation)
	third_scale = _metadata_vector3(metadata, "held_tp_scale", third_scale)

	if metadata.has("held_two_hand"):
		two_hand_required = bool(metadata.get("held_two_hand", false))
	var metadata_secondary_pose := String(metadata.get("held_secondary_pose", "")).strip_edges()
	if not metadata_secondary_pose.is_empty():
		secondary_pose_id = metadata_secondary_pose
	secondary_anchor_position = _metadata_vector3(metadata, "held_secondary_anchor_position", secondary_anchor_position)
	secondary_anchor_rotation = _metadata_vector3(metadata, "held_secondary_anchor_rotation_deg", secondary_anchor_rotation)
	secondary_anchor_scale = _metadata_vector3(metadata, "held_secondary_anchor_scale", secondary_anchor_scale)
	secondary_hand_position = _metadata_vector3(metadata, "held_secondary_hand_position", secondary_hand_position)
	secondary_hand_rotation = _metadata_vector3(metadata, "held_secondary_hand_rotation_deg", secondary_hand_rotation)
	secondary_hand_scale = _metadata_vector3(metadata, "held_secondary_hand_scale", secondary_hand_scale)

	return {
		"schema": "planet_simulator.held_item_grip_profile.v2",
		"definition_id": definition_id,
		"profile_id": profile_id,
		"first_person": _transform_dict(first_position, first_rotation, first_scale),
		"third_person": _transform_dict(third_position, third_rotation, third_scale),
		"two_hand": {
			"required": two_hand_required,
			"primary_hand": "right",
			"secondary_hand": "left",
			"secondary_pose_id": secondary_pose_id,
			"secondary_anchor": _transform_dict(
				secondary_anchor_position,
				secondary_anchor_rotation,
				secondary_anchor_scale
			),
			"secondary_hand_transform": _transform_dict(
				secondary_hand_position,
				secondary_hand_rotation,
				secondary_hand_scale
			),
			"presentation_only": true,
		},
		"presentation_only": true,
		"owns_gameplay_transform": false,
		"owns_item_state": false,
		"owns_network_state": false,
	}


func _transform_dict(position: Vector3, rotation_deg: Vector3, scale: Vector3) -> Dictionary:
	return {
		"position": [position.x, position.y, position.z],
		"rotation_deg": [rotation_deg.x, rotation_deg.y, rotation_deg.z],
		"scale": [scale.x, scale.y, scale.z],
	}


func _contains_any(normalized_id: String, normalized_tags: Array[String], needles: Array[String]) -> bool:
	for needle in needles:
		var normalized_needle := _normalize_token(needle)
		if normalized_id.contains(normalized_needle):
			return true
		for tag in normalized_tags:
			if tag.contains(normalized_needle):
				return true
	return false


func _normalize_tags(tags) -> Array[String]:
	var result: Array[String] = []
	for raw_tag in tags:
		result.append(_normalize_token(String(raw_tag)))
	return result


func _normalize_token(value: String) -> String:
	var normalized := value.to_lower()
	for token in ["_", "-", ".", ":", " ", "/", "\\"]:
		normalized = normalized.replace(token, "")
	return normalized


func _metadata_vector3(metadata: Dictionary, key: String, fallback: Vector3) -> Vector3:
	var value: Variant = metadata.get(key)
	if value is Vector3:
		return value as Vector3
	if value is Array:
		var components: Array = value
		if components.size() >= 3:
			return Vector3(
				float(components[0]),
				float(components[1]),
				float(components[2])
			)
	return fallback
