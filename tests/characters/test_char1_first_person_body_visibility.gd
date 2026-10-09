extends SceneTree

# CHAR1 preview-only body visibility regression.
# Runs without external Quaternius assets: the same camera and avatar host
# policies apply to the real rig and to the fallback presenter.
const ViewerScene = preload(
	"res://scenes/labs/character/char1_realistic_avatar_viewer.tscn"
)

var assertions := 0
var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var viewer = ViewerScene.instantiate()
	get_root().add_child(viewer)
	for i in range(4):
		await process_frame
	_check(viewer._host != null, "avatar host initialized")
	if viewer._host == null:
		_finish(viewer)
		return
	var initial: Dictionary = viewer.create_report()
	_check(String(initial.get("view_mode", "")) == "THIRD_PERSON", "starts in third person")
	_check(bool(initial.get("local_body_visible", false)), "body visible in third person")
	_check(viewer._host.is_visible_in_tree(), "third-person avatar renders in tree")
	_check(viewer._third_person_camera.current, "third-person camera active")

	viewer.toggle_view_mode()
	await process_frame
	var first: Dictionary = viewer.create_report()
	_check(String(first.get("view_mode", "")) == "FIRST_PERSON", "switches to first person")
	_check(not bool(first.get("local_body_visible", true)), "first-person local body hidden")
	_check(not viewer._host.is_visible_in_tree(), "first-person avatar not rendered")
	_check(viewer._first_person_camera.current, "first-person camera remains active")
	_check(bool(first.get("first_person_mode", false)), "host receives first-person mode")
	viewer.set_semantic("run")
	_check(
		String(viewer.get_current_engine_semantic()) == "run",
		"presentation animation still updates while body hidden"
	)

	viewer.switch_character("character/procedural/standard")
	_check(not viewer._host.visible, "changing to procedural does not reveal body")
	_check(bool(viewer.create_report().get("first_person_mode", false)), "first-person mode survives swap")
	viewer.switch_character("character/quaternius/regular")
	_check(not viewer._host.visible, "changing back to Quaternius keeps body hidden")
	_check(
		String(viewer.get_current_engine_semantic()) == "run",
		"running presentation state survives both swaps"
	)

	viewer.toggle_view_mode()
	await process_frame
	var third: Dictionary = viewer.create_report()
	_check(String(third.get("view_mode", "")) == "THIRD_PERSON", "returns to third person")
	_check(bool(third.get("local_body_visible", false)), "third-person body visible again")
	_check(viewer._host.is_visible_in_tree(), "world model visible after toggle")
	_check(viewer._third_person_camera.current, "third-person camera restored")
	viewer.toggle_view_mode()
	_check(not viewer._host.visible, "second first-person entry hides body again")
	viewer.toggle_view_mode()
	_check(viewer._host.visible, "second third-person return restores body")
	_finish(viewer)


func _check(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


func _finish(viewer) -> void:
	if viewer != null:
		viewer.queue_free()
	if failures.is_empty():
		print("CHAR1 FIRST-PERSON BODY VISIBILITY: PASS (%d assertions, 0 failures)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error("[CHAR1 body visibility] " + failure)
	print("CHAR1 FIRST-PERSON BODY VISIBILITY: FAIL (%d assertions, %d failures)" % [
		assertions, failures.size()
	])
	quit(1)
