extends RefCounted

const Utils = preload("res://scripts/network/contracts/network_contract_utils.gd")

const SCHEMA := "planet_simulator.shared_item_fixture_service.v1"
const DURABLE_SCHEMA := "planet_simulator.shared_item_fixture_state.v1"
const SHARED_ITEM_ID := "item/shared/beacon/1"
var _item: Dictionary = {}

func setup() -> Dictionary:
	_item = {"item_id": SHARED_ITEM_ID, "available": true, "owner_player_entity_id": "", "revision": 0}
	return _success({"item": get_item()})

func claim(item_id: String, player_entity_id: String) -> Dictionary:
	if item_id != SHARED_ITEM_ID:
		return _failure("ITEM_NOT_FOUND")
	if not bool(_item.get("available", false)):
		return _failure("ITEM_ALREADY_CLAIMED", {"owner_player_entity_id": String(_item.get("owner_player_entity_id", ""))})
	_item["available"] = false
	_item["owner_player_entity_id"] = player_entity_id
	_item["revision"] = int(_item.get("revision", 0)) + 1
	return _success({"item": get_item()})

func get_item() -> Dictionary:
	return _item.duplicate(true)

func export_durable_state() -> Dictionary:
	var state := {"schema": DURABLE_SCHEMA, "item": get_item(), "checksum": ""}
	state["checksum"] = _checksum(state)
	return state

func restore_durable_state(value: Dictionary) -> Dictionary:
	var validation := validate_durable_state(value)
	if not bool(validation.get("success", false)):
		return validation
	_item = Dictionary(value.get("item", {})).duplicate(true)
	return _success({"item": get_item()})

func validate_durable_state(value: Dictionary) -> Dictionary:
	if String(value.get("schema", "")) != DURABLE_SCHEMA:
		return _failure("INVALID_SHARED_ITEM_STATE_SCHEMA")
	if typeof(value.get("item")) != TYPE_DICTIONARY or typeof(value.get("checksum")) != TYPE_STRING:
		return _failure("INVALID_SHARED_ITEM_STATE")
	if String(value.get("checksum", "")) != _checksum(value):
		return _failure("SHARED_ITEM_STATE_CHECKSUM_MISMATCH")
	var item: Dictionary = value.get("item", {})
	if String(item.get("item_id", "")) != SHARED_ITEM_ID:
		return _failure("INVALID_SHARED_ITEM_ID")
	if typeof(item.get("available")) != TYPE_BOOL or int(item.get("revision", -1)) < 0:
		return _failure("INVALID_SHARED_ITEM_RECORD")
	var owner := String(item.get("owner_player_entity_id", ""))
	if bool(item.get("available", false)) and not owner.is_empty():
		return _failure("AVAILABLE_SHARED_ITEM_HAS_OWNER")
	if not bool(item.get("available", false)) and owner.is_empty():
		return _failure("CLAIMED_SHARED_ITEM_OWNER_REQUIRED")
	var safe := Utils.canonicalize(value, "$.shared_item")
	if not bool(safe.get("success", false)):
		return _failure("SHARED_ITEM_STATE_NOT_JSON_SAFE", {"message": String(safe.get("error", ""))})
	return _success()

func get_report() -> Dictionary:
	return {"schema": SCHEMA, "item": get_item()}

func _checksum(value: Dictionary) -> String:
	var payload := value.duplicate(true)
	payload.erase("checksum")
	return Utils.payload_hash(payload)

func _success(details: Dictionary = {}) -> Dictionary:
	return {"success": true, "error_code": "", "details": details.duplicate(true)}

func _failure(error_code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": error_code, "details": details.duplicate(true)}
