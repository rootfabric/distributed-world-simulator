extends RefCounted

const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")

const SCHEMA: String = "planet_simulator.ghost_replica_state.v1"
const PROTOCOL_VERSION: int = 1
const FIELDS: Array[String] = [
	"schema", "protocol_version", "replica_id", "entity_id", "source_owner_node_id",
	"source_authority_epoch", "state_revision", "snapshot_hash", "interest_region_id",
	"replica_tick", "expires_at_tick", "read_only",
]


static func create(
	replica_id: String,
	entity_id: String,
	source_owner_node_id: String,
	source_authority_epoch: int,
	state_revision: int,
	snapshot_hash: String,
	interest_region_id: String,
	replica_tick: int,
	expires_at_tick: int
) -> Dictionary:
	return {
		"schema": SCHEMA, "protocol_version": PROTOCOL_VERSION,
		"replica_id": replica_id, "entity_id": entity_id,
		"source_owner_node_id": source_owner_node_id,
		"source_authority_epoch": source_authority_epoch,
		"state_revision": state_revision, "snapshot_hash": snapshot_hash,
		"interest_region_id": interest_region_id, "replica_tick": replica_tick,
		"expires_at_tick": expires_at_tick, "read_only": true,
	}


static func validate(value: Dictionary) -> Dictionary:
	var check: Dictionary = UtilsScript.validate_exact_fields(value, FIELDS)
	if not bool(check.get("success", false)):
		return check
	for field in ["schema", "replica_id", "entity_id", "source_owner_node_id", "snapshot_hash", "interest_region_id"]:
		check = UtilsScript.require_string(value, field)
		if not bool(check.get("success", false)):
			return check
	if String(value["schema"]) != SCHEMA:
		return UtilsScript.validation_failure("UNSUPPORTED_SCHEMA", "Unexpected ghost replica schema")
	for field in ["protocol_version", "source_authority_epoch", "state_revision", "replica_tick", "expires_at_tick"]:
		check = UtilsScript.require_json_integer(value, field)
		if not bool(check.get("success", false)):
			return check
	check = UtilsScript.require_boolean(value, "read_only")
	if not bool(check.get("success", false)):
		return check
	if int(value["protocol_version"]) != PROTOCOL_VERSION:
		return UtilsScript.validation_failure("UNSUPPORTED_PROTOCOL", "Unsupported protocol version")
	if int(value["source_authority_epoch"]) < 1 or int(value["state_revision"]) < 0 or int(value["replica_tick"]) < 0 or int(value["expires_at_tick"]) <= int(value["replica_tick"]):
		return UtilsScript.validation_failure("INVALID_REPLICA_WINDOW", "Invalid replica counters or expiry")
	if not bool(value["read_only"]):
		return UtilsScript.validation_failure("GHOST_MUST_BE_READ_ONLY", "Ghost replicas cannot be authoritative")
	if not _is_lower_hex_64(String(value["snapshot_hash"])):
		return UtilsScript.validation_failure("INVALID_SNAPSHOT_HASH", "snapshot_hash must be lowercase SHA-256")
	var safe: Dictionary = UtilsScript.canonicalize(value)
	if not bool(safe.get("success", false)):
		return UtilsScript.validation_failure("NON_CANONICAL_PAYLOAD", String(safe.get("error", "")))
	return UtilsScript.validation_success()


static func normalize(value: Dictionary) -> Dictionary:
	if not bool(validate(value).get("success", false)):
		return {}
	var round_trip: Dictionary = UtilsScript.json_round_trip(value)
	return round_trip.get("value", {}) if bool(round_trip.get("success", false)) else {}


static func _is_lower_hex_64(value: String) -> bool:
	if value.length() != 64 or value != value.to_lower():
		return false
	for character in value:
		if not String(character) in ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "a", "b", "c", "d", "e", "f"]:
			return false
	return true
