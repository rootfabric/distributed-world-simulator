extends RefCounted

const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")

const SCHEMA: String = "planet_simulator.handoff_ticket.v1"
const PROTOCOL_VERSION: int = 1
const STATES: Array[String] = [
	"REQUESTED", "PREPARING", "FROZEN", "SNAPSHOT_READY",
	"TARGET_PREPARED", "COMMITTED", "ABORTED", "EXPIRED",
]
const TERMINAL_STATES: Array[String] = ["COMMITTED", "ABORTED", "EXPIRED"]
const SNAPSHOT_REQUIRED_STATES: Array[String] = ["SNAPSHOT_READY", "TARGET_PREPARED", "COMMITTED"]
const FIELDS: Array[String] = [
	"schema", "protocol_version", "ticket_id", "entity_id", "source_node_id",
	"target_node_id", "source_authority_epoch", "target_authority_epoch",
	"expected_state_revision", "region_id", "state", "created_at_tick",
	"expires_at_tick", "snapshot_id", "snapshot_hash", "reason", "transition_revision",
]


static func create(
	ticket_id: String,
	entity_id: String,
	source_node_id: String,
	target_node_id: String,
	source_authority_epoch: int,
	target_authority_epoch: int,
	expected_state_revision: int,
	region_id: String,
	created_at_tick: int,
	expires_at_tick: int
) -> Dictionary:
	return {
		"schema": SCHEMA, "protocol_version": PROTOCOL_VERSION,
		"ticket_id": ticket_id, "entity_id": entity_id,
		"source_node_id": source_node_id, "target_node_id": target_node_id,
		"source_authority_epoch": source_authority_epoch,
		"target_authority_epoch": target_authority_epoch,
		"expected_state_revision": expected_state_revision, "region_id": region_id,
		"state": "REQUESTED", "created_at_tick": created_at_tick,
		"expires_at_tick": expires_at_tick, "snapshot_id": "", "snapshot_hash": "",
		"reason": "", "transition_revision": 0,
	}


static func validate(value: Dictionary) -> Dictionary:
	var check: Dictionary = UtilsScript.validate_exact_fields(value, FIELDS)
	if not bool(check.get("success", false)):
		return check
	for field in ["schema", "ticket_id", "entity_id", "source_node_id", "target_node_id", "region_id", "state"]:
		check = UtilsScript.require_string(value, field)
		if not bool(check.get("success", false)):
			return check
	for field in ["snapshot_id", "snapshot_hash", "reason"]:
		check = UtilsScript.require_string(value, field, true)
		if not bool(check.get("success", false)):
			return check
	if String(value["schema"]) != SCHEMA:
		return UtilsScript.validation_failure("UNSUPPORTED_SCHEMA", "Unexpected handoff ticket schema")
	for field in ["protocol_version", "source_authority_epoch", "target_authority_epoch", "expected_state_revision", "created_at_tick", "expires_at_tick", "transition_revision"]:
		check = UtilsScript.require_json_integer(value, field)
		if not bool(check.get("success", false)):
			return check
	if int(value["protocol_version"]) != PROTOCOL_VERSION:
		return UtilsScript.validation_failure("UNSUPPORTED_PROTOCOL", "Unsupported protocol version")
	if String(value["source_node_id"]) == String(value["target_node_id"]):
		return UtilsScript.validation_failure("SAME_AUTHORITY_NODE", "Source and target nodes must differ")
	if int(value["source_authority_epoch"]) < 1 or int(value["target_authority_epoch"]) <= int(value["source_authority_epoch"]):
		return UtilsScript.validation_failure("INVALID_AUTHORITY_EPOCH", "Target epoch must exceed source epoch")
	if int(value["expected_state_revision"]) < 0 or int(value["created_at_tick"]) < 0 or int(value["expires_at_tick"]) <= int(value["created_at_tick"]) or int(value["transition_revision"]) < 0:
		return UtilsScript.validation_failure("INVALID_HANDOFF_TIMELINE", "Invalid handoff revisions or time window")
	if not STATES.has(String(value["state"])):
		return UtilsScript.validation_failure("INVALID_HANDOFF_STATE", "Unknown handoff state")
	var state: String = String(value["state"])
	if state == "REQUESTED" and int(value["transition_revision"]) != 0:
		return UtilsScript.validation_failure("INVALID_TRANSITION_REVISION", "REQUESTED ticket must start at transition_revision 0")
	if state != "REQUESTED" and int(value["transition_revision"]) < 1:
		return UtilsScript.validation_failure("INVALID_TRANSITION_REVISION", "Advanced handoff state requires positive transition_revision")
	if state in ["ABORTED", "EXPIRED"] and String(value["reason"]).strip_edges().is_empty():
		return UtilsScript.validation_failure("HANDOFF_REASON_REQUIRED", "Terminal failure state requires reason")
	if state == "COMMITTED" and not String(value["reason"]).is_empty():
		return UtilsScript.validation_failure("INVALID_HANDOFF_REASON", "Committed ticket cannot contain failure reason")
	var snapshot_id: String = String(value["snapshot_id"])
	var snapshot_hash: String = String(value["snapshot_hash"])
	if snapshot_id.is_empty() != snapshot_hash.is_empty():
		return UtilsScript.validation_failure("INCOMPLETE_SNAPSHOT_REFERENCE", "snapshot_id and snapshot_hash must appear together")
	var snapshot_required: bool = SNAPSHOT_REQUIRED_STATES.has(state)
	if snapshot_required and (snapshot_id.is_empty() or not _is_lower_hex_64(snapshot_hash)):
		return UtilsScript.validation_failure("SNAPSHOT_REQUIRED", "Handoff state requires snapshot_id and snapshot_hash")
	if not snapshot_hash.is_empty() and not _is_lower_hex_64(snapshot_hash):
		return UtilsScript.validation_failure("INVALID_SNAPSHOT_HASH", "snapshot_hash must be empty or lowercase SHA-256")
	var safe: Dictionary = UtilsScript.canonicalize(value)
	if not bool(safe.get("success", false)):
		return UtilsScript.validation_failure("NON_CANONICAL_PAYLOAD", String(safe.get("error", "")))
	return UtilsScript.validation_success()


static func normalize(value: Dictionary) -> Dictionary:
	if not bool(validate(value).get("success", false)):
		return {}
	var round_trip: Dictionary = UtilsScript.json_round_trip(value)
	return round_trip.get("value", {}) if bool(round_trip.get("success", false)) else {}


static func ticket_hash(value: Dictionary) -> String:
	return UtilsScript.payload_hash(normalize(value))


static func is_terminal(value: Dictionary) -> bool:
	return bool(validate(value).get("success", false)) and TERMINAL_STATES.has(String(value["state"]))


static func _is_lower_hex_64(value: String) -> bool:
	if value.length() != 64 or value != value.to_lower():
		return false
	for character in value:
		if not String(character) in ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "a", "b", "c", "d", "e", "f"]:
			return false
	return true
