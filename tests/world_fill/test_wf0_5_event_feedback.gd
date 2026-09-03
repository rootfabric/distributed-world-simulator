extends SceneTree

## WF0.5 Unified Presentation Event Feedback tests.
## Run: godot --headless --path <project> --script res://tests/world_fill/test_wf0_5_event_feedback.gd

const FeedbackScript = preload("res://scripts/world_fill/feedback/world_fill_event_feedback.gd")

var failures: Array[String] = []


func _init() -> void:
	_test_initial_event_routing()
	_test_unconfigured_channels_are_skipped_not_errors()
	_test_global_disable()
	_test_position_carried_to_channels()
	_test_unknown_event_fail_soft()
	_test_non_owning_no_state_accumulation()
	_finish()


func _test_initial_event_routing() -> void:
	var feedback := FeedbackScript.new()
	var received := {}
	feedback.configure("audio", func(event: Dictionary) -> void: received["audio"] = true)
	feedback.configure("vfx", func(event: Dictionary) -> void: received["vfx"] = true)
	feedback.configure("camera", func(event: Dictionary) -> void: received["camera"] = true)
	feedback.configure("ui", func(event: Dictionary) -> void: received["ui"] = true)
	var expectations := {
		"DIG_IMPACT": ["vfx", "audio"],
		"DIG_SUCCESS": ["vfx", "audio", "ui"],
		"PICKUP": ["audio", "ui"],
		"DROP": ["audio", "ui"],
		"BUILD_COMMIT": ["vfx", "audio", "ui"],
		"HANDOFF": ["camera", "ui"],
		"COMMAND_REJECTED": ["ui"],
		"ITEM_TRANSFER": ["ui"],
	}
	for event_type in expectations:
		received.clear()
		var report: Dictionary = feedback.dispatch({"type": event_type, "position": Vector3.ZERO})
		var invoked: Dictionary = report.get("invoked", {})
		_assert(invoked.size() == (expectations[event_type] as Array).size(),
			"%s invoked wrong channel count." % event_type)
		for channel_name in expectations[event_type]:
			_assert(bool(invoked.get(channel_name, false)) and received.has(channel_name),
				"%s did not invoke %s." % [event_type, channel_name])


func _test_unconfigured_channels_are_skipped_not_errors() -> void:
	var feedback := FeedbackScript.new()
	var report: Dictionary = feedback.dispatch({"type": "HANDOFF", "position": Vector3.ZERO})
	_assert(String(report.get("event_type", "")) == "HANDOFF", "Report lost event type.")
	var skipped: Dictionary = report.get("skipped", {})
	_assert(String(skipped.get("camera", "")) == "CHANNEL_UNCONFIGURED", "Camera channel skip reason wrong.")
	_assert(String(skipped.get("ui", "")) == "CHANNEL_UNCONFIGURED", "UI channel skip reason wrong.")
	_assert((report.get("invoked", {}) as Dictionary).is_empty(), "Nothing should be invoked without channels.")


func _test_global_disable() -> void:
	var feedback := FeedbackScript.new()
	var calls := [0]
	feedback.configure("ui", func(_event: Dictionary) -> void: calls[0] += 1)
	feedback.set_enabled(false)
	var report: Dictionary = feedback.dispatch({"type": "PICKUP", "position": Vector3.ZERO})
	_assert(calls[0] == 0, "Disabled adapter still invoked a channel.")
	_assert(not feedback.is_enabled(), "is_enabled disagrees with state.")
	_assert(String(report.get("skipped", {}).get("audio", "")) == "DISABLED", "Disable reason missing for unconfigured audio.")
	_assert(String(report.get("skipped", {}).get("ui", "")) == "DISABLED", "Disable reason missing for ui.")
	feedback.set_enabled(true)
	feedback.dispatch({"type": "PICKUP", "position": Vector3.ZERO})
	_assert(calls[0] == 1, "Re-enable did not restore dispatch.")


func _test_position_carried_to_channels() -> void:
	var feedback := FeedbackScript.new()
	var seen := []
	feedback.configure("vfx", func(event: Dictionary) -> void: seen.append(event.get("position", Vector3(-1, -1, -1))))
	var source := Vector3(3.5, 0.25, -7.25)
	feedback.dispatch({"type": "DIG_IMPACT", "position": source})
	_assert(not seen.is_empty() and seen[0] == source, "Event position was not carried to the channel.")


func _test_unknown_event_fail_soft() -> void:
	var feedback := FeedbackScript.new()
	var calls := [0]
	feedback.configure("ui", func(_event: Dictionary) -> void: calls[0] += 1)
	var report: Dictionary = feedback.dispatch({"type": "SOMETHING_ELSE", "position": Vector3.ZERO})
	_assert(calls[0] == 0, "Unknown event reached a channel.")
	_assert(not bool(report.get("known_event", true)), "Unknown event not flagged.")
	_assert(String(report.get("skipped", {}).get("all", "")) == "UNKNOWN_EVENT_TYPE", "Unknown event skip reason missing.")


func _test_non_owning_no_state_accumulation() -> void:
	var feedback := FeedbackScript.new()
	feedback.configure("ui", func(_event: Dictionary) -> void: pass)
	var first: Dictionary = feedback.dispatch({"type": "PICKUP", "position": Vector3.ZERO})
	var second: Dictionary = feedback.dispatch({"type": "DROP", "position": Vector3(1.0, 0.0, 1.0)})
	_assert(
		String(first.get("event_type", "")) == "PICKUP" and String(second.get("event_type", "")) == "DROP",
		"Adapter mixed event state across dispatches."
	)
	_assert(
		(first.get("invoked", {}) as Dictionary).size() == 1 and (second.get("invoked", {}) as Dictionary).size() == 1,
		"Adapter accumulated invoked-channel state."
	)


func _finish() -> void:
	if failures.is_empty():
		print("WF0.5 event feedback tests: PASS")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("WF0.5 event feedback tests: FAIL (%d)" % failures.size())
	quit(1)


func _assert(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

