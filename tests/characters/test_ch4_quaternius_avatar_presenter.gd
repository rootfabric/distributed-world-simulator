extends SceneTree

const AvatarPresenter = preload("res://scripts/characters/presentation/quaternius_avatar_presenter.gd")

var failures: Array[String] = []
var assertions := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var host := Node3D.new()
	root.add_child(host)
	var presenter = AvatarPresenter.new()
	host.add_child(presenter)
	var setup_result: Dictionary = presenter.setup({
		"force_fallback": true,
		"run_threshold_mps": 5.0,
	})
	_assert(bool(setup_result.get("success", false)), "Fallback presenter setup failed")
	await process_frame
	var report: Dictionary = presenter.create_report()
	_assert(String(report.get("schema", "")) == "planet_simulator.quaternius_avatar_presenter.v2", "Unexpected presenter schema")
	_assert(String(report.get("asset_mode", "")) == "FALLBACK", "Fallback mode was not selected")
	_assert(not bool(report.get("root_motion_applied", true)), "Presenter may apply root motion")
	_assert(_count_nodes_of_type(presenter, CharacterBody3D) == 0, "Presentation layer owns CharacterBody3D")
	_assert(_count_nodes_of_type(presenter, CollisionShape3D) == 0, "Presentation layer owns collision")

	presenter.apply_motion(Vector3.ZERO, Vector3.UP, Vector3.FORWARD)
	_assert(String(presenter.create_report().get("current_semantic", "")) == "idle", "Zero velocity must resolve to idle")
	presenter.apply_motion(Vector3(0.0, 0.0, 3.0), Vector3.UP, Vector3.FORWARD)
	_assert(String(presenter.create_report().get("current_semantic", "")) == "walk", "Walking velocity must resolve to walk")
	presenter.apply_motion(Vector3(0.0, 0.0, 7.0), Vector3.UP, Vector3.FORWARD)
	_assert(String(presenter.create_report().get("current_semantic", "")) == "run", "Running velocity must resolve to run")
	presenter.apply_motion(Vector3(0.0, 9.0, 0.0), Vector3.UP, Vector3.FORWARD)
	_assert(String(presenter.create_report().get("current_semantic", "")) == "idle", "Radial velocity without state must not trigger locomotion")
	presenter.apply_motion(Vector3(0.0, 6.0, 0.0), Vector3.UP, Vector3.FORWARD, {"grounded": false})
	_assert(String(presenter.create_report().get("current_semantic", "")) == "jump", "Airborne state must resolve to jump")
	presenter.apply_motion(Vector3.ZERO, Vector3.UP, Vector3.FORWARD, {"grounded": true, "crouching": true})
	_assert(String(presenter.create_report().get("current_semantic", "")) == "crouch_idle", "Stationary crouch must resolve to crouch idle")
	presenter.apply_motion(Vector3(0.0, 0.0, 1.8), Vector3.UP, Vector3.FORWARD, {"grounded": true, "crouching": true})
	_assert(String(presenter.create_report().get("current_semantic", "")) == "crouch_walk", "Moving crouch must resolve to crouch walk")

	var source := FileAccess.get_file_as_string("res://scripts/characters/presentation/quaternius_avatar_presenter.gd")
	_assert(not source.contains("move_and_slide"), "Presentation layer may not move gameplay body")
	_assert(not source.contains("multiplayer"), "Presentation layer gained network dependency")
	_assert(not source.contains("Input."), "Presentation layer gained input dependency")
	_assert(source.contains("root_motion_applied = false"), "Root motion safety fence is missing")

	var synthetic_host := Node3D.new()
	root.add_child(synthetic_host)
	var synthetic_presenter = AvatarPresenter.new()
	synthetic_host.add_child(synthetic_presenter)
	var synthetic_setup: Dictionary = synthetic_presenter.setup({
		"model_path": "res://tests/fixtures/ch5_synthetic_quaternius_base.tscn",
		"animation_path": "res://tests/fixtures/ch5_synthetic_quaternius_animation.tscn",
		"run_threshold_mps": 5.0,
	})
	_assert(bool(synthetic_setup.get("success", false)), "Synthetic presenter setup failed")
	await process_frame
	var synthetic_report: Dictionary = synthetic_presenter.create_report()
	_assert(String(synthetic_report.get("asset_mode", "")) == "QUATERNIUS_RETARGET", "Synthetic presenter did not enter retarget mode")
	_assert(bool(synthetic_report.get("supports_jump", false)), "Synthetic Jump clip was not resolved")
	_assert(bool(synthetic_report.get("supports_crouch", false)), "Synthetic crouch clips were not resolved")
	var capabilities: Dictionary = synthetic_report.get("animation_capabilities", {})
	_assert(bool(capabilities.get("jump_start", false)), "Jump_Start capability missing")
	_assert(bool(capabilities.get("jump_land", false)), "Jump_Land capability missing")

	synthetic_presenter.apply_motion(Vector3(0.0, 4.0, 0.0), Vector3.UP, Vector3.FORWARD, {"grounded": false})
	await process_frame
	_assert(String(synthetic_presenter.create_report().get("current_animation", "")) == "Jump", "Airborne semantic did not select exact Jump clip")
	synthetic_presenter.apply_motion(Vector3.ZERO, Vector3.UP, Vector3.FORWARD, {"grounded": true, "crouching": true})
	await process_frame
	_assert(String(synthetic_presenter.create_report().get("current_animation", "")) == "Crouch_Idle", "Crouch idle did not select Crouch_Idle")
	synthetic_presenter.apply_motion(Vector3(0.0, 0.0, 1.8), Vector3.UP, Vector3.FORWARD, {"grounded": true, "crouching": true})
	await process_frame
	_assert(String(synthetic_presenter.create_report().get("current_animation", "")) == "Crouch_Fwd", "Crouch movement did not select Crouch_Fwd")
	_assert(not bool(synthetic_presenter.create_report().get("root_motion_applied", true)), "Jump/crouch presentation changed root-motion authority")
	synthetic_host.queue_free()

	var require_external := OS.get_environment("PLANET_SIMULATOR_REQUIRE_QUATERNIUS_ASSETS") == "1"
	if require_external:
		var external_host := Node3D.new()
		root.add_child(external_host)
		var external_presenter = AvatarPresenter.new()
		external_host.add_child(external_presenter)
		var external_setup: Dictionary = external_presenter.setup({"run_threshold_mps": 5.0})
		_assert(bool(external_setup.get("success", false)), "External Quaternius setup failed")
		await process_frame
		var external_report: Dictionary = external_presenter.create_report()
		_assert(
			String(external_report.get("asset_mode", "")) in ["QUATERNIUS_RETARGET", "QUATERNIUS_EMBEDDED"],
			"Quaternius model did not reach animated mode: %s" % JSON.stringify(external_report)
		)
		_assert(bool(external_report.get("target_skeleton", false)), "Quaternius target skeleton missing: %s" % JSON.stringify(external_report))
		_assert(bool(external_report.get("animation_ready", false)), "Idle/Walk/Run animations were not resolved: %s" % JSON.stringify(external_report))
		_assert(bool(external_report.get("supports_jump", false)), "Real UAL1 Jump animation was not resolved: %s" % JSON.stringify(external_report))
		_assert(bool(external_report.get("supports_crouch", false)), "Real UAL1 Crouch_Idle/Crouch_Fwd animations were not resolved: %s" % JSON.stringify(external_report))
		var external_capabilities: Dictionary = external_report.get("animation_capabilities", {})
		_assert(bool(external_capabilities.get("jump_start", false)), "Real UAL1 Jump_Start animation was not resolved")
		_assert(bool(external_capabilities.get("jump_land", false)), "Real UAL1 Jump_Land animation was not resolved")
		_assert(not bool(external_report.get("root_motion_applied", true)), "External Quaternius path applies root motion")
		external_host.queue_free()

	host.queue_free()
	_finish()


func _count_nodes_of_type(node: Node, type_value: Variant) -> int:
	var count := 0
	for child in node.get_children():
		if is_instance_of(child, type_value):
			count += 1
		count += _count_nodes_of_type(child, type_value)
	return count


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("CH4/CH6 Quaternius avatar presenter: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("CH4/CH6 Quaternius avatar presenter: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)