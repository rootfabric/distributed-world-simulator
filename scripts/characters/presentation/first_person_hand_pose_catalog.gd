class_name FirstPersonHandPoseCatalog
extends RefCounted

const POSE_OPEN := "open"
const POSE_GENERIC_WRAP := "generic_wrap"
const POSE_FLASHLIGHT_WRAP := "flashlight_wrap"
const POSE_BEACON_PINCH := "beacon_pinch"
const POSE_BULKY_CARRY := "bulky_carry"
const POSE_ROUND_CRADLE := "round_cradle"
const POSE_LONG_WRAP := "long_wrap"


func resolve(grip_profile: Dictionary, visual_descriptor: Dictionary = {}) -> Dictionary:
	var grip_id := String(grip_profile.get("profile_id", "")).strip_edges().to_lower()
	var visual_profile := String(visual_descriptor.get("profile_id", "")).strip_edges().to_lower()
	var pose_id := POSE_GENERIC_WRAP

	if grip_id.contains("flashlight") or visual_profile.contains("flashlight"):
		pose_id = POSE_FLASHLIGHT_WRAP
	elif grip_id.contains("beacon") or visual_profile.contains("beacon"):
		pose_id = POSE_BEACON_PINCH
	elif grip_id.contains("bulky_carry") or visual_profile.contains("backpack"):
		pose_id = POSE_BULKY_CARRY
	elif grip_id.contains("bulky_round") or visual_profile.contains("helmet"):
		pose_id = POSE_ROUND_CRADLE
	elif grip_id.contains("long") or visual_profile.contains("tool"):
		pose_id = POSE_LONG_WRAP

	return get_pose(pose_id)


func get_open_pose() -> Dictionary:
	return get_pose(POSE_OPEN)


func get_pose(pose_id: String) -> Dictionary:
	var normalized := pose_id.strip_edges().to_lower()
	match normalized:
		POSE_OPEN:
			return _pose(
				POSE_OPEN,
				[6.0, 4.0, 2.0],
				[4.0, 3.0, 2.0],
				[4.0, 3.0, 2.0],
				[5.0, 4.0, 3.0],
				[7.0, 5.0, 4.0],
				-22.0,
				Vector3.ZERO,
				90
			)
		POSE_FLASHLIGHT_WRAP:
			return _pose(
				POSE_FLASHLIGHT_WRAP,
				[34.0, 42.0, 24.0],
				[52.0, 64.0, 38.0],
				[58.0, 68.0, 42.0],
				[60.0, 70.0, 44.0],
				[64.0, 72.0, 46.0],
				18.0,
				Vector3(-3.0, 0.0, 3.0),
				105
			)
		POSE_BEACON_PINCH:
			return _pose(
				POSE_BEACON_PINCH,
				[24.0, 38.0, 22.0],
				[28.0, 38.0, 20.0],
				[54.0, 66.0, 40.0],
				[62.0, 72.0, 46.0],
				[68.0, 76.0, 48.0],
				12.0,
				Vector3(-2.0, 3.0, 0.0),
				110
			)
		POSE_BULKY_CARRY:
			return _pose(
				POSE_BULKY_CARRY,
				[22.0, 30.0, 18.0],
				[32.0, 42.0, 28.0],
				[36.0, 46.0, 30.0],
				[40.0, 50.0, 32.0],
				[44.0, 52.0, 34.0],
				4.0,
				Vector3(-5.0, 4.0, 5.0),
				120
			)
		POSE_ROUND_CRADLE:
			return _pose(
				POSE_ROUND_CRADLE,
				[18.0, 26.0, 16.0],
				[24.0, 34.0, 22.0],
				[28.0, 38.0, 24.0],
				[32.0, 42.0, 26.0],
				[36.0, 44.0, 28.0],
				-2.0,
				Vector3(-7.0, 0.0, 4.0),
				120
			)
		POSE_LONG_WRAP:
			return _pose(
				POSE_LONG_WRAP,
				[30.0, 40.0, 24.0],
				[48.0, 58.0, 36.0],
				[54.0, 62.0, 40.0],
				[58.0, 66.0, 42.0],
				[62.0, 70.0, 44.0],
				14.0,
				Vector3(-4.0, 0.0, 2.0),
				105
			)
		_:
			return _pose(
				POSE_GENERIC_WRAP,
				[28.0, 38.0, 24.0],
				[44.0, 56.0, 34.0],
				[50.0, 60.0, 38.0],
				[54.0, 64.0, 40.0],
				[58.0, 68.0, 42.0],
				8.0,
				Vector3(-3.0, 0.0, 2.0),
				105
			)


func create_report() -> Dictionary:
	return {
		"schema": "planet_simulator.first_person_hand_pose_catalog.v1",
		"pose_ids": [
			POSE_OPEN,
			POSE_GENERIC_WRAP,
			POSE_FLASHLIGHT_WRAP,
			POSE_BEACON_PINCH,
			POSE_BULKY_CARRY,
			POSE_ROUND_CRADLE,
			POSE_LONG_WRAP,
		],
		"presentation_only": true,
		"owns_item_state": false,
		"owns_network_state": false,
		"owns_gameplay_transform": false,
	}


func _pose(
	pose_id: String,
	thumb: Array,
	index: Array,
	middle: Array,
	ring: Array,
	pinky: Array,
	thumb_opposition_deg: float,
	wrist_rotation_deg: Vector3,
	transition_ms: int
) -> Dictionary:
	return {
		"schema": "planet_simulator.first_person_hand_pose.v1",
		"pose_id": pose_id,
		"finger_curl_deg": {
			"thumb": thumb.duplicate(),
			"index": index.duplicate(),
			"middle": middle.duplicate(),
			"ring": ring.duplicate(),
			"pinky": pinky.duplicate(),
		},
		"thumb_opposition_deg": thumb_opposition_deg,
		"wrist_rotation_deg": [wrist_rotation_deg.x, wrist_rotation_deg.y, wrist_rotation_deg.z],
		"transition_ms": transition_ms,
		"presentation_only": true,
		"owns_item_state": false,
		"owns_network_state": false,
		"owns_gameplay_transform": false,
	}
