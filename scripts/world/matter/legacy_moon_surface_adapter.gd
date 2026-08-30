extends RefCounted

const MatterUtilsScript = preload("res://scripts/simulation/matter/matter_contract_utils.gd")

const DEFAULT_MASK_FRACTION: float = 0.60
const DEFAULT_CENTER_TOLERANCE_M: float = 2.0

var _configured := false
var _bubble = null
var _mask_radius_m := 0.0
var _center_tolerance_m := DEFAULT_CENTER_TOLERANCE_M


func configure(
	bubble,
	mask_radius_m: float = 0.0,
	center_tolerance_m: float = DEFAULT_CENTER_TOLERANCE_M
) -> Dictionary:
	if _configured:
		return MatterUtilsScript.failure("P7_LEGACY_MOON_ADAPTER_ALREADY_CONFIGURED")
	if bubble == null 		or not bubble.has_method("contains_body_fixed_position") 		or not bubble.has_method("anchor_direction") 		or not bubble.has_method("surface_radius_m") 		or not bubble.has_method("half_extent_m"):
		return MatterUtilsScript.failure("P7_LEGACY_MOON_ADAPTER_BUBBLE_REQUIRED")
	var selected_mask := mask_radius_m
	if selected_mask <= 0.0:
		selected_mask = float(bubble.half_extent_m()) * DEFAULT_MASK_FRACTION
	if not MatterUtilsScript.is_positive_number(selected_mask) 		or selected_mask >= float(bubble.half_extent_m()) 		or not MatterUtilsScript.is_positive_number(center_tolerance_m):
		return MatterUtilsScript.failure("P7_LEGACY_MOON_ADAPTER_MASK_INVALID")
	_bubble = bubble
	_mask_radius_m = selected_mask
	_center_tolerance_m = center_tolerance_m
	_configured = true
	return MatterUtilsScript.success(contract_report())


func route_for_body_fixed_position(position_m: Vector3) -> String:
	if not _configured:
		return "LEGACY"
	return _bubble.route_for_body_fixed_position(position_m)


func legacy_collision_enabled_at(position_m: Vector3) -> bool:
	return route_for_body_fixed_position(position_m) != "MATTER"


func legacy_local_inner_radius_m(center_direction: Vector3) -> float:
	if not _configured or not _bubble.is_enabled() 		or center_direction.length_squared() <= 0.000000000001:
		return 0.0
	var normalized := center_direction.normalized()
	var anchor: Vector3 = _bubble.anchor_direction()
	var surface_radius: float = float(_bubble.surface_radius_m())
	var center_distance_m := (normalized - anchor).length() * surface_radius
	if center_distance_m > _center_tolerance_m:
		return 0.0
	return _mask_radius_m


func bubble_mask_radius_m() -> float:
	return _mask_radius_m if _configured else 0.0


func contract_report() -> Dictionary:
	return {
		"configured": _configured,
		"mask_radius_m": _mask_radius_m,
		"center_tolerance_m": _center_tolerance_m,
		"inside_geometry_source": "MATTER",
		"inside_collision_source": "MATTER_MESH",
		"outside_geometry_source": "LEGACY_MOON",
		"outside_collision_source": "LEGACY_MOON",
		"double_collision_allowed": false,
		"canonical_state_owned": false,
	}
