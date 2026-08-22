extends Node3D

## ECO.EVO4 — Animated evolution plot demo (PRESENTATION-SIDE RESEARCH DEMO).
## A small 18 x 18 m plot fills with 12 seeded seedlings drawn from the
## ACCEPTED E4.B6 manifest species and visibly evolves over 8 generations of
## rising herbivory pressure, using the sealed EVO4.T0 payoff constants and
## the declared v0 defense-proxy derivation. Thorn density is bound to each
## individual's CURRENT defense value; browsed foliage uses the E4.T3
## browse_pressure presentation parameter. Pure presentation layer:
## zero chain-hash impact, no PH/CAL core edits, no population truth claims.
## Determinism: every stochastic choice is a sha256-text _unit() draw keyed by
## (BASE_SEED | individual_seed | generation | label), like the bridge module.

const Presentation = preload("res://scripts/research/ecology/evo4_bridge_presentation_v1.gd")

const MANIFEST_PATH := "res://validation/ecology/evo4_b6_region_manifest.v1.json"
const SCREENSHOT_PATH := "res://artifacts/evo4_evolution_plot.png"
const BASE_SEED := "eco-evo4-evolution-plot-v1"

const GENERATIONS := 8
const FRAMES_PER_GENERATION := 72 # ~1.2 s per generation at 60 fps
const HOLD_FRAMES := 30

const PLOT_HALF := 9.0 # plot is 18 x 18 m
const SPAWN_LIMIT := 8.4 # keep stems inside the plot border
const INITIAL_POPULATION := 12
const POPULATION_CAP := 40
const ADULT_AGE := 3.0 # generations until full size

# Sealed EVO4.T0 payoff constants (presentation-side copy only).
const DEFENSE_COST := 0.35
const HERBIVORY_GAIN := 0.85
const MUTATION_SPREAD := 0.12 # offspring defense mutation is U(-0.06, +0.06)

const BUILD_QUEUE_BUDGET := 4 # rich-subject builds/rebuilds allowed per frame
const MAX_BUILD_FAILURES := 3

const ORBIT_RADIUS := 11.5
const ORBIT_HEIGHT := 5.6
const ORBIT_SPEED := 0.14 # rad/s, slow orbital drift

var _plants: Array[Dictionary] = []
var _dying: Array[Dictionary] = []
var _build_queue: Array[Dictionary] = []
var _species_ids: Array[String] = []
var _species_data: Dictionary = {}
var _camera: Camera3D
var _hud_label: Label
var _orbit_angle := 0.9
var _generation_index := 0
var _pressure := 0.15
var _peak_population := 0
var _build_failures := 0
var _defense_history: Array[float] = []
var _done := false


func _ready() -> void:
	var manifest = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH))
	if typeof(manifest) != TYPE_DICTIONARY:
		_fail("missing manifest")
		return
	var traits_all: Dictionary = (manifest as Dictionary).get("species_traits", {})
	if traits_all.is_empty():
		_fail("manifest has no species_traits")
		return
	for gid in traits_all.keys():
		_species_ids.append(String(gid))
	_species_ids.sort()
	_prepare_species(traits_all)
	_build_environment()
	_build_hud()
	_spawn_initial_population()
	_run()


# ---- deterministic hash units (same pattern as the presentation module) --------

static func _unit(seed_text: String) -> float:
	var digest: String = seed_text.sha256_text()
	return float(digest.substr(0, 12).hex_to_int()) / 281474976710656.0


static func _hash01(a: int, b: int, key: String) -> float:
	return _unit("%d|%d|%s" % [a, b, key])


# ---- species preparation --------------------------------------------------------

func _prepare_species(traits_all: Dictionary) -> void:
	for gid in _species_ids:
		var species: Dictionary = traits_all[gid]
		var traits: Dictionary = (species["development_traits"] as Dictionary).duplicate(true)
		traits["branching_depth"] = int(traits["branching_depth"]) # JSON numbers parse as float
		var apical := clampf(float(traits["apical_dominance"]), 0.0, 1.0)
		var height := maxf(float(traits["max_height_m"]), 0.5)
		_species_data[gid] = {
			"traits": traits,
			"water": float(species["water_preference"]),
			"shade": float(species["shade_tolerance"]),
			"dormancy": float(species["dormancy_fraction"]),
			"defense": _defense_proxy(apical),
			"vigor": clampf(height / 40.0 + 0.3, 0.3, 1.0),
			"base_scale": clampf(2.0 / height, 0.40, 1.15),
		}


func _defense_proxy(apical_dominance: float) -> float:
	# Declared v0 defense proxy, same derivation as the sealed EVO4.T0 probe
	# with root_depth_proxy fixed at its 0.5 default (T0's optional genome-hash
	# jitter term is omitted here so the demo value is purely trait-derived):
	#   defense_proxy = clamp(0.55 * apical_dominance + 0.45 * root_depth_proxy(0.5), 0.05, 0.95)
	#                 = clamp(0.55 * apical_dominance + 0.225, 0.05, 0.95)
	return clampf(0.55 * apical_dominance + 0.225, 0.05, 0.95)


func _survival_chance(defense: float, pressure: float) -> float:
	# T0 payoff rule, survival form: the undefended herbivore loss is
	#   HERBIVORY_GAIN * P * (1 - defense_proxy)
	# so survival chance = 1 - HERBIVORY_GAIN * P * (1 - defense_proxy),
	# clamped to [0, 1]. Higher defense => strictly higher survival.
	var loss := HERBIVORY_GAIN * pressure * (1.0 - defense)
	return clampf(1.0 - loss, 0.0, 1.0)


func _payoff(plant: Dictionary, pressure: float) -> float:
	# T0 defended payoff rule (sealed constants, presentation-side copy):
	#   payoff = vigor - DEFENSE_COST * defense - HERBIVORY_GAIN * P * (1 - defense)
	var vigor := clampf(float(_species_data[String(plant["gid"])]["vigor"]), 0.3, 1.0)
	var defense := float(plant["defense"])
	return vigor - DEFENSE_COST * defense - HERBIVORY_GAIN * pressure * (1.0 - defense)


# ---- population -----------------------------------------------------------------

func _spawn_initial_population() -> void:
	var count := _species_ids.size()
	for i in range(INITIAL_POPULATION):
		var pick := int(_unit("%s|init-species|%d" % [BASE_SEED, i]) * float(count)) % count
		var gid := String(_species_ids[pick])
		var ux := _unit("%s|init-x|%d" % [BASE_SEED, i])
		var uz := _unit("%s|init-z|%d" % [BASE_SEED, i])
		var pos := Vector2((ux * 2.0 - 1.0) * SPAWN_LIMIT, (uz * 2.0 - 1.0) * SPAWN_LIMIT)
		var seed_value := int(_unit("%s|init-seed|%d" % [BASE_SEED, i]) * 2000000011.0)
		var plant := _make_plant(gid, seed_value, float(_species_data[gid]["defense"]), pos, 0.0)
		_plants.append(plant)
		_build_queue.append({"plant": plant})


func _make_plant(gid: String, seed_value: int, defense: float, pos: Vector2, age: float) -> Dictionary:
	var data: Dictionary = _species_data[gid]
	var root := Node3D.new()
	root.position = Vector3(pos.x, 0.0, pos.y)
	root.scale = Vector3.ONE * 0.05
	add_child(root)
	return {
		"gid": gid,
		"traits": data["traits"],
		"water": data["water"],
		"shade": data["shade"],
		"dormancy": data["dormancy"],
		"seed": seed_value,
		"defense": defense,
		"pos": pos,
		"age": age,
		"base_scale": data["base_scale"],
		"alive": true,
		"browsed": false,
		"built_browsed": false,
		"browse_bp": 0.0,
		"has_visual": false,
		"root": root,
	}


func _make_offspring(parent: Dictionary, g: int, k: int) -> Dictionary:
	var parent_seed := int(parent["seed"])
	var child_seed := int(_unit("%s|offspring|%d|%d|%d" % [BASE_SEED, parent_seed, g, k]) * 2000000011.0)
	# Seeded mutation: defense_proxy += U(-0.06, +0.06), clamped to [0.05, 0.95].
	var mutation := (_hash01(parent_seed, g, "mutation/%d" % k) - 0.5) * MUTATION_SPREAD
	var defense := clampf(float(parent["defense"]) + mutation, 0.05, 0.95)
	var ang := TAU * _hash01(parent_seed, g, "spread-dir/%d" % k)
	var dist := 0.5 + 1.3 * _hash01(parent_seed, g, "spread-dist/%d" % k)
	var parent_pos: Vector2 = parent["pos"]
	var child_pos := Vector2(
		clampf(parent_pos.x + cos(ang) * dist, -SPAWN_LIMIT, SPAWN_LIMIT),
		clampf(parent_pos.y + sin(ang) * dist, -SPAWN_LIMIT, SPAWN_LIMIT))
	return _make_plant(String(parent["gid"]), child_seed, defense, child_pos, 0.0)


func _step_generation(g: int) -> bool:
	var pressure := 0.15 + 0.09 * float(g) # rising herbivory pressure P_g
	_pressure = pressure
	var survivors: Array[Dictionary] = []
	var births: Array[Dictionary] = []
	var born := 0
	var died := 0
	for plant in _plants:
		var p: Dictionary = plant
		p["browsed"] = false
		var defense := float(p["defense"])
		var survival := _survival_chance(defense, pressure)
		var roll := _hash01(int(p["seed"]), g, "herbivory")
		if roll >= survival:
			p["alive"] = false
			_dying.append(p)
			died += 1
			continue
		# Survivor; decide whether this individual was visibly chewed this
		# generation (low-defense plants are bitten far more often).
		p["age"] = float(p["age"]) + 1.0
		var bite := _hash01(int(p["seed"]), g, "bite")
		if bite < clampf((1.0 - defense) * 0.9, 0.05, 0.9):
			p["browsed"] = true
			p["browse_bp"] = clampf((1.0 - defense) * 0.8, 0.15, 0.7)
		survivors.append(p)
		# Every survivor spawns 1-2 nearby offspring.
		var child_count := 1
		if _hash01(int(p["seed"]), g, "fecundity") < 0.65:
			child_count = 2
		for k in range(child_count):
			births.append(_make_offspring(p, g, k))
			born += 1
	# Queue visual refreshes for adults whose browsed state changed.
	for plant in survivors:
		var p: Dictionary = plant
		if bool(p["browsed"]) != bool(p["built_browsed"]):
			_build_queue.append({"plant": p})
	_plants = survivors
	for child in births:
		_plants.append(child)
		_build_queue.append({"plant": child})
	# Population cap: cull the weakest T0 payoff first.
	if _plants.size() > POPULATION_CAP:
		var order := _plants.duplicate()
		order.sort_custom(func(a, b): return _payoff(a, pressure) < _payoff(b, pressure))
		var excess := _plants.size() - POPULATION_CAP
		for i in range(excess):
			var culled: Dictionary = order[i]
			culled["alive"] = false
			_dying.append(culled)
			_plants.erase(culled)
			died += 1
	if _plants.is_empty():
		_fail("population extinct at generation %d" % g)
		return false
	_peak_population = maxi(_peak_population, _plants.size())
	var mean_defense := _live_mean_defense()
	_defense_history.append(mean_defense)
	print("ECO.EVO4.EVOLUTION-PLOT gen=%d pressure=%.2f population=%d mean_defense=%.3f born=%d died=%d" % [
		g, pressure, _plants.size(), mean_defense, born, died])
	return true


func _live_mean_defense() -> float:
	if _plants.is_empty():
		return 0.0
	var total := 0.0
	for plant in _plants:
		total += float(plant["defense"])
	return total / float(_plants.size())


func _run() -> void:
	for g in range(GENERATIONS):
		_generation_index = g
		if not _step_generation(g):
			return
		for f in range(FRAMES_PER_GENERATION):
			await get_tree().process_frame
	for f in range(HOLD_FRAMES):
		await get_tree().process_frame
	await _capture()


# ---- per-frame animation ---------------------------------------------------------

func _process(delta: float) -> void:
	if _camera != null:
		_orbit_angle += delta * ORBIT_SPEED
		_camera.position = Vector3(cos(_orbit_angle) * ORBIT_RADIUS, ORBIT_HEIGHT, sin(_orbit_angle) * ORBIT_RADIUS)
		_camera.look_at(Vector3(0.0, 1.4, 0.0), Vector3.UP)
	_drain_build_queue()
	_animate(delta)
	if _hud_label != null:
		_hud_label.text = "ECO.EVO4 EVOLUTION PLOT — PRESENTATION-SIDE RESEARCH DEMO\nGeneration %d/%d    Herbivory pressure %d%%    Mean defense %.3f    Population %d" % [
			mini(_generation_index + 1, GENERATIONS), GENERATIONS,
			int(round(_pressure * 100.0)), _live_mean_defense(), _plants.size()]


func _drain_build_queue() -> void:
	var budget := BUILD_QUEUE_BUDGET
	while budget > 0 and not _build_queue.is_empty():
		var entry: Dictionary = _build_queue.pop_front()
		_build_visual(entry["plant"])
		budget -= 1


func _build_visual(plant: Dictionary) -> void:
	var root: Node3D = plant["root"]
	if not is_instance_valid(root):
		return
	for child in root.get_children():
		child.queue_free()
	# thorn_density tracks the CURRENT individual defense value; browsed plants
	# rebuild with the T3 browse_pressure parameter (leaf/flower loss + tint).
	var want_browsed := bool(plant["browsed"])
	var browse_param := 0.0
	if want_browsed:
		browse_param = float(plant["browse_bp"])
	var built := Presentation.build_rich_subject(
		plant["traits"], int(plant["seed"]), float(plant["water"]),
		float(plant["shade"]), float(plant["dormancy"]), 1.5,
		float(plant["defense"]), browse_param)
	if built.is_empty():
		_build_failures += 1
		return
	var branch := MeshInstance3D.new()
	branch.mesh = built["branch_mesh"]
	root.add_child(branch)
	_add_multimesh(root, built["leaf_mesh"], built["leaf_transforms"], built["leaf_colors"], true)
	var flower_colors: Array[Color] = []
	for f in range((built["flower_transforms"] as Array).size()):
		flower_colors.append(built["flower_color"])
	_add_multimesh(root, built["flower_mesh"], built["flower_transforms"], flower_colors, true)
	var thorns: Array = built["thorn_transforms"]
	if thorns.size() > 0:
		var thorn_colors: Array[Color] = []
		for t in range(thorns.size()):
			thorn_colors.append(built["thorn_color"])
		_add_multimesh(root, built["thorn_mesh"], thorns, thorn_colors, false)
	plant["built_browsed"] = want_browsed
	plant["has_visual"] = true


func _animate(delta: float) -> void:
	var blend := clampf(delta * 4.0, 0.0, 1.0)
	for plant in _plants:
		var p: Dictionary = plant
		var root: Node3D = p["root"]
		if not is_instance_valid(root):
			continue
		# Seedlings start at 0.25 scale and grow toward the adult 1.0 scale;
		# changes are applied incrementally each frame for organic motion.
		var age_factor := clampf(float(p["age"]) / ADULT_AGE, 0.0, 1.0)
		var target := float(p["base_scale"]) * lerpf(0.25, 1.0, age_factor)
		var current := root.scale.x
		root.scale = Vector3.ONE * lerpf(current, target, blend)
	for plant in _dying:
		var p: Dictionary = plant
		var root: Node3D = p["root"]
		if not is_instance_valid(root):
			continue
		root.scale = root.scale * (1.0 - clampf(delta * 3.5, 0.0, 0.9))
		if root.scale.x < 0.02:
			root.visible = false
	var keep: Array[Dictionary] = []
	for plant in _dying:
		var root: Node3D = plant["root"]
		if is_instance_valid(root) and root.visible:
			keep.append(plant)
	_dying = keep


# ---- scene construction -----------------------------------------------------------

func _build_environment() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-34.0, 26.0, 0.0)
	sun.light_color = Color(1.0, 0.90, 0.74) # warm light
	sun.light_energy = 1.4
	sun.shadow_enabled = true
	add_child(sun)
	var world_env := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.36, 0.50, 0.70)
	sky_mat.sky_horizon_color = Color(0.88, 0.80, 0.66)
	sky_mat.ground_horizon_color = sky_mat.sky_horizon_color
	sky_mat.ground_bottom_color = Color(0.20, 0.18, 0.15)
	var sky_res := Sky.new()
	sky_res.sky_material = sky_mat
	env.sky = sky_res
	env.fog_enabled = true
	env.fog_density = 0.006
	env.fog_light_color = Color(0.85, 0.78, 0.66)
	world_env.environment = env
	add_child(world_env)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(140.0, 140.0)
	ground.mesh = plane
	var ground_material := StandardMaterial3D.new()
	ground_material.albedo_color = Color(0.13, 0.11, 0.09)
	ground.material_override = ground_material
	add_child(ground)
	var plot := MeshInstance3D.new()
	var plot_plane := PlaneMesh.new()
	plot_plane.size = Vector2(PLOT_HALF * 2.0, PLOT_HALF * 2.0)
	plot.mesh = plot_plane
	plot.position = Vector3(0.0, 0.01, 0.0)
	var plot_material := StandardMaterial3D.new()
	plot_material.albedo_color = Color(0.22, 0.17, 0.12)
	plot.material_override = plot_material
	add_child(plot)
	_camera = Camera3D.new()
	_camera.current = true
	_camera.fov = 58.0
	add_child(_camera)
	_camera.position = Vector3(cos(_orbit_angle) * ORBIT_RADIUS, ORBIT_HEIGHT, sin(_orbit_angle) * ORBIT_RADIUS)
	_camera.look_at(Vector3(0.0, 1.4, 0.0), Vector3.UP)
	var title := Label3D.new()
	title.text = "ANIMATED EVOLUTION DEMO — PRESENTATION-SIDE RESEARCH ONLY"
	title.font_size = 52
	title.pixel_size = 0.012
	title.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	title.modulate = Color(1.0, 0.97, 0.86)
	title.outline_size = 12
	title.position = Vector3(0.0, 6.8, 0.0)
	add_child(title)


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_hud_label = Label.new()
	_hud_label.position = Vector2(22.0, 16.0)
	_hud_label.add_theme_font_size_override("font_size", 21)
	_hud_label.add_theme_color_override("font_color", Color(1.0, 0.98, 0.92))
	_hud_label.add_theme_color_override("font_outline_color", Color(0.05, 0.04, 0.03, 0.9))
	_hud_label.add_theme_constant_override("outline_size", 6)
	layer.add_child(_hud_label)


func _add_multimesh(parent: Node3D, mesh: Mesh, transforms: Array, colors: Array[Color], double_sided: bool) -> void:
	if transforms.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = transforms.size()
	for i in range(transforms.size()):
		mm.set_instance_transform(i, transforms[i])
		mm.set_instance_color(i, colors[i % colors.size()])
	var holder := MultiMeshInstance3D.new()
	holder.multimesh = mm
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	if double_sided:
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
	holder.material_override = material
	parent.add_child(holder)


# ---- capture / verdict -------------------------------------------------------------

func _capture() -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	if image == null or image.is_empty():
		_fail("viewport image unavailable")
		return
	var absolute := ProjectSettings.globalize_path(SCREENSHOT_PATH)
	DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	var err := image.save_png(absolute)
	if err != OK:
		_fail("png save failed (err=%d)" % err)
		return
	# Light in-engine pixel sanity gate; the deep pixel audit runs externally.
	# Dark-green foliage pixels: green channel dominant, mid-dark value.
	var unique := {}
	var green := 0
	var samples := 0
	for x in range(0, image.get_width(), 10):
		for y in range(0, image.get_height(), 10):
			var c := image.get_pixel(x, y)
			unique[c.g8 * 65536 + c.r8 * 256 + c.b8] = true
			samples += 1
			var brightest: int = maxi(c.r8, maxi(c.g8, c.b8))
			if c.g8 > c.r8 + 4 and c.g8 > c.b8 + 4 and c.g8 >= 25 and brightest <= 190:
				green += 1
	var green_fraction := float(green) / maxf(float(samples), 1.0)
	print("pixel_check unique_sampled=%d green_fraction=%.4f build_failures=%d" % [
		unique.size(), green_fraction, _build_failures])
	if unique.size() < 300 or green_fraction < 0.001:
		_fail("pixel gate (unique_sampled=%d green_fraction=%.3f)" % [unique.size(), green_fraction])
		return
	if _build_failures > MAX_BUILD_FAILURES:
		_fail("too many rich-subject build failures (%d)" % _build_failures)
		return
	if _defense_history.size() != GENERATIONS:
		_fail("expected %d generations, completed %d" % [GENERATIONS, _defense_history.size()])
		return
	var trajectory := PackedStringArray()
	for value in _defense_history:
		trajectory.append("%.3f" % value)
	print("ECO.EVO4.EVOLUTION-PLOT mean_defense_trajectory=%s" % " -> ".join(trajectory))
	print("ECO.EVO4.EVOLUTION-PLOT DEMO: PASS generations=%d peak_population=%d final_mean_defense=%.3f" % [
		GENERATIONS, _peak_population, _defense_history[_defense_history.size() - 1]])
	print("screenshot=artifacts/evo4_evolution_plot.png")
	_done = true
	get_tree().quit(0)


func _fail(reason: String) -> void:
	if _done:
		return
	_done = true
	print("ECO.EVO4.EVOLUTION-PLOT DEMO: FAIL %s" % reason)
	get_tree().quit(1)
