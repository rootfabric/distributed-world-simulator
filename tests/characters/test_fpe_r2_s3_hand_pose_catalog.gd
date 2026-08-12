extends SceneTree

const PoseCatalogType = preload("res://scripts/characters/presentation/first_person_hand_pose_catalog.gd")

var failures: Array[String] = []
var assertions := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var catalog = PoseCatalogType.new()
	var open_pose: Dictionary = catalog.get_open_pose()
	var flashlight: Dictionary = catalog.resolve(
		{"profile_id": "flashlight_forward"},
		{"profile_id": "flashlight", "visual_kind": "CYLINDER"}
	)
	var beacon: Dictionary = catalog.resolve(
		{"profile_id": "beacon_vertical"},
		{"profile_id": "beacon", "visual_kind": "CYLINDER"}
	)
	var bulky: Dictionary = catalog.resolve(
		{"profile_id": "bulky_carry"},
		{"profile_id": "backpack", "visual_kind": "BOX"}
	)
	var generic: Dictionary = catalog.resolve(
		{"profile_id": "generic_box"},
		{"profile_id": "generic_box", "visual_kind": "BOX"}
	)

	_assert(String(open_pose.get("pose_id", "")) == "open", "S3 open pose id mismatch")
	_assert(String(flashlight.get("pose_id", "")) == "flashlight_wrap", "S3 flashlight did not resolve wrap pose")
	_assert(String(beacon.get("pose_id", "")) == "beacon_pinch", "S3 beacon did not resolve pinch pose")
	_assert(String(bulky.get("pose_id", "")) == "bulky_carry", "S3 bulky grip did not resolve carry pose")
	_assert(String(generic.get("pose_id", "")) == "generic_wrap", "S3 generic grip did not resolve generic wrap")
	_assert(String(flashlight.get("pose_id", "")) != String(beacon.get("pose_id", "")), "S3 flashlight and beacon collapsed to one hand pose")

	var open_curls: Dictionary = Dictionary(open_pose.get("finger_curl_deg", {}))
	var flashlight_curls: Dictionary = Dictionary(flashlight.get("finger_curl_deg", {}))
	var open_index: Array = Array(open_curls.get("index", []))
	var flashlight_index: Array = Array(flashlight_curls.get("index", []))
	_assert(open_index.size() == 3, "S3 open index chain does not have three joints")
	_assert(flashlight_index.size() == 3, "S3 flashlight index chain does not have three joints")
	if open_index.size() == 3 and flashlight_index.size() == 3:
		_assert(float(flashlight_index[0]) > float(open_index[0]) + 20.0, "S3 flashlight pose does not visibly curl index proximal joint")
		_assert(float(flashlight_index[1]) > float(open_index[1]) + 30.0, "S3 flashlight pose does not visibly curl index middle joint")
	_assert(float(beacon.get("thumb_opposition_deg", 0.0)) != float(open_pose.get("thumb_opposition_deg", 0.0)), "S3 beacon pinch does not change thumb opposition")
	_assert(int(flashlight.get("transition_ms", 0)) > 0, "S3 pose transition duration is not bounded positive")

	var report: Dictionary = catalog.create_report()
	var pose_ids: Array = Array(report.get("pose_ids", []))
	_assert(pose_ids.size() >= 7, "S3 pose library lost required profile coverage")
	_assert(pose_ids.has("open"), "S3 pose library report lost open pose")
	_assert(pose_ids.has("flashlight_wrap"), "S3 pose library report lost flashlight pose")
	_assert(pose_ids.has("beacon_pinch"), "S3 pose library report lost beacon pose")
	_assert(bool(report.get("presentation_only", false)), "S3 pose catalog is not presentation-only")
	_assert(not bool(report.get("owns_item_state", true)), "S3 pose catalog claims item ownership")
	_assert(not bool(report.get("owns_network_state", true)), "S3 pose catalog claims network ownership")
	_assert(not bool(report.get("owns_gameplay_transform", true)), "S3 pose catalog claims gameplay transform ownership")

	_finish()


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("FPE R2 S3 hand pose catalog: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("FPE R2 S3 hand pose catalog: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)
