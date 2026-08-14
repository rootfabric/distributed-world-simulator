extends SceneTree

const CellScript = preload("res://scripts/ui/inventory/item_cell.gd")
const ProfileLoaderScript = preload("res://scripts/ui/inventory/interactions/inventory_interaction_profile_loader.gd")

var assertions := 0
var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var loader = ProfileLoaderScript.new()
	var resolved: Dictionary = loader.resolve_profile("seven_days_like")
	_assert(bool(resolved.get("success", false)), "seven-days profile resolves")
	var profile = resolved.get("profile")
	_assert(profile != null, "seven-days profile exists")
	if profile == null:
		_finish()
		return

	var source = CellScript.new()
	get_root().add_child(source)
	source.set_interaction_profile(profile)
	source.render_cell({
		"item_id": "item/v0/test",
		"source_container_id": "world/shared",
		"source_slot_index": 0,
		"target_container_id": "world/shared",
		"target_slot_index": 0,
		"display_name": "Test",
		"quantity": 1,
	}, null, Callable())
	var source_events: Array = []
	source.interaction_requested.connect(func(action_id: String, payload: Dictionary):
		source_events.append({"action": action_id, "payload": payload.duplicate(true)})
	)
	source._gui_input(_left_press())
	_assert(source_events.size() == 1, "first carry click emits exactly once on press")
	if source_events.size() == 1:
		_assert(String(source_events[0]["payload"].get("input_phase", "")) == "PRESS", "first carry uses PRESS")

	var target = CellScript.new()
	get_root().add_child(target)
	target.set_interaction_profile(profile)
	target.render_cell({
		"item_id": "",
		"source_container_id": "inventory/a",
		"source_slot_index": 0,
		"target_container_id": "inventory/a",
		"target_slot_index": 0,
		"display_name": "Пусто",
		"quantity": 0,
	}, null, Callable())
	target.set_cursor_carry_state(true, true)
	var target_events: Array = []
	target.interaction_requested.connect(func(action_id: String, payload: Dictionary):
		target_events.append({"action": action_id, "payload": payload.duplicate(true)})
	)
	target._gui_input(_left_press())
	_assert(target_events.size() == 1, "cursor placement into empty slot emits on press")
	if target_events.size() == 1:
		var event: Dictionary = target_events[0]
		_assert(String(event.get("action", "")) == "CARRY_ALL_OR_PLACE_ALL", "placement action remains seven-days carry/place")
		var payload: Dictionary = event.get("payload", {})
		_assert(String(payload.get("input_phase", "")) == "PRESS", "placement uses PRESS instead of RELEASE")
		_assert(String(payload.get("target_container_id", "")) == "inventory/a", "placement keeps target container")
		_assert(int(payload.get("target_slot_index", -1)) == 0, "placement keeps target slot")
		_assert(String(payload.get("target_item_id", "x")) == "", "empty target remains empty")

	source.queue_free()
	target.queue_free()
	_finish()


func _left_press() -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	event.position = Vector2(12.0, 12.0)
	return event


func _assert(value: bool, message: String) -> void:
	assertions += 1
	if not value:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("V0-I2 inventory click-place: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("V0-I2 inventory click-place: FAIL (%d failures)" % failures.size())
	quit(1)
