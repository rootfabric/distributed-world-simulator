extends RefCounted

const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")

const SCHEMA: String = "planet_simulator.handoff_result.v1"
const PROTOCOL_VERSION: int = 1
const STATUSES: Array[String] = ["COMMITTED", "ABORTED", "EXPIRED", "REJECTED"]
const FIELDS: Array[String] = [
	"schema", "protocol_version", "ticket_id", "entity_id", "status", "error_code",
	"source_node_id", "target_node_id", "authority_owner_id", "authority_epoch",
	"state_revision", "completed_at_tick", "payload",
]


static func create(
	ticket_id: String,
	entity_id: String,
	status: String,
	error_code: String,
	source_node_id: String,
	target_node_id: String,
	authority_owner_id: String,
	authority_epoch: int,
	state_revision: int,
	completed_at_tick: int,
	payload: Dictionary = {}
) -> Dictionary:
	return {
		"schema": SCHEMA, "protocol_version": PROTOCOL_VERSION,
		"ticket_id": ticket_id, "entity_id": entity_id, "status": status,
		"error_code": error_code, "source_node_id": source_node_id,
		"target_node_id": target_node_id, "authority_owner_id": authority_owner_id,
		"authority_epoch": authority_epoch, "state_revision": state_revision,
		"completed_at_tick": completed_at_tick, "payload": payload.duplicate(true),
	}


static func validate(value: Dictionary) -> Dictionary:
	var check: Dictionary = UtilsScript.validate_exact_fields(value, FIELDS)
	if not bool(check.get("success", false)):
		return check
	for field in ["schema", "ticket_id", "entity_id", "status", "source_node_id", "target_node_id", "authority_owner_id"]:
		check = UtilsScript.require_string(value, field)
		if not bool(check.get("success", false)):
			return check
	check = UtilsScript.require_string(value, "error_code", true)
	if not bool(check.get("success", false)):
		return check
	if String(value["schema"]) != SCHEMA:
		return UtilsScript.validation_failure("UNSUPPORTED_SCHEMA", "Unexpected handoff result schema")
	for field in ["protocol_version", "authority_epoch", "state_revision", "completed_at_tick"]:
		check = UtilsScript.require_json_integer(value, field)
		if not bool(check.get("success", false)):
			return check
	if int(value["protocol_version"]) != PROTOCOL_VERSION:
		return UtilsScript.validation_failure("UNSUPPORTED_PROTOCOL", "Unsupported protocol version")
	if not STATUSES.has(String(value["status"])):
		return UtilsScript.validation_failure("INVALID_STATUS", "Unknown handoff result status")
	if int(value["authority_epoch"]) < 1 or int(value["state_revision"]) < 0 or int(value["completed_at_tick"]) < 0:
		return UtilsScript.validation_failure("INVALID_COUNTER", "Invalid handoff result counters")
	if String(value["status"]) == "COMMITTED":
		if String(value["authority_owner_id"]) != String(value["target_node_id"]) or not String(value["error_code"]).is_empty():
			return UtilsScript.validation_failure("INVALID_COMMIT_RESULT", "Committed result must name target owner and no error")
	elif String(value["error_code"]).is_empty():
		return UtilsScript.validation_failure("EMPTY_FIELD", "Non-committed result requires error_code")
	check = UtilsScript.require_dictionary(value, "payload")
	if not bool(check.get("success", false)):
		return check
	var safe: Dictionary = UtilsScript.canonicalize(value)
	if not bool(safe.get("success", false)):
		return UtilsScript.validation_failure("NON_CANONICAL_PAYLOAD", String(safe.get("error", "")))
	return UtilsScript.validation_success()


static func normalize(value: Dictionary) -> Dictionary:
	if not bool(validate(value).get("success", false)):
		return {}
	var round_trip: Dictionary = UtilsScript.json_round_trip(value)
	return round_trip.get("value", {}) if bool(round_trip.get("success", false)) else {}
