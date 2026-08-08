class_name WearableBodyTopologyCatalog
extends RefCounted

const MIN_THRESHOLD_M := 0.005
const MAX_THRESHOLD_M := 0.12
const MAX_UPPER_Y_PAD_M := 0.05
const COVERAGE_ROBUST := "ROBUST"
const COVERAGE_HIGH_BOOT := "HIGH_BOOT"
const COVERAGE_MODES := [COVERAGE_ROBUST, COVERAGE_HIGH_BOOT]

var _entries: Dictionary = {}


func register_surface_occlusion(
	presentation_id: String,
	rig_profile_id: String,
	garment_scene: PackedScene,
	threshold_m: float,
	boundary_pad_m: float = 0.006,
	coverage_mode: String = COVERAGE_ROBUST,
	upper_y_pad_m: float = 0.0,
	upper_bias_fraction: float = 1.0
) -> Dictionary:
	if not CharacterEquipmentDomain.is_valid_semantic_id(presentation_id):
		return _result(false, "INVALID_PRESENTATION_ID")
	if not CharacterEquipmentDomain.is_valid_semantic_id(rig_profile_id):
		return _result(false, "INVALID_RIG_PROFILE")
	if garment_scene == null:
		return _result(false, "MISSING_GARMENT_SCENE")
	if not is_finite(threshold_m) or threshold_m < MIN_THRESHOLD_M or threshold_m > MAX_THRESHOLD_M:
		return _result(false, "INVALID_TOPOLOGY_THRESHOLD", {
			"threshold_m": threshold_m,
			"min_threshold_m": MIN_THRESHOLD_M,
			"max_threshold_m": MAX_THRESHOLD_M,
		})
	if not is_finite(boundary_pad_m) or boundary_pad_m < 0.0 or boundary_pad_m > threshold_m:
		return _result(false, "INVALID_TOPOLOGY_BOUNDARY_PAD", {
			"boundary_pad_m": boundary_pad_m,
			"threshold_m": threshold_m,
		})
	if coverage_mode not in COVERAGE_MODES:
		return _result(false, "INVALID_TOPOLOGY_COVERAGE_MODE", {
			"coverage_mode": coverage_mode,
		})
	if not is_finite(upper_y_pad_m) or upper_y_pad_m < 0.0 or upper_y_pad_m > MAX_UPPER_Y_PAD_M:
		return _result(false, "INVALID_TOPOLOGY_UPPER_Y_PAD", {
			"upper_y_pad_m": upper_y_pad_m,
			"max_upper_y_pad_m": MAX_UPPER_Y_PAD_M,
		})
	if not is_finite(upper_bias_fraction) or upper_bias_fraction < 0.0 or upper_bias_fraction > 1.0:
		return _result(false, "INVALID_TOPOLOGY_UPPER_BIAS_FRACTION", {
			"upper_bias_fraction": upper_bias_fraction,
		})
	if coverage_mode == COVERAGE_ROBUST and (upper_y_pad_m > 0.0 or upper_bias_fraction < 1.0):
		return _result(false, "ROBUST_TOPOLOGY_CANNOT_USE_HIGH_BOOT_BIAS")

	_entries[_key(presentation_id, rig_profile_id)] = {
		"presentation_id": presentation_id,
		"rig_profile_id": rig_profile_id,
		"scene": garment_scene,
		"threshold_m": threshold_m,
		"boundary_pad_m": boundary_pad_m,
		"coverage_mode": coverage_mode,
		"upper_y_pad_m": upper_y_pad_m,
		"upper_bias_fraction": upper_bias_fraction,
	}
	return _result(true, CharacterEquipmentDomain.RESULT_OK, {
		"presentation_id": presentation_id,
		"rig_profile_id": rig_profile_id,
		"threshold_m": threshold_m,
		"boundary_pad_m": boundary_pad_m,
		"coverage_mode": coverage_mode,
		"upper_y_pad_m": upper_y_pad_m,
		"upper_bias_fraction": upper_bias_fraction,
	})


func resolve(presentation_id: String, rig_profile_id: String) -> Dictionary:
	var key := _key(presentation_id, rig_profile_id)
	if not _entries.has(key):
		return _result(false, "TOPOLOGY_OCCLUSION_NOT_REGISTERED", {
			"presentation_id": presentation_id,
			"rig_profile_id": rig_profile_id,
		})
	var entry: Dictionary = _entries[key]
	return _result(true, CharacterEquipmentDomain.RESULT_OK, {
		"presentation_id": String(entry.get("presentation_id", "")),
		"rig_profile_id": String(entry.get("rig_profile_id", "")),
		"scene": entry.get("scene"),
		"threshold_m": float(entry.get("threshold_m", 0.0)),
		"boundary_pad_m": float(entry.get("boundary_pad_m", 0.0)),
		"coverage_mode": String(entry.get("coverage_mode", COVERAGE_ROBUST)),
		"upper_y_pad_m": float(entry.get("upper_y_pad_m", 0.0)),
		"upper_bias_fraction": float(entry.get("upper_bias_fraction", 1.0)),
	})


func has(presentation_id: String, rig_profile_id: String) -> bool:
	return _entries.has(_key(presentation_id, rig_profile_id))


func entry_count() -> int:
	return _entries.size()


func _key(presentation_id: String, rig_profile_id: String) -> String:
	return "%s|%s" % [presentation_id, rig_profile_id]


func _result(success: bool, code: String, details: Dictionary = {}) -> Dictionary:
	return {
		"success": success,
		"code": code,
		"details": details,
	}
