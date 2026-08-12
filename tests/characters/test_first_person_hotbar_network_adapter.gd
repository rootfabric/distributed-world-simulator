extends SceneTree

const AdapterType = preload("res://scripts/characters/interaction/first_person_hotbar_network_adapter.gd")

var failures: Array[String] = []
var assertions := 0


class FakeRuntime:
	extends Node

	var ready := true
	var ownership_epoch := 7
	var sent_frames: Array[Dictionary] = []
	var item_graph_snapshot: Dictionary = {
		"inventories": {
			"a": {
				"inventory": [],
				"hotbar": ["item/a", "item/b", "", "", "", "", "", "", "", ""],
				"selected_hotbar_index": 0,
			},
		},
	}

	func is_ready() -> bool:
		return ready

	func get_local_player_record() -> Dictionary:
		return {"logical_player_id": "a", "ownership_epoch": ownership_epoch}

	func get_item_graph_snapshot() -> Dictionary:
		return item_graph_snapshot.duplicate(true)

	func _send_on_channel(
		message_type: String,
		payload: Dictionary,
		channel: int,
		reliability: String,
		expect_result: bool
	) -> bool:
		sent_frames.append({
			"message_type": message_type,
			"payload": payload.duplicate(true),
			"channel": channel,
			"reliability": reliability,
			"expect_result": expect_result,
		})
		return true


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var runtime := FakeRuntime.new()
	root.add_child(runtime)
	var adapter = AdapterType.new()
	var setup_result: Dictionary = adapter.setup(runtime, "a", 1000)
	_assert(bool(setup_result.get("success", false)), "adapter setup failed")
	_assert(adapter.canonical_selected_index() == 0, "initial canonical hotbar index mismatch")

	var started_us := Time.get_ticks_usec()
	var submitted: Dictionary = adapter.submit(1)
	var submit_duration_us := Time.get_ticks_usec() - started_us
	_assert(bool(submitted.get("success", false)), "nonblocking hotbar submit failed")
	_assert(submit_duration_us < 100000, "hotbar submit behaved like a blocking command")
	_assert(runtime.sent_frames.size() == 1, "hotbar submit did not send exactly one frame")
	if runtime.sent_frames.size() == 1:
		var frame: Dictionary = runtime.sent_frames[0]
		var payload: Dictionary = Dictionary(frame.get("payload", {}))
		_assert(String(frame.get("message_type", "")) == "ITEM_COMMAND", "wrong network message type")
		_assert(String(payload.get("command_type", "")) == "inventory.select_hotbar", "wrong item command type")
		_assert(int(payload.get("ownership_epoch", 0)) == 7, "ownership epoch not forwarded")
		_assert(int(Dictionary(payload.get("payload", {})).get("selected_hotbar_index", -1)) == 1, "hotbar index not forwarded")
		_assert(String(frame.get("reliability", "")) == "RELIABLE_ORDERED", "hotbar authority command must remain reliable ordered")

	var pending: Dictionary = adapter.poll()
	_assert(bool(pending.get("success", false)) and bool(Dictionary(pending.get("details", {})).get("pending", false)), "hotbar command was not reported pending before authority snapshot")

	runtime.item_graph_snapshot["inventories"]["a"]["selected_hotbar_index"] = 1
	var confirmed: Dictionary = adapter.poll()
	_assert(bool(confirmed.get("success", false)) and bool(Dictionary(confirmed.get("details", {})).get("confirmed", false)), "authority snapshot did not confirm predicted hotbar selection")
	var report: Dictionary = adapter.get_report()
	_assert(int(report.get("blocking_waits", -1)) == 0, "adapter must never perform blocking waits")
	_assert(int(report.get("confirmed", 0)) == 1, "confirmed counter mismatch")

	var invalid: Dictionary = adapter.submit(10)
	_assert(not bool(invalid.get("success", true)), "out-of-range hotbar index was accepted")

	runtime.queue_free()
	_finish()


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("FirstPerson hotbar nonblocking adapter: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("FirstPerson hotbar nonblocking adapter: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)
