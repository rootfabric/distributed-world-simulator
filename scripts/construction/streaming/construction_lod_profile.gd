extends RefCounted

const Utils = preload("res://scripts/network/contracts/network_contract_utils.gd")
const Level = preload("res://scripts/construction/streaming/construction_activity_level.gd")
const SCHEMA := "planet_simulator.construction_lod_profile.v1"
const FULL := "FULL"
const SIMPLIFIED := "SIMPLIFIED"
const IMPOSTOR := "IMPOSTOR"
const NONE := "NONE"
const TIERS: Array[String] = [FULL, SIMPLIFIED, IMPOSTOR, NONE]
const FIELDS: Array[String] = ["schema", "construct_id", "activity_level", "lod_tier", "mesh_detail_ratio", "collision_enabled", "animation_enabled", "checksum"]

static func compile(construct_id: String, activity_level: String, interest_score: int) -> Dictionary:
	if not construct_id.begins_with("construct/") or not Level.is_valid(activity_level) or interest_score < 0: return _failure("INVALID_CONSTRUCTION_LOD_INPUT")
	var tier := NONE; var ratio := 0.0; var collision := false; var animation := false
	if activity_level == Level.PRESENTED:
		tier = FULL if interest_score >= 10000000 else SIMPLIFIED
		ratio = 1.0 if tier == FULL else 0.35
		collision = true; animation = tier == FULL
	elif activity_level == Level.SUMMARY:
		tier = IMPOSTOR; ratio = 0.05
	var value := {"schema": SCHEMA, "construct_id": construct_id, "activity_level": activity_level, "lod_tier": tier, "mesh_detail_ratio": ratio, "collision_enabled": collision, "animation_enabled": animation, "checksum": ""}
	value["checksum"] = compute_checksum(value); return {"success": true, "error_code": "", "message": "", "profile": value}

static func validate(value: Dictionary) -> Dictionary:
	var exact := Utils.validate_exact_fields(value, FIELDS); if not bool(exact.get("success", false)): return exact
	if value.get("schema") != SCHEMA or not String(value.get("construct_id", "")).begins_with("construct/"): return _failure("INVALID_CONSTRUCTION_LOD_IDENTITY")
	if not Level.is_valid(value.get("activity_level")) or not TIERS.has(String(value.get("lod_tier", ""))): return _failure("INVALID_CONSTRUCTION_LOD_LEVEL")
	if typeof(value.get("mesh_detail_ratio")) not in [TYPE_INT, TYPE_FLOAT] or float(value["mesh_detail_ratio"]) < 0.0 or float(value["mesh_detail_ratio"]) > 1.0: return _failure("INVALID_CONSTRUCTION_LOD_DETAIL_RATIO")
	if typeof(value.get("collision_enabled")) != TYPE_BOOL or typeof(value.get("animation_enabled")) != TYPE_BOOL: return _failure("INVALID_CONSTRUCTION_LOD_FLAGS")
	var expected := compile(String(value["construct_id"]), String(value["activity_level"]), 10000000 if String(value["lod_tier"]) == FULL else 0)
	if not bool(expected.get("success", false)): return expected
	var canonical: Dictionary = expected["profile"]
	if String(value["lod_tier"]) != String(canonical["lod_tier"]) or float(value["mesh_detail_ratio"]) != float(canonical["mesh_detail_ratio"]) or bool(value["collision_enabled"]) != bool(canonical["collision_enabled"]) or bool(value["animation_enabled"]) != bool(canonical["animation_enabled"]): return _failure("NON_CANONICAL_CONSTRUCTION_LOD_PROFILE")
	if String(value.get("checksum", "")) != compute_checksum(value): return _failure("CONSTRUCTION_LOD_PROFILE_CHECKSUM_MISMATCH")
	return _success()

static func compute_checksum(value: Dictionary) -> String: var payload := value.duplicate(true); payload["checksum"] = ""; return Utils.payload_hash(payload)
static func _success() -> Dictionary: return {"success": true, "error_code": "", "message": ""}
static func _failure(code: String) -> Dictionary: return {"success": false, "error_code": code, "message": code}
