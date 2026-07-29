extends RefCounted

const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")

const SCHEMA: String = "planet_simulator.aggregate_authority_state.v1"
const FIELDS: Array[String] = [
	"schema",
	"authority_owner_id",
	"authority_epoch",
	"state_revision",
	"server_tick",
]


static func create(owner_id: String, epoch: int, revision: int, tick: int) -> Dictionary:
	return {
		"schema": SCHEMA,
		"authority_owner_id": owner_id,
		"authority_epoch": epoch,
		"state_revision": revision,
		"server_tick": tick,
	}


static func validate(value: Dictionary) -> Dictionary:
	var exact: Dictionary = UtilsScript.validate_exact_fields(value, FIELDS)
	if not bool(exact.get("success", false)):
		return exact
	if typeof(value.get("schema")) != TYPE_STRING or String(value["schema"]) != SCHEMA:
		return _failure("UNSUPPORTED_AGGREGATE_AUTHORITY_SCHEMA")
	var owner_check: Dictionary = UtilsScript.require_string(value, "authority_owner_id")
	if not bool(owner_check.get("success", false)):
		return owner_check
	for field in ["authority_epoch", "state_revision", "server_tick"]:
		var check: Dictionary = UtilsScript.require_json_integer(value, field)
		if not bool(check.get("success", false)):
			return check
	if int(value["authority_epoch"]) < 1:
		return _failure("INVALID_AUTHORITY_EPOCH")
	if int(value["state_revision"]) < 0:
		return _failure("INVALID_STATE_REVISION")
	if int(value["server_tick"]) < 0:
		return _failure("INVALID_SERVER_TICK")
	return UtilsScript.validation_success()


static func _failure(code: String) -> Dictionary:
	return UtilsScript.validation_failure(code, code)
