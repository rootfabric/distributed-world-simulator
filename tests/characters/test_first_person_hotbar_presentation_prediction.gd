extends SceneTree

const LabType = preload("res://scripts/characters/lab/quaternius_first_person_embodiment_fix7.gd")

class FakeItem:
	extends RefCounted
	var definition_id := "survey_beacon"

class FakeDefinition:
	extends RefCounted
	var display_name := "Beacon"
	var metadata: Dictionary = {"icon_color": [1.0, 0.3, 0.1, 1.0]}

class FakeHotbar:
	extends RefCounted
	var slot_count := 10
	var slots: Array[String] = ["item/a", "item/b", "", "", "", "", "", "", "", ""]
	func get_item_at_slot(index: int) -> String:
		return slots[index] if index >= 0 and index < slots.size() else ""

class FakeController:
	extends RefCounted
	var player_hotbar_id := "player_hotbar"
	var selected_hotbar_index := 0
	var hotbar := FakeHotbar.new()
	var item := FakeItem.new()
	var definition := FakeDefinition.new()
	func get_container(container_id: String):
		return hotbar if container_id == player_hotbar_id else null
	func get_item(item_id: String):
		return item if item_id in ["item/a", "item/b"] else null
	func get_definition(definition_id: String):
		return definition if definition_id == "survey_beacon" else null

class FakeBaseLab:
	extends RefCounted
	var character_gameplay_controller := FakeController.new()
	var network_ready := true

class FakeEmbodiment:
	extends RefCounted
	var right_item_id := ""
	var set_calls := 0
	var clear_calls := 0
	func set_authoritative_hand_item(hand_id: String, item_id: String, _display_name: String = "", _color: Color = Color.WHITE) -> Dictionary:
		if hand_id != "right":
			return {"success": false, "error_code": "WRONG_HAND"}
		right_item_id = item_id
		set_calls += 1
		return {"success": true, "details": {"item_id": item_id}}
	func clear_authoritative_hand_item(hand_id: String) -> Dictionary:
		if hand_id != "right":
			return {"success": false, "error_code": "WRONG_HAND"}
		right_item_id = ""
		clear_calls += 1
		return {"success": true}

var failures: Array[String] = []
var assertions := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var lab = LabType.new()
	var base := FakeBaseLab.new()
	var embodiment := FakeEmbodiment.new()
	lab.base_lab = base
	lab.first_person_embodiment = embodiment

	var selected: Dictionary = lab._apply_hotbar_presentation_for_index(0)
	_assert(bool(selected.get("success", false)), "non-empty predicted slot did not apply")
	_assert(embodiment.right_item_id == "item/a", "predicted item did not appear in right hand")
	_assert(embodiment.set_calls == 1, "predicted item was not set exactly once")

	var emptied: Dictionary = lab._apply_hotbar_presentation_for_index(4)
	_assert(bool(emptied.get("success", false)), "empty predicted slot did not apply")
	_assert(embodiment.right_item_id.is_empty(), "empty hotbar slot retained stale hand item")
	_assert(embodiment.clear_calls == 1, "empty hotbar slot did not clear the hand proxy")
	_assert(lab._last_hotbar_item_id.is_empty(), "empty slot did not become the presentation fingerprint")

	var repeated: Dictionary = lab._apply_hotbar_presentation_for_index(4)
	_assert(bool(repeated.get("success", false)), "repeated empty slot failed")
	_assert(embodiment.clear_calls == 1, "unchanged empty slot redundantly cleared the hand")
	_assert(lab._hotbar_local_prediction_applies == 2, "local prediction apply counter mismatch")
	_assert(lab._hotbar_local_prediction_clears == 1, "local prediction clear counter mismatch")

	lab.free()
	_finish()


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("FirstPerson hotbar presentation prediction: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("FirstPerson hotbar presentation prediction: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)
