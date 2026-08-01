extends RefCounted

const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const ParametricUtils = preload("res://scripts/construction/parametric/construction_parametric_utils.gd")
const BundleScript = preload("res://scripts/construction/multiplayer/construction_multiplayer_state_bundle.gd")

const SCHEMA := "planet_simulator.construction_multiplayer_event.v1"
const FIELDS: Array[String] = ["schema", "event_index", "command_id", "command_checksum", "client_id", "action", "construct_id", "state_bundle", "checksum"]

static func create(event_index: int, command: Dictionary, state_bundle: Dictionary) -> Dictionary:
	var event := {"schema": SCHEMA, "event_index": event_index, "command_id": String(command["command_id"]), "command_checksum": String(command["checksum"]), "client_id": String(command["client_id"]), "action": String(command["action"]), "construct_id": String(command["construct_id"]), "state_bundle": state_bundle.duplicate(true), "checksum": ""}; event["checksum"] = compute_checksum(event); return event

static func validate(event: Dictionary) -> Dictionary:
	var exact := UtilsScript.validate_exact_fields(event, FIELDS); if not bool(exact.get("success", false)): return exact
	if event.get("schema") != SCHEMA or not UtilsScript.is_json_integer(event.get("event_index")) or int(event["event_index"]) < 0: return ParametricUtils.failure("INVALID_CONSTRUCTION_MULTIPLAYER_EVENT")
	for field in ["command_id", "client_id", "action", "construct_id"]:
		if typeof(event.get(field)) != TYPE_STRING or String(event[field]).is_empty(): return ParametricUtils.failure("INVALID_CONSTRUCTION_MULTIPLAYER_EVENT_IDENTITY")
	if typeof(event.get("command_checksum")) != TYPE_STRING or String(event["command_checksum"]).length() != 64: return ParametricUtils.failure("INVALID_CONSTRUCTION_MULTIPLAYER_EVENT_COMMAND_CHECKSUM")
	if typeof(event.get("state_bundle")) != TYPE_DICTIONARY: return ParametricUtils.failure("INVALID_CONSTRUCTION_MULTIPLAYER_EVENT_BUNDLE")
	var checked := BundleScript.validate(event["state_bundle"]); if not bool(checked.get("success", false)): return checked
	if String(event.get("checksum", "")) != compute_checksum(event): return ParametricUtils.failure("CONSTRUCTION_MULTIPLAYER_EVENT_CHECKSUM_MISMATCH")
	return ParametricUtils.success()

static func compute_checksum(event: Dictionary) -> String:
	var payload := event.duplicate(true); payload["checksum"] = ""; return UtilsScript.payload_hash(payload)
