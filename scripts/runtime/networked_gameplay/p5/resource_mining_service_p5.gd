extends "res://scripts/runtime/networked_gameplay/p3/resource_mining_service.gd"

const REQUIRED_EQUIPMENT_SLOT := "tool/main"
const REQUIRED_TOOL_DEFINITION_ID := "item/tool/mining"


func _validate_mining_capability(logical_player_id: String) -> Dictionary:
	if _item_graph == null or not _item_graph.has_method("get_equipped_item"):
		return _failure("MINING_EQUIPMENT_PORT_INVALID")
	var equipped: Dictionary = _item_graph.get_equipped_item(
		logical_player_id,
		REQUIRED_EQUIPMENT_SLOT
	)
	if (
		equipped.is_empty()
		or String(equipped.get("definition_id", "")) != REQUIRED_TOOL_DEFINITION_ID
		or int(equipped.get("quantity", 0)) != 1
	):
		return _failure("MINING_TOOL_REQUIRED", {
			"required_definition_id": REQUIRED_TOOL_DEFINITION_ID,
			"slot_id": REQUIRED_EQUIPMENT_SLOT,
		})
	return _success({
		"item_id": String(equipped.get("item_id", "")),
		"definition_id": REQUIRED_TOOL_DEFINITION_ID,
		"slot_id": REQUIRED_EQUIPMENT_SLOT,
	})
