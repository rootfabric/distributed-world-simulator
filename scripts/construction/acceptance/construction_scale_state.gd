extends RefCounted

const Utils = preload("res://scripts/network/contracts/network_contract_utils.gd")
const Profile = preload("res://scripts/construction/acceptance/construction_scale_profile.gd")
const Metrics = preload("res://scripts/construction/acceptance/construction_scale_metrics.gd")

const SCHEMA := "construction.large_scale_state.v1"
const FIELDS: Array[String] = [
	"schema", "profile", "tick", "generation", "constructs", "plans", "agents", "fabrication_jobs",
	"orders", "shipments", "warehouses", "terminal_operations", "metrics", "material_ledger",
	"last_reconnect_operations", "checksum",
]

static func create(profile: Dictionary) -> Dictionary:
	var state := {
		"schema": SCHEMA,
		"profile": profile.duplicate(true),
		"tick": 0,
		"generation": 0,
		"constructs": {},
		"plans": {},
		"agents": {},
		"fabrication_jobs": {},
		"orders": {},
		"shipments": {},
		"warehouses": {},
		"terminal_operations": {},
		"metrics": Metrics.create(),
		"material_ledger": {"initial": 0, "produced": 0, "procured": 0, "consumed": 0, "in_transit": 0, "warehouse": 0, "salvaged": 0},
		"last_reconnect_operations": [],
		"checksum": "",
	}
	state.checksum = compute_checksum(state)
	return state

static func seal(value: Dictionary) -> Dictionary:
	var result := value.duplicate(true)
	result.metrics = Metrics.seal(Dictionary(result.metrics))
	result.checksum = compute_checksum(result)
	return result

static func validate(value: Dictionary) -> Dictionary:
	var exact := Utils.validate_exact_fields(value, FIELDS)
	if not bool(exact.get("success", false)):
		return exact
	if value.get("schema") != SCHEMA:
		return _failure("CONSTRUCTION_SCALE_STATE_SCHEMA_INVALID")
	var pv := Profile.validate(Dictionary(value.get("profile", {})))
	if not bool(pv.get("success", false)):
		return _failure("CONSTRUCTION_SCALE_STATE_PROFILE_INVALID", {"cause": pv})
	var mv := Metrics.validate(Dictionary(value.get("metrics", {})))
	if not bool(mv.get("success", false)):
		return _failure("CONSTRUCTION_SCALE_STATE_METRICS_INVALID", {"cause": mv})
	for field in ["tick", "generation"]:
		if not Utils.is_json_integer(value.get(field)) or int(value[field]) < 0:
			return _failure("CONSTRUCTION_SCALE_STATE_COUNTER_INVALID", {"field": field})
	for field in ["constructs", "plans", "agents", "fabrication_jobs", "orders", "shipments", "warehouses", "terminal_operations", "material_ledger"]:
		if typeof(value.get(field)) != TYPE_DICTIONARY:
			return _failure("CONSTRUCTION_SCALE_STATE_MAP_INVALID", {"field": field})
	if typeof(value.get("last_reconnect_operations")) != TYPE_ARRAY:
		return _failure("CONSTRUCTION_SCALE_STATE_RECONNECT_INVALID")
	if String(value.get("checksum", "")) != compute_checksum(value):
		return _failure("CONSTRUCTION_SCALE_STATE_CHECKSUM_MISMATCH")
	return _success()

static func compute_checksum(value: Dictionary) -> String:
	var payload := value.duplicate(true)
	payload["checksum"] = ""
	return Utils.payload_hash(payload)

static func _success() -> Dictionary:
	return {"success": true, "error_code": "", "message": ""}

static func _failure(code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": code, "message": code, "details": details.duplicate(true)}
