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
var _seeds: Array[Dictionary] = []
var _zone_ctx: Dictionary = {}
var _roots: Array[Dictionary] = []
var _rng_tick := 0
var _established_count := 0
var _cell_top := {}
var _cell_keys: Array = []
const RichPresentation = preload("res://scripts/research/ecology/evo4_bridge_presentation_v1.gd")
var _species: Dictionary = {}

func _establish(pos: Vector3, zone: String, hue_jitter: float) -> void:
	if _species.is_empty():
		var man = JSON.parse_string(FileAccess.get_file_as_string("res://validation/ecology/evo4_b6_region_manifest.v1.json"))
		for gid in ((man as Dictionary)["species_traits"] as Dictionary).keys():
			var sp: Dictionary = (man["species_traits"] as Dictionary)[gid]
			var t: Dictionary = (sp["development_traits"] as Dictionary).duplicate(true)
			t["branching_depth"] = int(t["branching_depth"])
			_species[gid] = {"traits": t, "wpref": float(sp["water_preference"]),
				"stol": float(sp["shade_tolerance"]), "dorm": float(sp["dormancy_fraction"]),
				"base": int(sp["variant_base_seed"])}
	var gids := _species.keys()
	var gid: String = gids[int(_unit("gid|%s|%f" % [zone, hue_jitter]) * float(gids.size()))]
	var sp: Dictionary = _species[gid]
	var seed_int := int(_unit("seedint|%s|%d" % [zone, _rng_tick]) * 900000.0) + 1000
	var built := RichPresentation.build_rich_subject(
		sp["traits"], seed_int + int(hue_jitter * 7919.0), sp["wpref"], sp["stol"], sp["dorm"], 1.4)
	if built.is_empty():
		print("ECO.EVO5.FLY: establish FAILED empty build gid=", gid)
		return
	_established_count += 1
	var holder := Node3D.new()
	holder.position = pos
	add_child(holder)
	var defense: float = clampf(float((_trajectories[zone] as Array).back()), 0.1, 1.0)
	var trunk_h := 1.2 + 1.4 * _unit("th|%d|%f" % [_rng_tick, hue_jitter])
	var limbs := 3 + int(_unit("lm|%d" % _rng_tick) * 4.0)
	var bark := StandardMaterial3D.new()
	bark.albedo_color = Color(0.36, 0.24, 0.14)
	var leaf_mat := StandardMaterial3D.new()
	leaf_mat.albedo_color = Color(0.28, 0.52, 0.20).lerp(Color(0.16, 0.30, 0.12), defense * 0.5)
	var stem := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.06
	cyl.bottom_radius = 0.13
	cyl.height = trunk_h
	stem.mesh = cyl
	stem.position.y = trunk_h * 0.5
	stem.material_override = bark
	holder.add_child(stem)
	for li in range(limbs):
		var ang := TAU * float(li) / float(limbs) + _unit("ba|%d|%d" % [_rng_tick, li]) * 0.8
		var tilt := 0.6 + 0.5 * _unit("bt|%d|%d" % [_rng_tick, li])
		var blen := (0.7 + 0.5 * _unit("bl|%d|%d" % [_rng_tick, li])) * (0.7 + 0.6 * defense)
		var joint := Node3D.new()
		joint.position = Vector3(0.0, trunk_h * (0.55 + 0.4 * float(li % 3) / 2.0), 0.0)
		joint.rotation = Vector3(0.0, -ang, tilt)
		holder.add_child(joint)
		var bone := MeshInstance3D.new()
		var bcyl := CylinderMesh.new()
		bcyl.top_radius = 0.03
		bcyl.bottom_radius = 0.05
		bcyl.height = blen
		bone.mesh = bcyl
		bone.position.y = blen * 0.5
		bone.material_override = bark
		joint.add_child(bone)
		var tip_y := blen
		var leaves := MeshInstance3D.new()
		var lsph := SphereMesh.new()
		lsph.radius = 0.28 + 0.22 * defense
		lsph.height = lsph.radius * 2.0
		leaves.mesh = lsph
		leaves.position.y = tip_y + lsph.radius * 0.6
		leaves.material_override = leaf_mat
		joint.add_child(leaves)
	return

func _sha(text: String) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(text.to_utf8_buffer())
	return ctx.finish().hex_encode()

func _unit(s: String) -> float:
	return float(int(_sha(s).substr(0, 12).hex_to_int())) / 281474976710656.0

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
	var zone_genes: Dictionary = {}
	for zone in (evo as Dictionary)["zones"].keys():
		zone_genes[zone] = ((evo["zones"][zone] as Dictionary)["final_genes"])
	var planted := 0
	for c in cells:
		var cell: Dictionary = c
		var zone := String(cell["zone"])
		if not _zone_ctx.has(zone):
			_zone_ctx[zone] = cell["context"]
		var tile := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(1.9, 3.0, 1.9)
		tile.mesh = box
		tile.position = Vector3(float(cell["x"]) * 2.0, float(cell["height"]) * 1.6 - 1.1, float(cell["z"]) * 2.0)
		_cell_top["%d|%d" % [int(cell["x"]), int(cell["z"])]] = float(cell["height"]) * 1.6 + 0.4
		_cell_keys.append("%d|%d" % [int(cell["x"]), int(cell["z"])])
		var mat := StandardMaterial3D.new()
		mat.albedo_color = _shade(PALETTE[zone], float(cell["height"]))
		tile.material_override = mat
		add_child(tile)
		var roll: float = _unit("plant|" + str(cell["x"]) + "|" + str(cell["z"]))
		if roll > 0.45 and planted < 170:
			planted += 1
			var jitter := Vector3((_unit("jx|%d|%d" % [cell["x"], cell["z"]]) - 0.5) * 1.2, 0.45, (_unit("jz|%d|%d" % [cell["x"], cell["z"]]) - 0.5) * 1.2)
			_make_plant(tile.position + jitter, zone, _unit("hue|%d|%d" % [cell["x"], cell["z"]]), zone_genes[zone])
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

func _make_plant(pos: Vector3, zone: String, hue_jitter: float = 0.5, genes: Dictionary = {}) -> void:
	var root := Node3D.new()
	root.position = pos
	var size_var := 0.75 + hue_jitter * 0.6
	root.scale = Vector3.ONE * size_var
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
	var base_green := Color(0.30, 0.50, 0.20).lerp(Color(0.22, 0.34, 0.14), 0.4)
	var hue_shift: float = (hue_jitter - 0.5) * 0.25
	cm.albedo_color = base_green.lerp(Color(0.45, 0.48, 0.18), clampf(hue_shift + 0.12, 0.0, 1.0))
	crown.material_override = cm
	root.add_child(crown)
	var spike_count := 4 + int(clampf(float(genes.get("defense_intensity", 0.3)) * 6.0, 0.0, 4.0))
	for s in range(spike_count):
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
		_spikes.append({"mesh": spike, "zone": zone, "base_y": 1.62 + 0.12 * sin(float(s) * 2.1), "root": root})

func _spawn_offspring() -> void:
	if _spikes.is_empty() or _spikes.size() > 240:
		return
	var parent: Dictionary = _spikes[int(_unit("spawn|%d" % _tick) * float(_spikes.size()))]
	var root: Node3D = parent["root"]
	var offset := Vector3((_unit("ox|%d" % _tick) - 0.5) * 2.2, 0.45, (_unit("oz|%d" % _tick) - 0.5) * 2.2)
	_make_plant(root.position + offset, String(parent["zone"]), _unit("oh|%d" % _tick), {})
	var young: Dictionary = _spikes[_spikes.size() - 1]
	(young["root"] as Node3D).scale = Vector3.ONE * 0.35

## Seed lifecycle: spawn drifting seed -> establishment check vs zone context
## (E3 semantics: score vs threshold) -> established plants grow with mutated
## genes; failed seeds shrink away. Iron-gated genes express only on ridge.
func _spawn_seed() -> void:
	var zones := _zone_ctx.keys()
	var zone: String = zones[int(_unit("seedzone|%d|%d" % [_tick, _rng_tick]) * float(zones.size()))]
	_rng_tick += 1
	var ctx: Dictionary = _zone_ctx[zone]
	var eff: Dictionary = ctx["effective_conditions"]
	var seed_node := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = 0.14
	sph.height = 0.28
	seed_node.mesh = sph
	var sm := StandardMaterial3D.new()
	sm.albedo_color = Color(0.85, 0.72, 0.40)
	seed_node.material_override = sm
	var cell_key: String = _cell_keys[int(_unit("cell|%d|%d" % [_tick, _rng_tick]) * float(_cell_keys.size()))]
	var parts := (cell_key as String).split("|")
	var drop_x := float(int(parts[0])) * 2.0 + (_unit("sx|%d" % _rng_tick) - 0.5) * 1.4
	var drop_z := float(int(parts[1])) * 2.0 + (_unit("sz|%d" % _rng_tick) - 0.5) * 1.4
	seed_node.position = Vector3(drop_x, 9.0, drop_z)
	add_child(seed_node)
	var score: float = 0.45 + float(eff.get("soil_moisture_ppm", 400000)) / 2e6 - float(eff.get("disturbance_pressure_ppm", 50000)) / 1e6 + 0.15 * _unit("sc|%d" % _rng_tick)
	_seeds.append({"node": seed_node, "zone": zone, "fall": 34, "cell": cell_key,
		"score": clampf(score, 0.15, 0.95)})

func _update_seeds() -> void:
	for i in range(_seeds.size() - 1, -1, -1):
		var s: Dictionary = _seeds[i]
		var node: MeshInstance3D = s["node"]
		if int(s["fall"]) > 0:
			s["fall"] = int(s["fall"]) - 1
			node.position.y -= 0.22
			continue
		var established := float(s["score"]) >= 0.55 and _roots.size() < 300
		if established:
			var pos := node.position
			node.queue_free()
			_seeds.remove_at(i)
			var ground_y: float = float(_cell_top.get(String(s["cell"]), 0.4))
			_establish(Vector3(pos.x, ground_y, pos.z), String(s["zone"]), _unit("esth|%d" % i))
		else:
			var fade: float = clampf(node.scale.x - 0.08, 0.05, 1.0)
			node.scale = Vector3.ONE * fade
			node.position.y -= 0.02
			if fade <= 0.06:
				node.queue_free()
				_seeds.remove_at(i)

func _cull_oldest() -> void:
	if _spikes.size() < 40:
		return
	var victim: Dictionary = _spikes[0]
	if is_instance_valid(victim["root"]):
		(victim["root"] as Node3D).queue_free()
	_spikes = _spikes.filter(func(e): return e["root"] != victim["root"])

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
	if _tick % 50 == 0:
		_spawn_seed()
		_spawn_seed()
	if _tick % 10 == 0:
		_update_seeds()
	for r in _roots:
		var rn: Node3D = r["node"]
		if is_instance_valid(rn) and rn.scale.x < float(r["target"]):
			rn.scale = rn.scale.lerp(Vector3.ONE * float(r["target"]), 0.01)
	if _roots.size() > 300 and _tick % 200 == 0:
		var victim: Dictionary = _spikes[0]
		if is_instance_valid(victim["root"]):
			(victim["root"] as Node3D).queue_free()
		_spikes = _spikes.filter(func(e): return e["root"] != victim["root"])

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
	_cam.position = Vector3(1.0, 30.0, 1.0)
	_pitch = -1.4
	_yaw = 0.0
	_apply_look()
	for i in range(700):
		await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	image.save_png(ProjectSettings.globalize_path("res://artifacts/evo5_terrain_fly.png"))
	print("ECO.EVO5.TERRAIN-FLY: AUTOCAP established=%d screenshot=artifacts/evo5_terrain_fly.png" % _established_count)
	get_tree().quit(0)
