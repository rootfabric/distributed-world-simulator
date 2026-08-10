extends SceneTree

const LabScene = preload("res://scenes/labs/character/quaternius_layered_equipment_lab.tscn")
const UPPER_PRESENTATION_ID := "wearable.layer.upper.peasant"
const LOWER_PRESENTATION_ID := "wearable.layer.lower.peasant"
const FEET_PRESENTATION_ID := "wearable.layer.feet.peasant"

const EXPECTED_UPPER := 0.032
const EXPECTED_LOWER := 0.038
const EXPECTED_FEET := 0.036
const EXPECTED_SCALE := 1.0

var failures: Array[String] = []
var assertions := 0

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var lab = LabScene.instantiate()
	root.add_child(lab)
	await process_frame
	await physics_frame

	_assert(bool(lab.layered_setup_result.get("success", false)), "CH8C CLI tuning lab setup failed: %s" % JSON.stringify(lab.layered_setup_result))
	_assert(bool(lab.cli_inflation_override_active), "CH8C CLI tuning override was not detected")
	_assert(is_equal_approx(float(lab.upper_inflation_max_m), EXPECTED_UPPER), "CH8C CLI upper value mismatch")
	_assert(is_equal_approx(float(lab.lower_inflation_max_m), EXPECTED_LOWER), "CH8C CLI lower value mismatch")
	_assert(is_equal_approx(float(lab.feet_inflation_max_m), EXPECTED_FEET), "CH8C CLI feet value mismatch")
	_assert(is_equal_approx(float(lab.inflation_scale), EXPECTED_SCALE), "CH8C CLI scale mismatch")
	_assert(_profile_max(lab, UPPER_PRESENTATION_ID) >= EXPECTED_UPPER - 0.000001, "CH8C CLI upper profile was not scaled")
	_assert(_profile_max(lab, LOWER_PRESENTATION_ID) >= EXPECTED_LOWER - 0.000001, "CH8C CLI lower profile was not scaled")
	_assert(_profile_max(lab, FEET_PRESENTATION_ID) >= EXPECTED_FEET - 0.000001, "CH8C CLI feet profile was not scaled")
	_assert(String(lab.status_label.text).contains("| CLI"), "CH8C CLI status marker missing")
	_assert(String(lab.status_label.text).contains("upper 0.032 m | lower 0.038 m | feet 0.036 m"), "CH8C CLI status values missing")

	lab.queue_free()
	_finish()

func _profile_max(lab, presentation_id: String) -> float:
	if not lab.inflation_reports.has(presentation_id):
		return 0.0
	return float((lab.inflation_reports[presentation_id] as Dictionary).get("profile_max_offset_m", 0.0))

func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)

func _finish() -> void:
	if failures.is_empty():
		print("CH8C CLI inflation override: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("CH8C CLI inflation override: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)
