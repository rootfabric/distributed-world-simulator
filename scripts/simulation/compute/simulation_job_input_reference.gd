extends RefCounted

const NetworkUtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const ComputeUtilsScript = preload("res://scripts/simulation/compute/compute_contract_utils.gd")

const SCHEMA := "planet_simulator.simulation_job_input_reference.v1"
const FIELDS: Array[String] = [
	"schema", "aggregate_id", "aggregate_kind", "state_schema", "authority_owner_id",
	"authority_epoch", "state_revision", "server_tick", "snapshot_checksum",
	"projected_state", "projected_state_hash",
]


static func create(snapshot: Dictionary, projected_state: Dictionary) -> Dictionary:
	var descriptor: Dictionary = snapshot.get("descriptor", {})
	var identity: Dictionary = descriptor.get("identity", {})
	var authority: Dictionary = descriptor.get("authority", {})
	var value := {
		"schema": SCHEMA,
		"aggregate_id": String(identity.get("aggregate_id", "")),
		"aggregate_kind": String(identity.get("aggregate_kind", "")),
		"state_schema": String(identity.get("state_schema", "")),
		"authority_owner_id": String(authority.get("authority_owner_id", "")),
		"authority_epoch": int(authority.get("authority_epoch", 0)),
		"state_revision": int(authority.get("state_revision", -1)),
		"server_tick": int(authority.get("server_tick", -1)),
		"snapshot_checksum": String(snapshot.get("checksum", "")),
		"projected_state": projected_state.duplicate(true),
		"projected_state_hash": NetworkUtilsScript.payload_hash(projected_state),
	}
	return value


static func validate(value: Dictionary) -> Dictionary:
	var exact := NetworkUtilsScript.validate_exact_fields(value, FIELDS)
	if not bool(exact.get("success", false)):
		return exact
	if value.get("schema") != SCHEMA:
		return ComputeUtilsScript.failure("UNSUPPORTED_SIMULATION_JOB_INPUT_SCHEMA")
	if not ComputeUtilsScript.is_identifier(String(value.get("aggregate_id", "")), "aggregate/") or not ComputeUtilsScript.is_upper_kind(String(value.get("aggregate_kind", ""))) or not ComputeUtilsScript.is_versioned_schema(String(value.get("state_schema", ""))):
		return ComputeUtilsScript.failure("INVALID_SIMULATION_JOB_INPUT_IDENTITY")
	if not ComputeUtilsScript.is_identifier(String(value.get("authority_owner_id", ""))):
		return ComputeUtilsScript.failure("INVALID_SIMULATION_JOB_INPUT_AUTHORITY")
	for field in ["authority_epoch", "state_revision", "server_tick"]:
		if not NetworkUtilsScript.is_json_integer(value.get(field)):
			return ComputeUtilsScript.failure("INVALID_SIMULATION_JOB_INPUT_COUNTER", {"field": field})
	if int(value["authority_epoch"]) < 1 or int(value["state_revision"]) < 0 or int(value["server_tick"]) < 0:
		return ComputeUtilsScript.failure("INVALID_SIMULATION_JOB_INPUT_COUNTER")
	if not ComputeUtilsScript.is_lower_hex_64(String(value.get("snapshot_checksum", ""))) or not ComputeUtilsScript.is_lower_hex_64(String(value.get("projected_state_hash", ""))):
		return ComputeUtilsScript.failure("INVALID_SIMULATION_JOB_INPUT_HASH")
	if typeof(value.get("projected_state")) != TYPE_DICTIONARY:
		return ComputeUtilsScript.failure("INVALID_SIMULATION_JOB_PROJECTED_STATE")
	var canonical := ComputeUtilsScript.canonical_copy(value["projected_state"])
	if not bool(canonical.get("success", false)):
		return canonical
	if String(value["projected_state_hash"]) != NetworkUtilsScript.payload_hash(value["projected_state"]):
		return ComputeUtilsScript.failure("SIMULATION_JOB_PROJECTED_STATE_HASH_MISMATCH")
	return ComputeUtilsScript.success()
