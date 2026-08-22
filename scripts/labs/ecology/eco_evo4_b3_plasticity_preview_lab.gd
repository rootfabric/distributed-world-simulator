extends Node3D

## ECO.EVO4/E4.B3 — Plasticity preview: one genome under three condition sets.
## Consumes the gate-exported preview subjects (effective PH0 traits from the
## B2 compiler) and renders them with the rich presentation module.
## Derived presentation only; screenshot evidence into artifacts/.

const Presentation = preload("res://scripts/research/ecology/evo4_bridge_presentation_v1.gd")

const INPUT_PATH := "res://validation/ecology/evo4_b3_preview_subjects.v1.json"
const CATALOG_PATH := "res://config/ecology/accepted_inputs/evo2_full_persisted_species_catalog.e3_4.v1.json"

func _ready() -> void:
	var text := FileAccess.get_file_as_string(INPUT_PATH)
	var parsed = JSON.parse_string(text) if not text.is_empty() else null
	var catalog = JSON.parse_string(FileAccess.get_file_as_string(CATALOG_PATH))
	if typeof(parsed) != TYPE_DICTIONARY:
		print("ECO.EVO4/E4.B3 PLASTICITY PREVIEW: FAIL (missing preview subjects)")
		get_tree().quit(1)
		return
	_build_environment()
	var x := -4.6
	for subject in Array((parsed as Dictionary)["subjects"]):
		var s: Dictionary = subject
		var traits: Dictionary = (s["development_traits"] as Dictionary).duplicate(true)
		traits["branching_depth"] = int(traits["branching_depth"])
		var genome_id := String(s["genome_id"])
		var wp := _metabolic(catalog, genome_id, "water_preference", 0.5)
		var shade := _metabolic(catalog, genome_id, "shade_tolerance", 0.3)
		var dorm := _dormancy(catalog, genome_id, 0.25)
		var built := Presentation.build_rich_subject(traits, int(s["individual_seed_demo"]), wp, shade, dorm, 1.6)
		if built.is_empty():
			print("ECO.EVO4/E4.B3 PLASTICITY PREVIEW: FAIL (%s)" % String(s["label"]))
			get_tree().quit(1)
			return
		var root := _instantiate(built)
		root.position = Vector3(x, 0.0, 0.0)
		add_child(root)
		var label := Label3D.new()
		label.text = "%s\nh=%.2fm crown=%.2fm" % [String(s["label"]), float(traits["max_height_m"]), float(traits["crown_spread_m"])]
		label.font_size = 40
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.position = Vector3(x, float(traits["max_height_m"]) + 0.55, 0.0)
		add_child(label)
		x += 4.6
	await _capture("res://artifacts/evo4_b3_plasticity_preview.png")
	print("ECO.EVO4/E4.B3 PLASTICITY PREVIEW: PASS (%d conditions)" % ((parsed as Dictionary)["subjects"].size()))
	print("screenshot=artifacts/evo4_b3_plasticity_preview.png")
	get_tree().quit(0)

func _metabolic(catalog, genome_id: String, field: String, fallback: float) -> float:
	if typeof(catalog) != TYPE_DICTIONARY:
		return fallback
	for entry in Array((catalog as Dictionary)["entries"]):
		var genome: Dictionary = (entry as Dictionary)["genome"]
		if String(genome["genome_id"]) == genome_id:
			return float(genome[field])
	return fallback

func _dormancy(catalog, genome_id: String, fallback: float) -> float:
	if typeof(catalog) != TYPE_DICTIONARY:
		return fallback
	for entry in Array((catalog as Dictionary)["entries"]):
		var genome: Dictionary = (entry as Dictionary)["genome"]
		if String(genome["genome_id"]) == genome_id:
			return float(((entry as Dictionary)["recruitment_traits"] as Dictionary)["dormancy_fraction"])
	return fallback

func _instantiate(built: Dictionary) -> Node3D:
	var root := Node3D.new()
	var branch_instance := MeshInstance3D.new()
	branch_instance.mesh = built["branch_mesh"]
	var branch_material := StandardMaterial3D.new()
	branch_material.vertex_color_use_as_albedo = true
	branch_material.roughness = 0.88
	branch_instance.material_override = branch_material
	root.add_child(branch_instance)
	root.add_child(_instanced(built["leaf_mesh"], built["leaf_transforms"], built["leaf_colors"], true))
	var flower_colors: Array[Color] = []
	for f in range((built["flower_transforms"] as Array).size()):
		flower_colors.append(built["flower_color"] if f % 5 != 4 else built["flower_core_color"])
	root.add_child(_instanced(built["flower_mesh"], built["flower_transforms"], flower_colors, true))
	return root

func _instanced(mesh: Mesh, transforms: Array[Transform3D], colors: Array[Color], double_sided: bool) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = transforms.size()
	for i in range(transforms.size()):
		mm.set_instance_transform(i, transforms[i])
		mm.set_instance_color(i, colors[i])
	var holder := MultiMeshInstance3D.new()
	holder.multimesh = mm
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	if double_sided:
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.roughness = 0.75
	holder.material_override = material
	return holder

func _build_environment() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-26.0, 38.0, 0.0)
	sun.light_color = Color(1.0, 0.86, 0.66)
	sun.light_energy = 1.55
	sun.shadow_enabled = true
	add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-18.0, -140.0, 0.0)
	fill.light_color = Color(0.62, 0.70, 0.95)
	fill.light_energy = 0.32
	add_child(fill)
	var world_env := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.30, 0.47, 0.72)
	sky_mat.sky_horizon_color = Color(0.92, 0.76, 0.58)
	sky_mat.ground_horizon_color = sky_mat.sky_horizon_color
	sky_mat.ground_bottom_color = Color(0.23, 0.20, 0.16)
	var sky_res := Sky.new()
	sky_res.sky_material = sky_mat
	env.sky = sky_res
	world_env.environment = env
	add_child(world_env)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(40.0, 40.0)
	ground.mesh = plane
	var ground_material := StandardMaterial3D.new()
	ground_material.albedo_color = Color(0.17, 0.13, 0.09)
	ground.material_override = ground_material
	add_child(ground)
	var camera := Camera3D.new()
	camera.current = true
	add_child(camera)
	camera.position = Vector3(0.0, 3.2, 11.0)
	camera.look_at(Vector3(0.0, 2.0, 0.0), Vector3.UP)

func _capture(target_res_path: String) -> void:
	for frame_index in range(24):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var absolute := ProjectSettings.globalize_path(target_res_path)
	DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	image.save_png(absolute)
