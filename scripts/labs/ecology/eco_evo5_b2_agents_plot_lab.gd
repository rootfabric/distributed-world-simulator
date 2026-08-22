extends Node3D

## ECO.EVO5/B2 - agents on the plot (visual contract demo).
## Two herbivore capsules walk to the lowest-toxicity plants and bite them;
## bitten plants darken and sink. Presentation-side research demo only.

const TICKS := 600

var _agents: Array[Dictionary] = []
var _plants: Array[Dictionary] = []
var _bites := 0
var _hud: Label

func _ready() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35.0, 25.0, 0.0)
	sun.light_energy = 1.4
	add_child(sun)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.55, 0.62, 0.72)
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(24.0, 24.0)
	ground.mesh = plane
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.20, 0.16, 0.12)
	ground.material_override = gm
	add_child(ground)
	for i in range(9):
		var pos := Vector3(float((i % 3) * 5 - 5), 0.0, float((i / 3) * 5 - 5))
		_plants.append(_make_plant(i, pos))
	for j in range(2):
		var agent := Node3D.new()
		var body := MeshInstance3D.new()
		var cap := CapsuleMesh.new()
		cap.radius = 0.22
		cap.height = 0.9
		body.mesh = cap
		body.position.y = 0.45
		var bm := StandardMaterial3D.new()
		bm.albedo_color = Color(0.85, 0.55, 0.30)
		body.material_override = bm
		agent.add_child(body)
		add_child(agent)
		agent.position = Vector3(-9.0 + 6.0 * j, 0.0, 8.0)
		_agents.append({"node": agent, "target": -1})
	_hud = Label.new()
	_hud.position = Vector2(16, 12)
	add_child(_hud)
	_run()

func _make_plant(index: int, pos: Vector3) -> Dictionary:
	var root := Node3D.new()
	root.position = pos
	add_child(root)
	var stem := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.06
	cyl.bottom_radius = 0.10
	cyl.height = 1.1
	stem.mesh = cyl
	stem.position.y = 0.55
	root.add_child(stem)
	var crown := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = 0.55
	sph.height = 1.1
	crown.mesh = sph
	crown.position.y = 1.45
	var cm := StandardMaterial3D.new()
	var toxicity := 0.7 - 0.06 * index
	cm.albedo_color = Color(0.15 + 0.5 * (1.0 - toxicity), 0.45, 0.12).lerp(Color(0.6, 0.2, 0.2), toxicity * 0.5)
	crown.material_override = cm
	root.add_child(crown)
	return {"id": index, "root": root, "crown_material": cm, "toxicity": toxicity,
		"nutrient": 0.3 + 0.08 * index, "browse": 0.0, "base_color": cm.albedo_color}

func _run() -> void:
	for tick in range(TICKS):
		for a in _agents:
			if int(a["target"]) < 0:
				var best := -1
				var best_w := -999.0
				for p in _plants:
					var w: float = p["nutrient"] - 0.8 * p["toxicity"]
					if w > best_w:
						best_w = w
						best = p["id"]
				a["target"] = best
			var target: Dictionary = _plants[int(a["target"])]
			var node: Node3D = a["node"]
			var delta: Vector3 = target["root"].position - node.position
			delta.y = 0.0
			if delta.length() > 0.9:
				node.position += delta.normalized() * 0.09
			else:
				_bites += 1
				target["browse"] += 1.0
				var k: float = clampf(target["browse"] / 6.0, 0.0, 1.0)
				target["crown_material"].albedo_color = target["base_color"].lerp(Color(0.25, 0.18, 0.10), k)
				target["root"].scale = Vector3.ONE * (1.0 - 0.25 * k)
				a["target"] = -1
		if tick % 60 == 0:
			_hud.text = "tick %d/%d  bites=%d" % [tick, TICKS, _bites]
			await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	image.save_png(ProjectSettings.globalize_path("res://artifacts/evo5_b2_agents_plot.png"))
	print("ECO.EVO5.B2 AGENTS-PLOT DEMO: PASS ticks=%d bites=%d" % [TICKS, _bites])
	get_tree().quit(0)
