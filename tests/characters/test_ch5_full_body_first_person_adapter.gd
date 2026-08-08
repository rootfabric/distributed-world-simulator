extends SceneTree

const AvatarPresenter = preload("res://scripts/characters/presentation/quaternius_avatar_presenter.gd")
const FirstPersonAdapter = preload("res://scripts/characters/presentation/full_body_first_person_adapter.gd")

var failures: Array[String] = []
var assertions := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var host := Node3D.new()
	root.add_child(host)

	var fallback_presenter = AvatarPresenter.new()
	host.add_child(fallback_presenter)
	fallback_presenter.setup({"force_fallback": true})
	var fallback_adapter = FirstPersonAdapter.new()
	host.add_child(fallback_adapter)
	var bind_result: Dictionary = fallback_adapter.bind_avatar(fallback_presenter)
	_assert(bool(bind_result.get("success", false)), "Fallback adapter bind failed")
	var report: Dictionary = fallback_adapter.create_report()
	_assert(String(report.get("schema", "")) == "planet_simulator.full_body_first_person_adapter.v1", "Unexpected adapter schema")
	_assert(String(report.get("mask_mode", "")) == "FALLBACK_VISIBILITY", "Fallback head mask was not resolved")
	_assert(bool(report.get("mask_ready", false)), "Fallback mask is not ready")

	fallback_adapter.set_first_person_enabled(true)
	await process_frame
	report = fallback_adapter.create_report()
	_assert(bool(report.get("first_person_enabled", false)), "First-person mode did not enable")
	_assert(bool(report.get("mask_applied", false)), "Fallback mask was not applied")
	var fallback_head := _find_descendant_named(fallback_presenter, "Head") as Node3D
	_assert(fallback_head != null and not fallback_head.visible, "Fallback head stayed visible in first person")

	fallback_adapter.set_first_person_enabled(false)
	await process_frame
	_assert(fallback_head != null and fallback_head.visible, "Fallback head did not restore in third person")

	var source := FileAccess.get_file_as_string("res://scripts/characters/presentation/full_body_first_person_adapter.gd")
	_assert(not source.contains("Input."), "First-person adapter gained input ownership")
	_assert(not source.contains("move_and_slide"), "First-person adapter gained movement ownership")
	_assert(not source.contains("Camera3D.new"), "First-person adapter gained camera ownership")

	var synthetic_presenter = AvatarPresenter.new()
	host.add_child(synthetic_presenter)
	var synthetic_setup: Dictionary = synthetic_presenter.setup({
		"model_path": "res://tests/fixtures/ch5_synthetic_quaternius_base.tscn",
		"animation_path": "res://tests/fixtures/ch5_synthetic_quaternius_animation.tscn",
		"run_threshold_mps": 5.0,
	})
	_assert(bool(synthetic_setup.get("success", false)), "Synthetic external presenter setup failed")
	_assert(String(synthetic_presenter.create_report().get("asset_mode", "")) == "QUATERNIUS_RETARGET", "Synthetic presenter did not enter retarget mode")

	var synthetic_adapter = FirstPersonAdapter.new()
	host.add_child(synthetic_adapter)
	synthetic_adapter.bind_avatar(synthetic_presenter)
	report = synthetic_adapter.create_report()
	_assert(String(report.get("mask_mode", "")) == "BONE_SCALE", "Synthetic external head did not resolve to bone-scale mask")
	_assert(String(report.get("head_bone_name", "")).to_lower() == "head", "Synthetic head bone was not resolved")

	synthetic_adapter.set_first_person_enabled(true)
	await process_frame
	var target_skeleton := _find_model_skeleton(synthetic_presenter)
	var head_index := target_skeleton.find_bone("head") if target_skeleton != null else -1
	_assert(target_skeleton != null and head_index >= 0, "Synthetic target head bone missing")
	var masked_scale := target_skeleton.get_bone_pose_scale(head_index) if head_index >= 0 else Vector3.ONE
	_assert(masked_scale.length() < 0.01, "Synthetic head bone was not collapsed in first person")

	synthetic_presenter.apply_motion(Vector3(0.0, 0.0, 7.0), Vector3.UP, Vector3.FORWARD)
	await process_frame
	masked_scale = target_skeleton.get_bone_pose_scale(head_index) if head_index >= 0 else Vector3.ONE
	_assert(masked_scale.length() < 0.01, "Animation pose restored the hidden head")
	_assert(not bool(synthetic_presenter.create_report().get("root_motion_applied", true)), "First-person masking changed root-motion authority")

	synthetic_adapter.set_first_person_enabled(false)
	await process_frame
	var restored_scale := target_skeleton.get_bone_pose_scale(head_index) if head_index >= 0 else Vector3.ZERO
	_assert(restored_scale.is_equal_approx(Vector3.ONE), "Synthetic head scale did not restore in third person")

	host.queue_free()
	_finish()


func _find_model_skeleton(presenter: Node) -> Skeleton3D:
	var model_root := _find_descendant_named(presenter, "QuaterniusModel")
	return _find_first_skeleton(model_root) if model_root != null else null


func _find_first_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node as Skeleton3D
	for child in node.get_children():
		var found := _find_first_skeleton(child)
		if found != null:
			return found
	return null


func _find_descendant_named(node: Node, target_name: String) -> Node:
	if String(node.name) == target_name:
		return node
	for child in node.get_children():
		var found := _find_descendant_named(child, target_name)
		if found != null:
			return found
	return null


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("CH5 full-body first-person adapter: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("CH5 full-body first-person adapter: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)
