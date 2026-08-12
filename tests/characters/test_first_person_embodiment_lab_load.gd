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
			String(lab.get_script().resource_path) == "res://scripts/characters/lab/quaternius_first_person_embodiment_fix16.gd",
			"FPE graphical root is not the R2 S8 Fix16 skinned hand composition"
		)
		_assert(lab.has_method("_apply_hotbar_presentation_for_index"), "FPE immediate hotbar presentation port is missing")
		_assert(lab.has_method("_select_hotbar_nonblocking"), "FPE local hotbar selection port is missing")
		_assert(lab.has_method("_poll_hotbar_authority"), "FPE hotbar authority compatibility port is missing")
		_assert(lab.has_method("get_held_item_presentation_report"), "FPE R2 held-item presentation report is missing")
		_assert(lab.has_method("_on_held_item_presentation_changed"), "FPE R2 shared held-state consumer is missing")
		_assert(lab.has_method("get_r2_s2_catalog_report"), "FPE R2 S2 catalog report is missing")
		_assert(lab.has_method("get_r2_s3_hand_pose_report"), "FPE R2 S3 hand pose report is missing")
		_assert(lab.has_method("get_r2_s4_two_hand_report"), "FPE R2 S4 two-hand report is missing")
		_assert(lab.has_method("get_sandbox_collision_isolation_report"), "FPE sandbox owner-collision isolation report is missing")
		_assert(lab.has_method("get_r2_s5_secondary_world_hand_report"), "FPE R2 S5 secondary world-hand report is missing")
		_assert(lab.has_method("get_r2_s6_hand_visual_provider_report"), "FPE R2 S6 hand visual provider report is missing")
		_assert(lab.has_method("get_r2_s7_resource_hand_visual_report"), "FPE R2 S7 resource hand visual report is missing")
		_assert(lab.has_method("_find_requested_hand_visual_scene_path"), "FPE R2 S7 resource scene argument resolver is missing")
		_assert(lab.has_method("get_r2_s8_skinned_hand_visual_report"), "FPE R2 S8 skinned hand visual report is missing")
		_assert(lab.has_method("_find_requested_skinned_hand_scene_path"), "FPE R2 S8 skinned scene argument resolver is missing")
		_assert(lab.item_viewmodel_catalog != null, "FPE R2 S2 item viewmodel catalog is missing")
		_assert(lab.held_item_grip_catalog != null, "FPE R2 S2/S4 grip profile catalog is missing")
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
