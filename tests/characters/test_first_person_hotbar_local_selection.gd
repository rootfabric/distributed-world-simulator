extends SceneTree

const LabType = preload("res://scripts/characters/lab/quaternius_first_person_embodiment_fix8.gd")

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

class FakeInventoryUI:
	extends RefCounted
	var refresh_calls := 0
	func _refresh_persistent_hotbar() -> void:
		refresh_calls += 1

class FakeController:
	extends RefCounted
	var player_hotbar_id := "player_hotbar"
	var selected_hotbar_index := 0
	var hotbar := FakeHotbar.new()
	var inventory_ui := FakeInventoryUI.new()
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
	func create_report() -> Dictionary:
		# The production lab debug snapshot asks the embodiment for its report.
		# This test double intentionally implements that observable port as well as
		# set/clear so a PASS cannot coexist with a GDScript SCRIPT ERROR.
		return {
			"schema": "test.fake_first_person_embodiment.v1",
			"right_item_id": right_item_id,
			"set_calls": set_calls,
			"clear_calls": clear_calls,
		}

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

	var selected: Dictionary = lab._select_hotbar_nonblocking(1)
	_assert(bool(selected.get("success", false)), "local hotbar selection failed")
	_assert(String(selected.get("code", "")) == "HOTBAR_LOCAL_PRESENTATION", "selection did not use local presentation mode")
	_assert(base.character_gameplay_controller.selected_hotbar_index == 1, "local selected index did not change immediately")
	_assert(embodiment.right_item_id == "item/b", "right-hand item did not change immediately")
	_assert(base.character_gameplay_controller.inventory_ui.refresh_calls == 1, "persistent hotbar did not refresh exactly once")
	_assert(bool(selected.get("details", {}).get("network_command_sent", true)) == false, "local selection unexpectedly sent a network command")
	_assert(bool(selected.get("details", {}).get("durable_checkpoint_requested", true)) == false, "local selection unexpectedly requested durability")

	var emptied: Dictionary = lab._select_hotbar_nonblocking(4)
	_assert(bool(emptied.get("success", false)), "empty local hotbar selection failed")
	_assert(base.character_gameplay_controller.selected_hotbar_index == 4, "empty local slot did not become selected")
	_assert(embodiment.right_item_id.is_empty(), "empty local slot retained the old hand item")
	_assert(embodiment.clear_calls == 1, "empty local slot did not clear the hand exactly once")

	var repeated: Dictionary = lab._select_hotbar_nonblocking(4)
	_assert(bool(repeated.get("success", false)), "repeated local hotbar selection failed")
	_assert(String(repeated.get("code", "")) == "HOTBAR_LOCAL_PRESENTATION_NOOP", "unchanged local selection did not become a no-op")
	_assert(embodiment.clear_calls == 1, "unchanged empty slot redundantly cleared the hand")

	# A later canonical structural projection may carry an old durable selected
	# index. Fix8 must retain canonical item contents but ignore that presentation
	# field for the local player.
	base.character_gameplay_controller.selected_hotbar_index = 0
	lab._on_fpe_canonical_projection_applied("FULL_GRAPH", {})
	_assert(base.character_gameplay_controller.selected_hotbar_index == 4, "canonical projection overwrote local hotbar presentation selection")

	var report: Dictionary = lab.get_first_person_embodiment_debug_snapshot().get("fix8", {})
	_assert(String(report.get("selection_mode", "")) == "CLIENT_LOCAL_PRESENTATION", "Fix8 selection ownership report mismatch")
	_assert(int(report.get("server_hotbar_commands_sent", -1)) == 0, "Fix8 reported a server hotbar command")
	_assert(int(report.get("durable_hotbar_checkpoints_requested", -1)) == 0, "Fix8 reported a durable hotbar checkpoint")
	_assert(bool(report.get("item_actions_remain_server_authoritative", false)), "Fix8 weakened item-action authority")

	lab.free()
	_finish()


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("FirstPerson hotbar local selection: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("FirstPerson hotbar local selection: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)
