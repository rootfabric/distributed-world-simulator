extends RefCounted

const SCHEMA := "distributed_world_simulator.ecology.plant_renderer_profile.v1"
const VERSION := "1.0.0"
const PROFILE_ORDER: Array[String] = [
	"DEBUG_SKELETON",
	"BRANCH_TUBES",
	"BRANCH_LEAF_INSTANCED",
	"CANOPY_APPROXIMATION",
	"FULL_PROCEDURAL",
	"IMPOSTOR_BILLBOARD",
]

static func create(profile_id: String) -> Dictionary:
	if not profile_id in PROFILE_ORDER:
		return {}
	var profile := {
		"schema": SCHEMA,
		"version": VERSION,
		"profile_id": profile_id,
		"lod_class": 0,
		"branch_mode": "NONE",
		"branch_sides": 0,
		"branch_fraction": 0.0,
		"foliage_mode": "NONE",
		"foliage_fraction": 0.0,
		"canopy_mode": "NONE",
		"impostor_resolution": 0,
	}
	match profile_id:
		"DEBUG_SKELETON":
			profile["lod_class"] = 0
			profile["branch_mode"] = "LINES"
			profile["branch_fraction"] = 1.0
		"BRANCH_TUBES":
			profile["lod_class"] = 1
			profile["branch_mode"] = "TAPERED_TUBES"
			profile["branch_sides"] = 6
			profile["branch_fraction"] = 1.0
		"BRANCH_LEAF_INSTANCED":
			profile["lod_class"] = 2
			profile["branch_mode"] = "TAPERED_TUBES"
			profile["branch_sides"] = 6
			profile["branch_fraction"] = 1.0
			profile["foliage_mode"] = "INSTANCED_LEAVES"
			profile["foliage_fraction"] = 0.70
		"CANOPY_APPROXIMATION":
			profile["lod_class"] = 3
			profile["branch_mode"] = "TRUNK_ONLY"
			profile["branch_sides"] = 5
			profile["branch_fraction"] = 0.25
			profile["canopy_mode"] = "ELLIPSOID_CLUSTER"
		"FULL_PROCEDURAL":
			profile["lod_class"] = 4
			profile["branch_mode"] = "TAPERED_TUBES"
			profile["branch_sides"] = 10
			profile["branch_fraction"] = 1.0
			profile["foliage_mode"] = "INSTANCED_LEAVES_BUDS"
			profile["foliage_fraction"] = 1.0
			profile["canopy_mode"] = "DIAGNOSTIC_BOUNDS"
		"IMPOSTOR_BILLBOARD":
			profile["lod_class"] = 5
			profile["impostor_resolution"] = 256
	profile["profile_hash"] = compute_hash(profile)
	return profile

static func validate(profile: Dictionary) -> Dictionary:
	if String(profile.get("schema", "")) != SCHEMA or String(profile.get("version", "")) != VERSION:
		return _failure("ECO_PH5_RENDERER_PROFILE_SCHEMA_VERSION_MISMATCH")
	if not String(profile.get("profile_id", "")) in PROFILE_ORDER:
		return _failure("ECO_PH5_RENDERER_PROFILE_UNKNOWN")
	if int(profile.get("lod_class", -1)) < 0 or int(profile.get("lod_class", -1)) > 5:
		return _failure("ECO_PH5_RENDERER_PROFILE_INVALID_LOD_CLASS")
	if int(profile.get("branch_sides", -1)) < 0:
		return _failure("ECO_PH5_RENDERER_PROFILE_INVALID_BRANCH_SIDES")
	for field_name in ["branch_fraction", "foliage_fraction"]:
		if typeof(profile.get(field_name)) not in [TYPE_INT, TYPE_FLOAT]:
			return _failure("ECO_PH5_RENDERER_PROFILE_INVALID_FRACTION", {"field": field_name})
		var value := float(profile.get(field_name))
		if not is_finite(value) or value < 0.0 or value > 1.0:
			return _failure("ECO_PH5_RENDERER_PROFILE_INVALID_FRACTION", {"field": field_name})
	if int(profile.get("impostor_resolution", -1)) < 0:
		return _failure("ECO_PH5_RENDERER_PROFILE_INVALID_IMPOSTOR_RESOLUTION")
	var profile_hash := String(profile.get("profile_hash", ""))
	if profile_hash.length() != 64 or profile_hash != compute_hash(profile):
		return _failure("ECO_PH5_RENDERER_PROFILE_HASH_MISMATCH")
	return _success()

static func compute_hash(profile: Dictionary) -> String:
	return "|".join(PackedStringArray([
		SCHEMA,
		VERSION,
		String(profile.get("profile_id", "")),
		str(int(profile.get("lod_class", -1))),
		String(profile.get("branch_mode", "")),
		str(int(profile.get("branch_sides", 0))),
		"%.9f" % float(profile.get("branch_fraction", 0.0)),
		String(profile.get("foliage_mode", "")),
		"%.9f" % float(profile.get("foliage_fraction", 0.0)),
		String(profile.get("canopy_mode", "")),
		str(int(profile.get("impostor_resolution", 0))),
	])).sha256_text()

static func create_all() -> Dictionary:
	var result := {}
	for profile_id in PROFILE_ORDER:
		result[profile_id] = create(profile_id)
	return result

static func _success(details: Dictionary = {}) -> Dictionary:
	return {"success": true, "error_code": "", "details": details.duplicate(true)}

static func _failure(code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": code, "details": details.duplicate(true)}
