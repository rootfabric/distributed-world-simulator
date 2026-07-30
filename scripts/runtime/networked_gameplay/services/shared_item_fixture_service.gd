extends RefCounted

const SCHEMA := "planet_simulator.shared_item_fixture_service.v1"
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

func get_item() -> Dictionary: return _item.duplicate(true)
func get_report() -> Dictionary: return {"schema": SCHEMA, "item": get_item()}
func _success(details: Dictionary = {}) -> Dictionary: return {"success": true, "error_code": "", "details": details.duplicate(true)}
func _failure(error_code: String, details: Dictionary = {}) -> Dictionary: return {"success": false, "error_code": error_code, "details": details.duplicate(true)}
