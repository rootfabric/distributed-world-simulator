extends SceneTree

const LabScene = preload("res://scenes/labs/character/quaternius_first_person_embodiment_lab.tscn")

var failures: Array[String] = []
var assertions := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_assert(LabScene != null, "FPE graphical lab PackedScene failed to preload")
	var lab: Node = LabScene.instantiate() if LabScene != null else null
	_assert(lab != null, "FPE graphical lab failed to instantiate")
	if lab != null:
		_assert(lab.has_method("get_first_person_embodiment_debug_snapshot"), "FPE graphical lab script did not bind")
		_assert(
			String(lab.get_script().resource_path) == "res://scripts/characters/lab/quaternius_fpe_optimized_lab.gd",
			"FPE graphical root is not the Fix6 optimized projection-aware lab"
		)
		var base_lab: Node = lab.get_node_or_null("CH9_6BaseLab")
		_assert(base_lab != null, "FPE graphical lab does not compose a CH9.6 host")
		if base_lab != null:
			_assert(
				String(base_lab.get_script().resource_path) == "res://scripts/characters/lab/quaternius_fpe_ch9_6_host.gd",
				"FPE graphical lab child is not the CH9.6 research host"
			)
			_assert(base_lab.has_method("get_fpe_status_performance_report"), "FPE CH9.6 host performance port is missing")
			_assert(base_lab.has_method("get_network_debug_snapshot"), "FPE CH9.6 host no longer inherits accepted network lab behavior")
			_assert(base_lab.has_signal("fpe_canonical_projection_applied"), "FPE CH9.6 host projection classification signal is missing")
			var perf: Dictionary = base_lab.get_fpe_status_performance_report()
			_assert(not bool(perf.get("automatic_heavy_status", true)), "FPE host still enables automatic heavy inherited HUD")
		lab.free()
	_finish()


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("FirstPersonEmbodiment graphical scene load: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("FirstPersonEmbodiment graphical scene load: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)
