extends SceneTree

# CHAR1 graphical acceptance: real renderer, cross-provider hot-swap,
# visible meshes, semantic motion handoff and first-person mode.
# Does not instantiate a canonical gameplay / network authority.
const Bootstrap = preload("res://scripts/characters/runtime/production_avatar_bootstrap.gd")
const Host = preload("res://scripts/characters/avatar/player_avatar_host.gd")
const Contract = preload("res://scripts/characters/avatar/avatar_contract.gd")

var assertions := 0
var failures: Array[String] = []

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var runtime: Dictionary = Bootstrap.create_runtime()
	_check(bool(runtime.get("success", false)), "bootstrap succeeds")
	if not bool(runtime.get("success", false)):
		_finish(null)
		return
	var stage := Node3D.new()
	stage.name = "CHAR1GraphicalStage"
	get_root().add_child(stage)
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.08, 0.12, 0.16)
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	stage.add_child(world_environment)
	var camera := Camera3D.new()
	stage.add_child(camera)
	camera.position = Vector3(0.0, 1.65, 5.5)
	camera.look_at(Vector3(0.0, 1.05, 0.0))
	camera.current = true
	var light := DirectionalLight3D.new()
	stage.add_child(light)
	light.rotation_degrees = Vector3(-50.0, 20.0, 0.0)
	var host := Host.new()
	stage.add_child(host)
	var details: Dictionary = runtime.get("details", {})
	var configured: Dictionary = host.setup(
		details.get("catalog"),
		details.get("providers"),
		"character/quaternius/regular",
		false
	)
	_check(bool(configured.get("success", false)), "Quaternius-compatible provider instantiates")
	if not bool(configured.get("success", false)):
		_finish(stage)
		return
	var motion := {
		"schema": Contract.MOTION_SCHEMA,
		"velocity": {"x": 2.0, "y": 0.0, "z": 0.0},
		"grounded": true,
		"facing_yaw": 0.35,
		"state_revision": 1,
	}
	_check(bool(host.apply_motion_state(motion).get("success", false)), "first provider receives motion")
	for i in range(6):
		await process_frame
	var report: Dictionary = host.create_report()
	_check(
		String(report.get("presenter", {}).get("provider_id", "")) == "avatar/quaternius",
		"Quaternius provider selected"
	)
	_check(_avatar_is_rendered(), "Quaternius or fallback visibly renders")
	_capture("quaternius-or-fallback")
	var swap: Dictionary = host.switch_avatar("character/procedural/standard")
	_check(bool(swap.get("success", false)), "cross-provider hot-swap succeeds")
	for i in range(6):
		await process_frame
	report = host.create_report()
	_check(
		String(report.get("presenter", {}).get("provider_id", "")) == "avatar/procedural_humanoid",
		"procedural provider selected"
	)
	_check(
		bool(report.get("presenter", {}).get("has_motion_state", false)),
		"semantic motion state is replayed to replacement provider"
	)
	_check(_avatar_is_rendered(), "procedural provider visibly renders")
	_capture("procedural")
	host.set_first_person_mode(true)
	for i in range(2):
		await process_frame
	_check(
		bool(host.create_report().get("first_person_mode", false)),
		"first-person mode switches through provider interface"
	)
	_finish(stage)

func _avatar_is_rendered() -> bool:
	var image: Image = get_root().get_texture().get_image()
	if image == null or image.is_empty():
		return false
	var background := image.get_pixel(4, 4)
	var visible_pixels := 0
	for y in range(image.get_height() / 4, image.get_height() * 3 / 4, 6):
		for x in range(image.get_width() / 3, image.get_width() * 2 / 3, 6):
			var color: Color = image.get_pixel(x, y)
			var distance := (
				absf(color.r - background.r)
				+ absf(color.g - background.g)
				+ absf(color.b - background.b)
			)
			if distance > 0.24:
				visible_pixels += 1
	return visible_pixels >= 12

func _capture(label: String) -> void:
	var output_dir := ProjectSettings.globalize_path("res://artifacts/char1-graphical")
	DirAccess.make_dir_recursive_absolute(output_dir)
	var screenshot: Image = get_root().get_texture().get_image()
	screenshot.save_png(output_dir.path_join(label + ".png"))

func _check(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)

func _finish(stage: Node3D) -> void:
	if stage != null:
		stage.queue_free()
	if failures.is_empty():
		print("CHAR1 GRAPHICAL: PASS (%d assertions, 0 failures)" % assertions)
		quit(0)
	else:
		for failure in failures:
			push_error("[CHAR1 graphical] " + failure)
		print("CHAR1 GRAPHICAL: FAIL (%d assertions, %d failures)" % [assertions, failures.size()])
		quit(1)
