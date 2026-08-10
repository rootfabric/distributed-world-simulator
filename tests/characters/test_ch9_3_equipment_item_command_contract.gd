extends SceneTree

const ItemCommand = preload("res://scripts/runtime/networked_gameplay/contracts/item_command.gd")
const NetworkCommand = preload("res://scripts/network/contracts/network_command_envelope.gd")

var failures: Array[String] = []
var assertions := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var equipment_command: Dictionary = NetworkCommand.create(
		"message/ch9-3/equipment",
		"operation/ch9-3/equipment-contract",
		"a",
		"transport-session/ch9-3/equipment-contract",
		1,
		1,
		-1,
		"equipment.equip",
		{"item_id": "item/player/a/wearable/lower", "slot_index": 3}
	)
	_assert(bool(ItemCommand.validate_network_envelope(equipment_command).get("success", false)), "CH9.3 equipment command rejected by item command contract")

	var unrelated := equipment_command.duplicate(true)
	unrelated["command_type"] = "character.secret_mutation"
	_assert(not bool(ItemCommand.validate_network_envelope(unrelated).get("success", false)), "CH9.3 item command contract widened beyond equipment namespace")

	_finish()


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("CH9.3 equipment item command contract: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("CH9.3 equipment item command contract: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)
