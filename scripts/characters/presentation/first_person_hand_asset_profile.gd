class_name FirstPersonHandAssetProfile
extends RefCounted

const PROFILE_SCHEMA := "planet_simulator.fpe_hand_asset_profile.v1"
const PROVIDER_SKINNED_NAMED_BIND := "SKINNED_NAMED_BIND"
const PROVIDER_BONE_ATTACHMENT := "BONE_ATTACHMENT"
const PROVIDER_PROCEDURAL := "PROCEDURAL"
const PROVIDER_INSPECT_ONLY := "INSPECT_ONLY"
const REST_CANONICAL_COMPATIBLE := "CANONICAL_COMPATIBLE_BIND_SPACE"
const REST_INSPECT_REQUIRED := "INSPECT_REQUIRED"
const REST_AUTO_CANONICAL_REBIND := "AUTO_CANONICAL_REBIND"

const ALLOWED_PROVIDERS: Array[String] = [
	PROVIDER_SKINNED_NAMED_BIND,
	PROVIDER_BONE_ATTACHMENT,
	PROVIDER_PROCEDURAL,
	PROVIDER_INSPECT_ONLY,
]
const ALLOWED_LAYOUTS: Array[String] = [
	"PER_HAND_SINGLE_SCENE",
	"PAIRED_SEPARATE_MESHES",
	"PAIRED_SINGLE_MESH",
	"BOTH_COMPATIBLE",
	"AUTO_INSPECT",
]
const ALLOWED_REST_POLICIES: Array[String] = [
	REST_CANONICAL_COMPATIBLE,
	REST_INSPECT_REQUIRED,
	REST_AUTO_CANONICAL_REBIND,
]


static func load_from_path(profile_path: String) -> Dictionary:
	var path := profile_path.strip_edges()
	if path.is_empty() or not path.begins_with("res://"):
		return _failure("FPE_HAND_PROFILE_PATH_INVALID", {"profile_path": profile_path})
	if not FileAccess.file_exists(path):
		return _failure("FPE_HAND_PROFILE_NOT_FOUND", {"profile_path": path})
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _failure("FPE_HAND_PROFILE_OPEN_FAILED", {"profile_path": path})
	var raw := file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(raw)
	if not parsed is Dictionary:
		return _failure("FPE_HAND_PROFILE_JSON_INVALID", {"profile_path": path})
	var profile := Dictionary(parsed).duplicate(true)
	var validation := validate(profile)
	if not bool(validation.get("success", false)):
		var details := Dictionary(validation.get("details", {})).duplicate(true)
		details["profile_path"] = path
		return _failure(String(validation.get("error_code", "FPE_HAND_PROFILE_INVALID")), details)
	return _success({
		"profile_path": path,
		"profile": profile,
		"report": create_report(profile, path),
	})


static func validate(profile: Dictionary) -> Dictionary:
	if String(profile.get("schema", "")) != PROFILE_SCHEMA:
		return _failure("FPE_HAND_PROFILE_SCHEMA_MISMATCH", {
			"actual": String(profile.get("schema", "")),
			"required": PROFILE_SCHEMA,
		})
	var profile_id := String(profile.get("profile_id", "")).strip_edges()
	if profile_id.is_empty():
		return _failure("FPE_HAND_PROFILE_ID_REQUIRED")
	var provider := String(profile.get("provider", "")).strip_edges().to_upper()
	if provider not in ALLOWED_PROVIDERS:
		return _failure("FPE_HAND_PROFILE_PROVIDER_UNSUPPORTED", {"provider": provider})
	var layout := String(profile.get("hand_layout", "")).strip_edges().to_upper()
	if layout not in ALLOWED_LAYOUTS:
		return _failure("FPE_HAND_PROFILE_LAYOUT_UNSUPPORTED", {"hand_layout": layout})
	var license_value: Variant = profile.get("license", {})
	if not license_value is Dictionary:
		return _failure("FPE_HAND_PROFILE_LICENSE_REQUIRED")
	var license_data := Dictionary(license_value)
	if String(license_data.get("spdx", "")).strip_edges().is_empty():
		return _failure("FPE_HAND_PROFILE_LICENSE_SPDX_REQUIRED")
	var asset_value: Variant = profile.get("asset", {})
	if not asset_value is Dictionary:
		return _failure("FPE_HAND_PROFILE_ASSET_REQUIRED")
	var asset := Dictionary(asset_value)
	var scene_path := String(asset.get("scene_path", "")).strip_edges()
	if provider not in [PROVIDER_PROCEDURAL, PROVIDER_INSPECT_ONLY] and not scene_path.begins_with("res://"):
		return _failure("FPE_HAND_PROFILE_SCENE_PATH_REQUIRED", {"scene_path": scene_path})
	var retarget_value: Variant = profile.get("retarget", {})
	if provider == PROVIDER_SKINNED_NAMED_BIND:
		if not retarget_value is Dictionary:
			return _failure("FPE_HAND_PROFILE_RETARGET_REQUIRED")
		var retarget := Dictionary(retarget_value)
		var policy := String(retarget.get("rest_space_policy", "")).strip_edges().to_upper()
		if policy not in ALLOWED_REST_POLICIES:
			return _failure("FPE_HAND_PROFILE_REST_POLICY_UNSUPPORTED", {"rest_space_policy": policy})
		var bone_map_value: Variant = retarget.get("bone_map", {})
		if not bone_map_value is Dictionary:
			return _failure("FPE_HAND_PROFILE_BONE_MAP_INVALID")
		var by_hand_value: Variant = retarget.get("bone_map_by_hand", {})
		if not by_hand_value is Dictionary:
			return _failure("FPE_HAND_PROFILE_BONE_MAP_BY_HAND_INVALID")
	return _success({"profile_id": profile_id, "provider": provider, "hand_layout": layout})


static func create_report(profile: Dictionary, profile_path: String = "") -> Dictionary:
	var asset := Dictionary(profile.get("asset", {}))
	var license_data := Dictionary(profile.get("license", {}))
	var retarget := Dictionary(profile.get("retarget", {}))
	var common_map := Dictionary(retarget.get("bone_map", {}))
	var by_hand := Dictionary(retarget.get("bone_map_by_hand", {}))
	var per_hand_counts := {
		"left": Dictionary(by_hand.get("left", {})).size(),
		"right": Dictionary(by_hand.get("right", {})).size(),
	}
	return {
		"schema": "planet_simulator.fpe_hand_asset_profile_report.v1",
		"profile_id": String(profile.get("profile_id", "")),
		"display_name": String(profile.get("display_name", "")),
		"profile_path": profile_path,
		"status": String(profile.get("status", "")),
		"provider": String(profile.get("provider", "")),
		"hand_layout": String(profile.get("hand_layout", "")),
		"scene_path": String(asset.get("scene_path", "")),
		"source_url": String(license_data.get("source_url", "")),
		"license_spdx": String(license_data.get("spdx", "")),
		"rest_space_policy": String(retarget.get("rest_space_policy", "")),
		"bone_map_count": common_map.size(),
		"bone_map_by_hand_count": per_hand_counts,
		"bone_map_total_count": common_map.size() + int(per_hand_counts.left) + int(per_hand_counts.right),
		"portable": true,
		"presentation_only": true,
		"owns_item_state": false,
		"owns_network_state": false,
		"owns_gameplay_transform": false,
	}


static func _success(details: Dictionary = {}) -> Dictionary:
	return {"success": true, "error_code": "", "details": details.duplicate(true)}


static func _failure(error_code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": error_code, "details": details.duplicate(true)}
