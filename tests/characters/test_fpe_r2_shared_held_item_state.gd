extends SceneTree

const LabType = preload("res://scripts/characters/lab/quaternius_first_person_embodiment_fix9.gd")
const HeldStateType = preload("res://scripts/characters/presentation/held_item_presentation_state.gd")

class FakeItem:
	extends RefCounted
	var definition_id := "survey_beacon"

class FakeDefinition:
	extends RefCounted
	var display_name := "Beacon"
	var metadata: Dictionary = {"icon_color": [0.8, 0.3, 0.1, 1.0]}

class FakeHotbar:
	extends RefCounted
	var slot_count := 10
	var slots: Array[String] = ["item/a", "", "", "", "", "", "", "", "", ""]
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
		return item if item_id == "item/a" else null
	func get_definition(definition_id: String):
		return definition if definition_id == "survey_beacon" else null

class FakeBaseLab:
	extends RefCounted
	var character_gameplay_controller := FakeController.new()

class FakeFirstPerson:
	extends RefCounted
	var item_id := ""
	var set_calls := 0
	var clear_calls := 0
	func set_authoritative_hand_item(hand_id: String, new_item_id: String, _display_name: String = "", _color: Color = Color.WHITE) -> Dictionary:
		if hand_id != "right":
			return {"success": false, "error_code": "WRONG_HAND"}
		item_id = new_item_id
		set_calls += 1
		return {"success": true, "error_code": ""}
	func clear_authoritative_hand_item(hand_id: String) -> Dictionary:
		if hand_id != "right":
			return {"success": false, "error_code": "WRONG_HAND"}
		item_id = ""
		clear_calls += 1
		return {"success": true, "error_code": ""}

class FakeThirdPerson:
	extends RefCounted
	var item_id := ""
	var set_calls := 0
	var clear_calls := 0
	func present_item(new_item_id: String, _display_name: String = "", _color: Color = Color.WHITE) -> Dictionary:
		item_id = new_item_id
		set_calls += 1
		return {"success": true, "error_code": "", "details": {"attachment_mode": "TEST"}}
	func clear_item() -> Dictionary:
		item_id = ""
		clear_calls += 1
		return {"success": true, "error_code": ""}
	func create_report() -> Dictionary:
		return {"current_item_id": item_id, "presentation_only": true}

var failures: Array[String] = []
var assertions := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var lab = LabType.new()
	var state = HeldStateType.new()
	var first := FakeFirstPerson.new()
	var third := FakeThirdPerson.new()
	lab.base_lab = FakeBaseLab.new()
	lab.first_person_embodiment = first
	lab.third_person_held_item_presenter = third
	lab.held_item_presentation_state = state
	state.changed.connect(lab._on_held_item_presentation_changed)

	var selected: Dictionary = lab._apply_hotbar_presentation_for_index(0)
	_assert(bool(selected.get("success", false)), "R2 occupied hotbar selection failed")
	_assert(bool(selected.get("details", {}).get("shared_held_state", false)), "R2 selection did not report shared held state")
	_assert(first.item_id == "item/a", "R2 first-person presenter did not receive selected item")
	_assert(third.item_id == "item/a", "R2 third-person presenter did not receive selected item")
	_assert(first.set_calls == 1, "R2 first-person selected item applied unexpected number of times")
	_assert(third.set_calls == 1, "R2 third-person selected item applied unexpected number of times")
	var occupied_state: Dictionary = state.get_hand_snapshot("right")
	_assert(String(occupied_state.get("item_id", "")) == "item/a", "R2 held state did not retain canonical item identity")
	_assert(int(occupied_state.get("selected_slot_index", -1)) == 0, "R2 held state did not retain selected slot presentation metadata")
	_assert(String(occupied_state.get("source", "")) == "HOTBAR_LOCAL_SELECTION", "R2 held state source mismatch")

	var emptied: Dictionary = lab._apply_hotbar_presentation_for_index(1)
	_assert(bool(emptied.get("success", false)), "R2 empty hotbar selection failed")
	_assert(first.item_id.is_empty(), "R2 empty slot did not clear first-person item")
	_assert(third.item_id.is_empty(), "R2 empty slot did not clear third-person item")
	_assert(first.clear_calls == 1, "R2 first-person clear count mismatch")
	_assert(third.clear_calls == 1, "R2 third-person clear count mismatch")
	var empty_state: Dictionary = state.get_hand_snapshot("right")
	_assert(String(empty_state.get("item_id", "")).is_empty(), "R2 held state retained stale item after empty slot")
	_assert(int(empty_state.get("selected_slot_index", -1)) == 1, "R2 empty held state did not retain selected slot metadata")

	var state_report: Dictionary = state.create_report()
	_assert(bool(state_report.get("transient", false)), "R2 held state is not marked transient")
	_assert(not bool(state_report.get("durable", true)), "R2 held state incorrectly claims durability")
	_assert(not bool(state_report.get("owns_item_state", true)), "R2 held state incorrectly owns canonical item state")
	_assert(not bool(state_report.get("owns_network_state", true)), "R2 held state incorrectly owns network state")

	lab.free()
	_finish()


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("FPE R2 shared held-item state: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("FPE R2 shared held-item state: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)
