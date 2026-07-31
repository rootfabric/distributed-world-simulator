extends RefCounted

const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const ConstructStoreScript = preload("res://scripts/construction/authoritative/construction_construct_store.gd")

const SCHEMA: String = "planet_simulator.authoritative_construction_state.v1"
const FIELDS: Array[String] = [
	"schema",
	"authority_owner_id",
	"authority_epoch",
	"item_graph_revision",
	"ledger_revision",
	"server_tick",
	"construct_authority_revisions",
	"item_registry",
	"container_registry",
	"construct_store",
	"operation_ledger",
	"checksum",
]


static func create(
	authority_owner_id: String,
	authority_epoch: int,
	item_graph_revision: int,
	ledger_revision: int,
	server_tick: int,
	construct_authority_revisions: Dictionary,
	item_registry_state: Dictionary,
	container_registry_state: Dictionary,
	construct_store_state: Dictionary,
	operation_ledger_state: Dictionary
) -> Dictionary:
	var state: Dictionary = {
		"schema": SCHEMA,
		"authority_owner_id": authority_owner_id,
		"authority_epoch": authority_epoch,
		"item_graph_revision": item_graph_revision,
		"ledger_revision": ledger_revision,
		"server_tick": server_tick,
		"construct_authority_revisions": _canonical_dict(construct_authority_revisions),
		"item_registry": _canonical_dict(item_registry_state),
		"container_registry": _canonical_dict(container_registry_state),
		"construct_store": _canonical_dict(construct_store_state),
		"operation_ledger": _canonical_dict(operation_ledger_state),
		"checksum": "",
	}
	state["checksum"] = compute_checksum(state)
	return state


static func validate(state: Dictionary) -> Dictionary:
	var exact: Dictionary = UtilsScript.validate_exact_fields(state, FIELDS)
	if not bool(exact.get("success", false)):
		return exact
	if state.get("schema") != SCHEMA:
		return _failure("UNSUPPORTED_AUTHORITATIVE_CONSTRUCTION_STATE_SCHEMA")
	if not _is_identifier(String(state.get("authority_owner_id", ""))):
		return _failure("INVALID_CONSTRUCTION_AUTHORITY_OWNER")
	for field in ["authority_epoch", "item_graph_revision", "ledger_revision", "server_tick"]:
		if not UtilsScript.is_json_integer(state.get(field)):
			return _failure("INVALID_AUTHORITATIVE_CONSTRUCTION_INTEGER", {"field": field})
	if int(state["authority_epoch"]) < 1 or int(state["item_graph_revision"]) < 0 or int(state["ledger_revision"]) < 0 or int(state["server_tick"]) < 0:
		return _failure("INVALID_AUTHORITATIVE_CONSTRUCTION_REVISION")
	if typeof(state.get("construct_authority_revisions")) != TYPE_DICTIONARY:
		return _failure("INVALID_CONSTRUCT_AUTHORITY_REVISIONS")
	for construct_id in state["construct_authority_revisions"]:
		if not String(construct_id).begins_with("construct/") or not UtilsScript.is_json_integer(state["construct_authority_revisions"][construct_id]) or int(state["construct_authority_revisions"][construct_id]) < 0:
			return _failure("INVALID_CONSTRUCT_AUTHORITY_REVISION", {"construct_id": construct_id})
	for field in ["item_registry", "container_registry", "construct_store", "operation_ledger"]:
		if typeof(state.get(field)) != TYPE_DICTIONARY:
			return _failure("INVALID_AUTHORITATIVE_CONSTRUCTION_SECTION", {"field": field})
	if String(state["item_registry"].get("schema", "")) != "planet_simulator.item_registry.v2" or int(state["item_registry"].get("schema_version", 0)) != 2:
		return _failure("INVALID_AUTHORITATIVE_ITEM_REGISTRY_SCHEMA")
	if String(state["container_registry"].get("schema", "")) != "planet_simulator.container_registry.v2" or int(state["container_registry"].get("schema_version", 0)) != 2:
		return _failure("INVALID_AUTHORITATIVE_CONTAINER_REGISTRY_SCHEMA")
	if String(state["operation_ledger"].get("schema", "")) != "planet_simulator.item_operation_ledger.v1" or int(state["operation_ledger"].get("schema_version", 0)) != 1:
		return _failure("INVALID_AUTHORITATIVE_OPERATION_LEDGER_SCHEMA")
	var construct_validation: Dictionary = ConstructStoreScript.validate_state(state["construct_store"])
	if not bool(construct_validation.get("success", false)):
		return construct_validation
	var declared_construct_ids: Array[String] = []
	for snapshot in state["construct_store"].get("constructs", []):
		declared_construct_ids.append(String(snapshot.get("construct_id", "")))
	declared_construct_ids.sort()
	var revision_construct_ids: Array[String] = []
	for construct_id in state["construct_authority_revisions"].keys():
		revision_construct_ids.append(String(construct_id))
	revision_construct_ids.sort()
	if declared_construct_ids != revision_construct_ids:
		return _failure("CONSTRUCT_AUTHORITY_REVISION_SET_MISMATCH")
	if typeof(state.get("checksum")) != TYPE_STRING or String(state["checksum"]) != compute_checksum(state):
		return _failure("AUTHORITATIVE_CONSTRUCTION_STATE_CHECKSUM_MISMATCH")
	if not bool(UtilsScript.canonicalize(state).get("success", false)):
		return _failure("AUTHORITATIVE_CONSTRUCTION_STATE_NOT_JSON_SAFE")
	return _success()


static func compute_checksum(state: Dictionary) -> String:
	var payload: Dictionary = state.duplicate(true)
	payload["checksum"] = ""
	return UtilsScript.payload_hash(payload)


static func _canonical_dict(value: Dictionary) -> Dictionary:
	var result: Dictionary = UtilsScript.canonicalize(value)
	if not bool(result.get("success", false)):
		return value.duplicate(true)
	return Dictionary(result.get("value", {}))


static func _is_identifier(value: String) -> bool:
	if value.is_empty() or value != value.strip_edges():
		return false
	for character in value:
		var text := String(character)
		if not text.to_lower() in ["a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m", "n", "o", "p", "q", "r", "s", "t", "u", "v", "w", "x", "y", "z"] and not text in ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "-", "_", "/", ":", "."]:
			return false
	return true


static func _success(details: Dictionary = {}) -> Dictionary:
	var result: Dictionary = {"success": true, "error_code": "", "message": ""}
	for key in details:
		result[key] = details[key]
	return result


static func _failure(code: String, details: Dictionary = {}) -> Dictionary:
	var result: Dictionary = {"success": false, "error_code": code, "message": code}
	for key in details:
		result[key] = details[key]
	return result
