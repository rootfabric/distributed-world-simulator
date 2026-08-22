extends Node3D

## ECO.EVO4/E4.T3 — Trophic defense visualization lab.
## 9 bridge species of the ACCEPTED E4.B6 manifest, side by side:
## LEFT column = BEFORE herbivory (thorn_density from the v0 defense proxy),
## RIGHT column = AFTER herbivory pressure (same thorns + deterministic
## browse loss and browsed-foliage tint). Labels in frame. Presentation
## layer only; zero chain-hash impact; PH5 core untouched.

const Presentation = preload("res://scripts/research/ecology/evo4_bridge_presentation_v1.gd")

const MANIFEST_PATH := "res://validation/ecology/evo4_b6_region_manifest.v1.json"
const SCREENSHOT_PATH := "res://artifacts/evo4_t3_trophic_defense.png"
const BROWSE_PRESSURE := 0.65
const ROWS_Z_START := -14.0
const ROWS_Z_STEP := 3.5
const COLUMN_X := 8.0

var _thorn_total := 0
var _leaf_before := 0
var _leaf_after := 0


func _ready() -> void:
	var manifest = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH))
	if typeof(manifest) != TYPE_DICTIONARY:
		print("ECO.EVO4/E4.T3 TROPHIC DEFENSE LAB: FAIL (missing manifest)")
		get_tree().quit(1)
		return
	var species_traits: Dictionary = (manifest as Dictionary)["species_traits"]
	var representatives := _representatives(manifest as Dictionary)
	if representatives.size() != 9:
		print("ECO.EVO4/E4.T3 TROPHIC DEFENSE LAB: FAIL (expected 9 species, got %d)" % representatives.size())
		get_tree().quit(1)
		return

	_build_environment()
	var row := 0
	for item in representatives:
		var gid := String(item["genome_id"])
		var species: Dictionary = species_traits[gid]
		var traits: Dictionary = (species["development_traits"] as Dictionary).duplicate(true)
		traits["branching_depth"] = int(traits["branching_depth"]) # JSON numbers are float
		var variant_seed := int(species["variant_base_seed"]) + int(item["variant_index"]) * 7919
		var defense := _defense_proxy(gid, traits)
		var base_args := [
			traits, variant_seed, float(species["water_preference"]),
			float(species["shade_tolerance"]), float(species["dormancy_fraction"]), 1.6,
		]
		var z := ROWS_Z_START + ROWS_Z_STEP * float(row)

		var before := Presentation.build_rich_subject(
			base_args[0], base_args[1], base_args[2], base_args[3], base_args[4], base_args[5],
			defense, 0.0)
		var after := Presentation.build_rich_subject(
			base_args[0], base_args[1], base_args[2], base_args[3], base_args[4], base_args[5],
			defense, BROWSE_PRESSURE)
		if before.is_empty() or after.is_empty():
			print("ECO.EVO4/E4.T3 TROPHIC DEFENSE LAB: FAIL (build failed for %s)" % gid)
			get_tree().quit(1)
			return
		_leaf_before += int(before["stats"]["leaf_count"])
		_leaf_after += int(after["stats"]["leaf_count"])
		_thorn_total += (before["stats"].get("thorn_count", 0) as int)

		var yaw := float(item["yaw_rad"])
		_place_specimen(before, Vector3(-COLUMN_X, 0.0, z), yaw)
		_place_specimen(after, Vector3(COLUMN_X, 0.0, z), yaw)
		var short_name := gid.substr(gid.find("/") + 1)
		var before_leaves := _leaf_count_of(before)
		var after_leaves := _leaf_count_of(after)
		_add_label("%s\ndefense %.2f" % [short_name, defense],
			Vector3(-COLUMN_X, float(before["stats"]["height_m"]) + 1.0, z))
		if before_leaves > 0:
			_add_label("-%d%% foliage" % int(round(100.0 * (1.0 - float(after_leaves) / float(before_leaves)))),
				Vector3(COLUMN_X, float(after["stats"]["height_m"]) + 1.0, z))
		row += 1

	_add_label("BEFORE HERBIVORY — thorns = v0 defense proxy", Vector3(-COLUMN_X, 10.5, ROWS_Z_START), 64)
	_add_label("AFTER HERBIVORY PRESSURE %.2f" % BROWSE_PRESSURE, Vector3(COLUMN_X, 10.5, ROWS_Z_START), 64)
	_add_label("ECO.EVO4/E4.T3 trophic defense — 9 bridge species", Vector3(0.0, 13.5, ROWS_Z_START), 56)

	await _capture_and_verify(representatives.size())


func _defense_proxy(gid: String, traits: Dictionary) -> float:
	# Declared v0 derivation, identical to the sealed EVO4.T0 formula
	# (root_depth_proxy default 0.5); presentation-side copy only.
	var apical := clampf(float(traits["apical_dominance"]), 0.0, 1.0)
	return clampf(0.55 * apical + 0.225 + 0.10 * (Presentation._unit(gid) - 0.5), 0.05, 0.95)


func _representatives(manifest: Dictionary) -> Array:
	var seen := {}
	var reps: Array = []
	for instance in manifest["instances"]:
		var inst: Dictionary = instance
		var gid := String(inst["genome_id"])
		if seen.has(gid):
			continue
		seen[gid] = true
		reps.append({
			"genome_id": gid,
			"variant_index": int(inst["variant_index"]),
			"yaw_rad": float(inst["yaw_rad"]),
		})
	reps.sort_custom(func(a, b): return String(a["genome_id"]) < String(b["genome_id"]))
	return reps


func _leaf_count_of(built: Dictionary) -> int:
	return int((built["stats"] as Dictionary)["leaf_count"])


func _place_specimen(built: Dictionary, origin: Vector3, yaw_rad: float) -> void:
	var root := Node3D.new()
	root.position = origin
	root.rotation.y = yaw_rad
	add_child(root)
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


func _add_label(text_value: String, pos: Vector3, font_size: int = 40) -> void:
	var label := Label3D.new()
	label.text = text_value
	label.font_size = font_size
	label.pixel_size = 0.012
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.modulate = Color(1, 1, 0.92)
	label.outline_size = 10
	label.position = pos
	add_child(label)


func _build_environment() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-34.0, 24.0, 0.0)
	sun.light_color = Color(1.0, 0.90, 0.74)
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
	plane.size = Vector2(80.0, 80.0)
	ground.mesh = plane
	var ground_material := StandardMaterial3D.new()
	ground_material.albedo_color = Color(0.17, 0.14, 0.11)
	ground.material_override = ground_material
	add_child(ground)
	var camera := Camera3D.new()
	camera.current = true
	add_child(camera)
	camera.position = Vector3(0.0, 9.0, 24.0)
	camera.look_at(Vector3(0.0, 2.5, ROWS_Z_START + ROWS_Z_STEP * 4.0), Vector3.UP)


func _capture_and_verify(species_count: int) -> void:
	for warmup in range(20):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var absolute := ProjectSettings.globalize_path(SCREENSHOT_PATH)
	DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	image.save_png(absolute)

	# Pixel gate: the frame must be non-degenerate and the two columns must
	# visibly differ (browse loss changes the right-hand silhouettes).
	var unique := {}
	var left_sum := 0.0
	var right_sum := 0.0
	var samples := 0
	for x in range(0, image.get_width(), 12):
		for y in range(0, image.get_height(), 12):
			var c := image.get_pixel(x, y)
			unique[c.get_luminance()] = true
			samples += 1
			if x < image.get_width() / 2:
				left_sum += c.get_luminance()
			else:
				right_sum += c.get_luminance()
	var half := maxi(samples / 2, 1)
	var delta := absf(left_sum / half - right_sum / (samples - half))
	var loss_pct := 100.0 * (1.0 - float(_leaf_after) / maxf(float(_leaf_before), 1.0))
	print("screenshot=artifacts/evo4_t3_trophic_defense.png")
	print("pixel_check unique=%d column_delta=%.4f thorns=%d leaf_loss=%.1f%%" % [
		unique.size(), delta, _thorn_total, loss_pct])
	if unique.size() >= 250 and delta >= 0.002 and _thorn_total > 0 and loss_pct > 5.0 and loss_pct < 95.0:
		print("ECO.EVO4/E4.T3 TROPHIC DEFENSE LAB: PASS (%d species before/after, browse=%.2f)" % [
			species_count, BROWSE_PRESSURE])
		get_tree().quit(0)
	else:
		print("ECO.EVO4/E4.T3 TROPHIC DEFENSE LAB: FAIL (pixel gate)")
		get_tree().quit(1)
