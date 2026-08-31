extends RefCounted

const MatterUtilsScript = preload("res://scripts/simulation/matter/matter_contract_utils.gd")

const DEFAULT_SEAM_CLEARANCE_M: float = 0.02

var _configured := false
var _bubble = null
var _seam_clearance_m := DEFAULT_SEAM_CLEARANCE_M


func configure(
	bubble,
	seam_clearance_m: float = DEFAULT_SEAM_CLEARANCE_M
) -> Dictionary:
	if _configured:
		return MatterUtilsScript.failure("P7_LEGACY_MOON_ADAPTER_ALREADY_CONFIGURED")
	if bubble == null \
		or not bubble.has_method("route_for_body_fixed_position") \
		or not bubble.has_method("grid_profile") \
		or not bubble.has_method("half_extent_m"):
		return MatterUtilsScript.failure("P7_LEGACY_MOON_ADAPTER_BUBBLE_REQUIRED")
	if not is_finite(seam_clearance_m) or seam_clearance_m < 0.0 \
		or seam_clearance_m >= float(bubble.half_extent_m()):
		return MatterUtilsScript.failure("P7_LEGACY_MOON_ADAPTER_CLEARANCE_INVALID")
	_bubble = bubble
	_seam_clearance_m = seam_clearance_m
	_configured = true
	return MatterUtilsScript.success(contract_report())


func route_for_body_fixed_position(position_m: Vector3) -> String:
	if not _configured:
		return "LEGACY"
	return _bubble.route_for_body_fixed_position(position_m)


func legacy_collision_enabled_at(position_m: Vector3) -> bool:
	return route_for_body_fixed_position(position_m) != "MATTER"


func legacy_exclusion_bounds() -> Dictionary:
	if not _configured or not _bubble.is_enabled():
		return {}
	var grid: Dictionary = _bubble.grid_profile()
	var center_value: Array = grid.get("root_center_m", [])
	if center_value.size() != 3:
		return {}
	var center := Vector3(
		float(center_value[0]),
		float(center_value[1]),
		float(center_value[2])
	)
	var half_extent_m := float(grid.get("root_half_extent_m", 0.0))
	if not MatterUtilsScript.is_positive_number(half_extent_m):
		return {}
	var minimum_m := center - Vector3.ONE * half_extent_m
	var maximum_m := center + Vector3.ONE * half_extent_m
	return {
		"minimum_m": [minimum_m.x, minimum_m.y, minimum_m.z],
		"maximum_m": [maximum_m.x, maximum_m.y, maximum_m.z],
		"clearance_m": _seam_clearance_m,
		"body_id": String(grid.get("body_id", "")),
		"body_frame_id": String(grid.get("body_frame_id", "")),
		"root_id": String(grid.get("root_id", "")),
	}


func contract_report() -> Dictionary:
	return {
		"configured": _configured,
		"seam_strategy": "BODY_FIXED_AABB_TRIANGLE_CLIP",
		"seam_clearance_m": _seam_clearance_m,
		"inside_geometry_source": "MATTER",
		"inside_collision_source": "MATTER_MESH",
		"outside_geometry_source": "LEGACY_MOON",
		"outside_collision_source": "LEGACY_MOON",
		"double_collision_allowed": false,
		"canonical_state_owned": false,
	}
