extends SceneTree

# CHAR2 camera-only contract: the real local Earth camera is switched without
# installing another controller or changing remote-avatar visibility.
const EarthApp = preload("res://scripts/app/earth_char1_avatar_app.gd")

class FakeExplorer:
	extends Node3D
	var camera: Camera3D
	func get_camera() -> Camera3D:
		return camera

class FakeAvatar:
	extends Node3D
	var first_person := true
	var calls := 0
	func set_first_person_mode(enabled: bool) -> void:
		first_person = enabled
		visible = not enabled
		calls += 1
	func create_report() -> Dictionary:
		return {"local_body_visible": visible, "first_person_mode": first_person}

var assertions := 0
var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var app = EarthApp.new()
	var scene_root := Node3D.new()
	root.add_child(scene_root)
	var explorer := FakeExplorer.new()
	scene_root.add_child(explorer)
	var first := Camera3D.new()
	explorer.add_child(first)
	first.current = true
	explorer.camera = first
	var third := Camera3D.new()
	explorer.add_child(third)
	third.current = false
	var avatar := FakeAvatar.new()
	scene_root.add_child(avatar)
	app.earth_explorer = explorer
	app.char1_avatar_presentation = avatar
	app._char1_third_person_camera = third
	_check(first.current, "first-person camera initially current")
	var changed: Dictionary = app.set_char1_camera_third_person(true)
	_check(bool(changed.get("success", false)), "third-person transition accepted")
	_check(third.current and not first.current, "third-person camera takes over")
	_check(avatar.visible and not avatar.first_person, "local avatar shown only in third person")
	_check(int(app._char1_camera_toggles) == 1, "camera transition tracked")
	changed = app.set_char1_camera_third_person(false)
	_check(bool(changed.get("success", false)), "first-person transition accepted")
	_check(first.current and not third.current, "first-person camera restored")
	_check(not avatar.visible and avatar.first_person, "local avatar hidden in first person")
	_check(int(app._char1_camera_toggles) == 2, "second transition tracked")
	var report: Dictionary = app._command_char1_camera_status([])
	_check(bool(report.get("success", false)), "read-only camera status works")
	_check(String(report.get("details", {}).get("view", "")) == "FIRST_PERSON", "camera status is first-person")
	_check(not bool(report.get("details", {}).get("local_body_visible", true)), "camera status cannot claim local body visible")
	var toggle: Dictionary = app._command_char1_camera_toggle([])
	_check(bool(toggle.get("success", false)), "F1 camera toggle command accepted")
	_check(third.current and avatar.visible, "F1 toggle selects third-person and restores body")
	_check(avatar.calls == 3, "avatar interface receives exactly one call per switch")
	_check(app._m3_remote_presenters.is_empty(), "camera toggle does not invent remote players")
	app.free()
	scene_root.queue_free()
	await process_frame
	if failures.is_empty():
		print("CHAR2 PRODUCT CAMERA: PASS (%d assertions, 0 failures)" % assertions)
		quit(0)
	else:
		for message in failures:
			push_error("[CHAR2 camera] " + message)
		print("CHAR2 PRODUCT CAMERA: FAIL (%d assertions, %d failures)" % [assertions, failures.size()])
		quit(1)


func _check(ok: bool, description: String) -> void:
	assertions += 1
	if not ok:
		failures.append(description)
