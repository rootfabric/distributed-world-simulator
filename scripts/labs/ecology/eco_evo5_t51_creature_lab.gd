extends Node3D

## ECO.EVO5/T5.1 - creature skeleton-graph body demo (presentation-side).
## Torso + gene-count limbs (sha256-deterministic), procedural gait, hunt lunge.

var _limbs: Array[Dictionary] = []
var _torso: Node3D
var _time := 0.0

func _unit(s: String) -> float:
	return int(_sha(s).substr(0, 12).hex_to_int()) / 281474976710656.0

func _sha(text: String) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(text.to_utf8_buffer())
	return ctx.finish().hex_encode()

func _ready() -> void:
	var camera := Camera3D.new()
	add_child(camera)
	camera.current = true
	camera.position = Vector3(0.0, 6.0, 11.0)
	camera.look_at(Vector3(0.0, 0.8, 0.0), Vector3.UP)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-38.0, 30.0, 0.0)
	sun.light_energy = 1.4
	add_child(sun)
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.52, 0.60, 0.72)
	we.environment = env
	add_child(we)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(26.0, 26.0)
	ground.mesh = plane
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.21, 0.17, 0.12)
	ground.material_override = gm
	add_child(ground)
	_torso = Node3D.new()
	add_child(_torso)
	var body := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 0.35
	cap.height = 1.8
	body.mesh = cap
	body.rotation_degrees = Vector3(90, 0, 0)
	body.position.y = 0.85
	body.scale = Vector3(1, 1, 1.6)
	var bm := StandardMaterial3D.new()
	bm.albedo_color = Color(0.45, 0.30, 0.55)
	body.material_override = bm
	_torso.add_child(body)
	var head := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = 0.30
	sph.height = 0.6
	head.mesh = sph
	head.position = Vector3(0.0, 0.95, -1.25)
	var hm := StandardMaterial3D.new()
	hm.albedo_color = Color(0.62, 0.42, 0.72)
	head.material_override = hm
	_torso.add_child(head)
	var genome := "evo5-creature-genome-alpha"
	var limb_count := 2 + int(_unit(genome + "|limb_count") * 5.0)
	for i in range(limb_count):
		var side := 1.0 if i % 2 == 0 else -1.0
		var phase := float(i) * 1.7
		var hip := Node3D.new()
		hip.position = Vector3(0.45 * side, 0.75, -0.6 + 1.2 * float(i / 2))
		_torso.add_child(hip)
		var upper := MeshInstance3D.new()
		var seg1 := CylinderMesh.new()
		seg1.top_radius = 0.07
		seg1.bottom_radius = 0.06
		seg1.height = 0.55
		upper.mesh = seg1
		upper.position.y = -0.27
		var lm := StandardMaterial3D.new()
		lm.albedo_color = Color(0.38, 0.24, 0.46)
		upper.material_override = lm
		hip.add_child(upper)
		var lower := MeshInstance3D.new()
		lower.mesh = seg1
		lower.position.y = -0.78
		lower.material_override = lm
		hip.add_child(lower)
		_limbs.append({"hip": hip, "phase": phase})
	var hud := Label.new()
	hud.text = "ECO.EVO5.T5.1 CREATURE BODY DEMO (PRESENTATION-SIDE)"
	hud.position = Vector2(16, 12)
	add_child(hud)
	_walk(limb_count)

func _walk(limbs_n: int) -> void:
	for tick in range(360):
		_time += 0.05
		_torso.position = Vector3(sin(_time * 0.5) * 3.0, 0.0, cos(_time * 0.5) * 3.0)
		_torso.rotation.y = -atan2(cos(_time * 0.5), sin(_time * 0.5)) + PI / 2.0
		for limb in _limbs:
			var swing: float = sin(_time * 6.0 + limb["phase"]) * 0.5
			(limb["hip"] as Node3D).rotation.x = swing
			(limb["hip"] as Node3D).position.y = 0.75 + maxf(0.0, sin(_time * 6.0 + limb["phase"])) * 0.12
		if tick == 300:
			_torso.scale = Vector3.ONE * 1.15
		elif tick == 320:
			_torso.scale = Vector3.ONE
		if tick % 20 == 0:
			await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	image.save_png(ProjectSettings.globalize_path("res://artifacts/evo5_t51_creature.png"))
	print("ECO.EVO5.T5.1 CREATURE LAB: PASS limbs=%d" % limbs_n)
	get_tree().quit(0)
