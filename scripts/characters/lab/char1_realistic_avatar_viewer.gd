class_name Char1RealisticAvatarViewer
extends Node3D

# CHAR1 realistic avatar preview viewer.
# Integration check mode over the CHAR1 provider-driven avatar line:
# the real Quaternius Universal Base Character is the default presenter,
# with third-person (start mode) / first-person toggle.
# The local world body is temporarily hidden for first-person preview.
#
# Controls:
#   1 / 2 / 3 - character: Quaternius real / procedural standard / high visibility
#   C or V    - toggle FIRST_PERSON / THIRD_PERSON
#   I / W / R - semantic animation: idle / walk / run
#   mouse     - orbit (third-person), look (first-person), wheel = zoom

const Bootstrap = preload(
	"res://scripts/characters/runtime/production_avatar_bootstrap.gd"
)
const Host = preload(
	"res://scripts/characters/avatar/player_avatar_host.gd"
)
const Contract = preload(
	"res://scripts/characters/avatar/avatar_contract.gd"
)

const CHARACTER_IDS := {
	KEY_1: "character/quaternius/regular",
	KEY_2: "character/procedural/standard",
	KEY_3: "character/procedural/high_visibility",
}
const SEMANTIC_SPEED_MPS := {
	"idle": 0.0,
	"walk": 2.0,
	"run": 6.0,
}
const THIRD_PERSON_DISTANCE := 4.2
const THIRD_PERSON_MIN_DISTANCE := 1.6
const THIRD_PERSON_MAX_DISTANCE := 8.0
const ORBIT_TARGET_HEIGHT := 1.15
const FIRST_PERSON_NEAR := 0.05
const FIRST_PERSON_FORWARD_OFFSET := 0.06
const HUD_INTERVAL_SECONDS := 0.2

var view_mode := "THIRD_PERSON"
var semantic := "idle"
var facing_yaw := 0.0
var orbit_yaw := PI
var orbit_pitch := -0.22
var orbit_distance := THIRD_PERSON_DISTANCE

var _host
var _third_person_camera: Camera3D
var _first_person_camera: Camera3D
var _hud_label: Label
var _hud_timer := 0.0
var _eye_height_m := 1.62
var _state_revision := 0
var _orbiting := false


func _ready() -> void:
	_build_stage()
	var runtime: Dictionary = Bootstrap.create_runtime()
	if not bool(runtime.get("success", false)):
		_hud_text(
			"CHAR1 VIEWER: BOOTSTRAP FAILED\n"
			+ String(runtime.get("error_code", ""))
		)
		push_error("CHAR1 viewer bootstrap failed")
		return
	var details: Dictionary = runtime.get("details", {})
	_host = Host.new()
	_host.name = "PlayerAvatarHost"
	add_child(_host)
	var configured: Dictionary = _host.setup(
		details.get("catalog"),
		details.get("providers"),
		"character/quaternius/regular",
		true
	)
	if not bool(configured.get("success", false)):
		_hud_text(
			"CHAR1 VIEWER: AVATAR SETUP FAILED\n"
			+ String(configured.get("error_code", ""))
		)
		push_error("CHAR1 viewer avatar setup failed")
		return
	_refresh_eye_height()
	_apply_view_mode()
	_apply_semantic_motion()
	_update_hud(true)


func _process(delta: float) -> void:
	_hud_timer += delta
	if _hud_timer >= HUD_INTERVAL_SECONDS:
		_hud_timer = 0.0
		_update_hud(false)
	if _host == null:
		return
	if view_mode == "THIRD_PERSON":
		_update_third_person_camera()
	else:
		_update_first_person_camera(delta)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var key: int = (event as InputEventKey).keycode
		if key == KEY_C or key == KEY_V:
			toggle_view_mode()
		elif CHARACTER_IDS.has(key):
			switch_character(CHARACTER_IDS[key])
		elif key == KEY_I:
			set_semantic("idle")
		elif key == KEY_W:
			set_semantic("walk")
		elif key == KEY_R:
			set_semantic("run")
	elif event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_LEFT:
			_orbiting = button.pressed
		elif button.button_index == MOUSE_BUTTON_WHEEL_UP and button.pressed:
			orbit_distance = maxf(
				THIRD_PERSON_MIN_DISTANCE,
				orbit_distance - 0.4
			)
		elif button.button_index == MOUSE_BUTTON_WHEEL_DOWN and button.pressed:
			orbit_distance = minf(
				THIRD_PERSON_MAX_DISTANCE,
				orbit_distance + 0.4
			)
	elif event is InputEventMouseMotion and _orbiting:
		var motion := event as InputEventMouseMotion
		if view_mode == "THIRD_PERSON":
			orbit_yaw -= motion.relative.x * 0.008
			orbit_pitch = clampf(
				orbit_pitch - motion.relative.y * 0.006,
				-1.2,
				0.6
			)
		else:
			facing_yaw -= motion.relative.x * 0.008
			_apply_semantic_motion()


func toggle_view_mode() -> void:
	view_mode = "FIRST_PERSON" if view_mode == "THIRD_PERSON" else "THIRD_PERSON"
	_apply_view_mode()
	_update_hud(true)


func switch_character(character_id: String) -> void:
	if _host == null:
		return
	var result: Dictionary = _host.switch_avatar(character_id)
	if not bool(result.get("success", false)):
		push_error("CHAR1 viewer switch failed: " + String(result.get("error_code", "")))
		return
	_refresh_eye_height()
	_apply_view_mode()
	_apply_semantic_motion()
	_update_hud(true)


func set_semantic(next_semantic: String) -> void:
	semantic = next_semantic
	_apply_semantic_motion()
	_update_hud(true)


func get_asset_mode() -> String:
	if _host == null:
		return "UNINITIALIZED"
	var report: Dictionary = _host.create_report()
	var presenter: Dictionary = report.get("presenter", {})
	var engine: Dictionary = presenter.get("engine", {})
	return String(engine.get("asset_mode", presenter.get("asset_mode", "UNKNOWN")))


func get_current_engine_semantic() -> String:
	if _host == null:
		return ""
	var report: Dictionary = _host.create_report()
	return String(report.get("presenter", {}).get("engine", {}).get("current_semantic", ""))


func create_report() -> Dictionary:
	var report: Dictionary = {}
	var character_id := ""
	var provider_id := ""
	if _host != null:
		report = _host.create_report()
		character_id = String(report.get("active_character_id", ""))
		provider_id = String(report.get("presenter", {}).get("provider_id", ""))
	return {
		"schema": "planet_simulator.char1_realistic_avatar_viewer.v1",
		"character_id": character_id,
		"provider_id": provider_id,
		"asset_mode": get_asset_mode(),
		"view_mode": view_mode,
		"semantic": semantic,
		"engine_semantic": get_current_engine_semantic(),
		"first_person_mode": bool(report.get("first_person_mode", false)),
		"local_body_visible": bool(_host.visible) if _host != null else false,
	}


func _build_stage() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.10, 0.14, 0.19)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.55, 0.6, 0.66)
	environment.ambient_light_energy = 1.1
	var world_environment := WorldEnvironment.new()
	world_environment.name = "WorldEnvironment"
	world_environment.environment = environment
	add_child(world_environment)

	var light := DirectionalLight3D.new()
	light.name = "DirectionalLight"
	light.rotation_degrees = Vector3(-48.0, 25.0, 0.0)
	light.light_energy = 1.2
	add_child(light)

	var floor_mesh := PlaneMesh.new()
	floor_mesh.size = Vector2(60.0, 60.0)
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color(0.22, 0.26, 0.3)
	floor_material.roughness = 0.9
	floor_mesh.material = floor_material
	var floor := MeshInstance3D.new()
	floor.name = "Floor"
	floor.mesh = floor_mesh
	add_child(floor)

	_third_person_camera = Camera3D.new()
	_third_person_camera.name = "ThirdPersonCamera"
	_third_person_camera.fov = 60.0
	add_child(_third_person_camera)

	_first_person_camera = Camera3D.new()
	_first_person_camera.name = "FirstPersonCamera"
	_first_person_camera.fov = 75.0
	_first_person_camera.near = FIRST_PERSON_NEAR
	add_child(_first_person_camera)

	var canvas := CanvasLayer.new()
	canvas.name = "HUD"
	add_child(canvas)
	_hud_label = Label.new()
	_hud_label.name = "HudLabel"
	_hud_label.position = Vector2(16.0, 12.0)
	_hud_label.add_theme_font_size_override("font_size", 16)
	canvas.add_child(_hud_label)


func _refresh_eye_height() -> void:
	if _host == null:
		return
	var definition: Dictionary = _host.get_active_definition()
	_eye_height_m = float(definition.get("eye_height_m", 1.62))


func _apply_view_mode() -> void:
	if _host == null:
		return
	var first_person := view_mode == "FIRST_PERSON"
	_host.set_first_person_mode(first_person)
	# Temporary preview-only first-person policy: hide the entire local avatar,
	# not just its head. The host/presenter keeps processing locomotion and
	# action animation while hidden; third-person restores visibility.
	# The camera and HUD are siblings, so they remain visible and independent.
	_host.visible = not first_person
	_first_person_camera.current = first_person
	_third_person_camera.current = not first_person
	if not first_person:
		_update_third_person_camera()


func _apply_semantic_motion() -> void:
	if _host == null:
		return
	_state_revision += 1
	var speed := float(SEMANTIC_SPEED_MPS.get(semantic, 0.0))
	var motion := {
		"schema": Contract.MOTION_SCHEMA,
		"velocity": {
			"x": sin(facing_yaw) * speed,
			"y": 0.0,
			"z": cos(facing_yaw) * speed,
		},
		"grounded": true,
		"facing_yaw": facing_yaw,
		"state_revision": _state_revision,
	}
	var result: Dictionary = _host.apply_motion_state(motion)
	if not bool(result.get("success", false)):
		push_error("CHAR1 viewer motion rejected: " + String(result.get("error_code", "")))


func _update_third_person_camera() -> void:
	if _third_person_camera == null:
		return
	var target := Vector3(0.0, ORBIT_TARGET_HEIGHT, 0.0)
	var horizontal := Vector3(
		cos(orbit_pitch) * sin(orbit_yaw),
		0.0,
		cos(orbit_pitch) * cos(orbit_yaw)
	)
	var position := target - horizontal * orbit_distance
	position.y = target.y - sin(orbit_pitch) * orbit_distance
	_third_person_camera.global_position = position
	_third_person_camera.look_at(target)


func _update_first_person_camera(_delta: float) -> void:
	if _first_person_camera == null:
		return
	# Stable eye-height camera: independent node, never a child of the
	# animated head bone. The local body is hidden in this preview while
	# first-person camera placement is being refined.
	var forward := Vector3(sin(facing_yaw), 0.0, cos(facing_yaw))
	_first_person_camera.global_position = (
		Vector3(0.0, _eye_height_m, 0.0) + forward * FIRST_PERSON_FORWARD_OFFSET
	)
	_first_person_camera.look_at(
		_first_person_camera.global_position + forward
	)


func _update_hud(force: bool) -> void:
	if _hud_label == null:
		return
	var report: Dictionary = create_report()
	var asset_mode := String(report.get("asset_mode", "UNKNOWN"))
	var lines: Array[String] = [
		"CHAR1 REALISTIC AVATAR PREVIEW",
		"character_id: " + String(report.get("character_id", "")),
		"provider_id:  " + String(report.get("provider_id", "")),
		"asset_mode:   " + asset_mode,
		"view_mode:    " + view_mode,
		"local_body:   " + ("VISIBLE" if bool(report.get("local_body_visible", false)) else "HIDDEN (first-person preview)"),
		"semantic:     " + semantic + " (engine: " + String(report.get("engine_semantic", "")) + ")",
		"",
		"[1] Quaternius real   [2] Procedural standard   [3] High visibility",
		"[C]/[V] toggle view   [I]dle [W]alk [R]un   mouse: orbit / look / wheel zoom",
	]
	if asset_mode == "FALLBACK":
		lines.append("")
		lines.append("!! FALLBACK: real Quaternius assets NOT loaded - NOT READY")
	_hud_text("\n".join(lines))


func _hud_text(text: String) -> void:
	if _hud_label != null:
		_hud_label.text = text
