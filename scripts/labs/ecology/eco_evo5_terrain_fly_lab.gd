extends Node3D

## ECO.EVO5 - terrain flyover spectator: watch zone evolution live.
## Click to capture mouse; WASD/QE fly, Esc releases. Replays gene trajectories
## as growing thorn spikes. Set EVO5_FLY_AUTOCAP=1 for headless verify+quit.

const PALETTE := {
	"plain": Color(0.43, 0.55, 0.31), "hill_slopes": Color(0.59, 0.51, 0.27),
	"ravine_bottom": Color(0.24, 0.35, 0.43), "riverside": Color(0.27, 0.47, 0.63),
	"iron_ridge": Color(0.67, 0.39, 0.24), "snow_corner": Color(0.86, 0.86, 0.90),
}

var _cam: Camera3D
var _yaw := -0.7
var _pitch := -0.5
var _spikes: Array[Dictionary] = []
var _trajectories: Dictionary = {}
var _tick := 0

func _ready() -> void:
	var evo = JSON.parse_string(FileAccess.get_file_as_string("res://validation/ecology/evo5_terrain_evolution.v1.json"))
	var terrain = JSON.parse_string(FileAccess.get_file_as_string("res://validation/ecology/evo5_terrain_demo.v1.json"))
	if typeof(evo) != TYPE_DICTIONARY or typeof(terrain) != TYPE_DICTIONARY:
		print("ECO.EVO5.TERRAIN-FLY: FAIL (missing artifacts)")
		get_tree().quit(1)
		return
	for zone in (evo as Dictionary)["zones"].keys():
		_trajectories[zone] = (evo["zones"][zone] as Dictionary)["defense_trajectory"]
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45.0, 40.0, 0.0)
	sun.light_energy = 1.3
	add_child(sun)
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.36, 0.52, 0.74)
	sky_mat.sky_horizon_color = Color(0.83, 0.76, 0.64)
	sky_mat.ground_bottom_color = Color(0.25, 0.23, 0.20)
	env.sky = Sky.new()
	(env.sky as Sky).sky_material = sky_mat
	env.fog_enabled = true
	env.fog_density = 0.006
	we.environment = env
	add_child(we)
	var cells: Array = (terrain as Dictionary)["cells"]
	var zone_centers: Dictionary = {}
	for c in cells:
		var cell: Dictionary = c
		var tile := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(1.9, 0.8, 1.9)
		tile.mesh = box
		tile.position = Vector3(float(cell["x"]) * 2.0, float(cell["height"]) * 1.6 - 0.6, float(cell["z"]) * 2.0)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = _shade(PALETTE[String(cell["zone"])], float(cell["height"]))
		tile.material_override = mat
		add_child(tile)
		var zone := String(cell["zone"])
		if not zone_centers.has(zone):
			zone_centers[zone] = []
		if (zone_centers[zone] as Array).size() < 3:
			(zone_centers[zone] as Array).append(tile.position + Vector3(0.0, 0.45, 0.0))
	for zone in zone_centers.keys():
		for spot in zone_centers[zone]:
			_make_plant(spot, String(zone))
	_cam = Camera3D.new()
	add_child(_cam)
	_cam.current = true
	_cam.position = Vector3(18.0, 14.0, 18.0)
	_apply_look()
	var hud := Label.new()
	hud.text = "FLY: click=capture mouse | WASD move QE up/down Esc=release | spikes grow = defense evolves"
	hud.position = Vector2(16, 12)
	add_child(hud)
	print("ECO.EVO5.TERRAIN-FLY: READY zones=%d plants=%d" % [_trajectories.size(), _spikes.size()])
	if OS.get_environment("EVO5_FLY_AUTOCAP") == "1":
		_autocap()

func _shade(base: Color, height: float) -> Color:
	return base.lightened(clampf((height - 1.0) * 0.12, -0.12, 0.18))

func _make_plant(pos: Vector3, zone: String) -> void:
	var root := Node3D.new()
	root.position = pos
	add_child(root)
	var stem := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.07
	cyl.bottom_radius = 0.13
	cyl.height = 1.2
	stem.mesh = cyl
	stem.position.y = 0.6
	root.add_child(stem)
	var crown := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = 0.5
	sph.height = 1.0
	crown.mesh = sph
	crown.position.y = 1.5
	var cm := StandardMaterial3D.new()
	cm.albedo_color = Color(0.30, 0.50, 0.20).lerp(Color(0.22, 0.34, 0.14), 0.4)
	crown.material_override = cm
	root.add_child(crown)
	for s in range(6):
		var spike := MeshInstance3D.new()
		var cone := CylinderMesh.new()
		cone.top_radius = 0.015
		cone.bottom_radius = 0.05
		cone.height = 0.5
		spike.mesh = cone
		var ang := TAU * float(s) / 6.0
		spike.position = Vector3(cos(ang) * 0.42, 1.62 + 0.12 * sin(float(s) * 2.1), sin(ang) * 0.42)
		spike.rotation.x = sin(ang) * 0.5
		spike.rotation.z = -cos(ang) * 0.5
		var sm := StandardMaterial3D.new()
		sm.albedo_color = Color(0.75, 0.70, 0.45)
		spike.material_override = sm
		root.add_child(spike)
		_spikes.append({"mesh": spike, "zone": zone, "base_y": spike.position.y})

func _process(delta: float) -> void:
	_tick += 1
	var speed := 6.0 * delta
	var forward := -_cam.transform.basis.z
	var right := _cam.transform.basis.x
	if Input.is_key_pressed(KEY_W):
		_cam.position += forward * speed
	if Input.is_key_pressed(KEY_S):
		_cam.position -= forward * speed
	if Input.is_key_pressed(KEY_A):
		_cam.position -= right * speed
	if Input.is_key_pressed(KEY_D):
		_cam.position += right * speed
	if Input.is_key_pressed(KEY_Q):
		_cam.position.y -= speed
	if Input.is_key_pressed(KEY_E):
		_cam.position.y += speed
	if Input.is_key_pressed(KEY_ESCAPE):
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	var first_traj: Array = _trajectories.values()[0]
	var gen_step: int = int((_tick / 60.0)) % (first_traj.size())
	for entry in _spikes:
		var traj: Array = _trajectories[String(entry["zone"])]
		var def: float = float(traj[gen_step])
		var spike: MeshInstance3D = entry["mesh"]
		spike.scale = Vector3.ONE * clampf(0.25 + def * 1.4, 0.25, 1.7)
		spike.position.y = float(entry["base_y"]) + 0.10 * def

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_yaw -= event.relative.x * 0.003
		_pitch = clampf(_pitch - event.relative.y * 0.003, -1.4, 1.2)
		_apply_look()

func _apply_look() -> void:
	_cam.rotation = Vector3(_pitch, _yaw, 0.0)

func _autocap() -> void:
	for i in range(90):
		await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	image.save_png(ProjectSettings.globalize_path("res://artifacts/evo5_terrain_fly.png"))
	print("ECO.EVO5.TERRAIN-FLY: AUTOCAP PASS screenshot=artifacts/evo5_terrain_fly.png")
	get_tree().quit(0)
