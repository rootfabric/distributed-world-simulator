extends SceneTree

const LabScene = preload("res://scenes/labs/character/quaternius_character_lab.tscn")

var failures: Array[String] = []
var assertions := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var lab = LabScene.instantiate()
	root.add_child(lab)
	await process_frame
	await physics_frame
	_assert(lab is Node3D, "Lab root is not Node3D")
	_assert(lab.player is CharacterBody3D, "Lab player body missing")
	_assert(lab.avatar != null, "Lab avatar presenter missing")
	_assert(lab.camera is Camera3D, "Lab camera missing")
	_assert(lab.player.get_child_count() >= 3, "Lab player composition is incomplete")
	var report: Dictionary = lab.avatar.create_report()
	_assert(String(report.get("schema", "")) == "planet_simulator.quaternius_avatar_presenter.v1", "Unexpected avatar report schema")
	_assert(not bool(report.get("root_motion_applied", true)), "Lab avatar enables root motion")
	var require_external := OS.get_environment("PLANET_SIMULATOR_REQUIRE_QUATERNIUS_ASSETS") == "1"
	if require_external:
		_assert(
			String(report.get("asset_mode", "")) in ["QUATERNIUS_RETARGET", "QUATERNIUS_EMBEDDED"],
			"Walkable lab fell back instead of using Quaternius: %s" % JSON.stringify(report)
		)
		_assert(
			bool(report.get("animation_ready", false)),
			"Walkable lab has no Idle/Walk/Run animation set: %s" % JSON.stringify(report)
		)
	lab.queue_free()
	_finish()


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("CH4 Quaternius character lab: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("CH4 Quaternius character lab: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)
