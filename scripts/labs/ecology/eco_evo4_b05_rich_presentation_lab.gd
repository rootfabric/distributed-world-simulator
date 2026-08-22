extends Node3D

## ECO.EVO4/E4.B0.5 — Rich Presentation Spike lab.
## Renders both bridge-input species as cohorts (3 seeded individuals each)
## through the evo4_bridge_presentation_v1 enricher over the accepted PH chain.
## Adds deterministic ground scatter and atmosphere. Captures one viewport PNG
## into artifacts/ and quits. Presentation only; zero chain-hash impact.

const Presentation = preload("res://scripts/research/ecology/evo4_bridge_presentation_v1.gd")

const INPUT_PATH := "res://validation/ecology/evo4_b0_bridge_input.v1.json"
const CATALOG_PATH := "res://config/ecology/accepted_inputs/evo2_full_persisted_species_catalog.e3_4.v1.json"
const COHORT_SCALES: Array[float] = [0.85, 1.0, 1.18]
const FOLIAGE_DENSITY := 1.8

func _ready() -> void:
	var input_text := FileAccess.get_file_as_string(INPUT_PATH)
	var subjects = JSON.parse_string(input_text) if not input_text.is_empty() else null
	if typeof(subjects) != TYPE_DICTIONARY or (subjects as Dictionary)["subjects"] == null:
		print("ECO.EVO4/E4.B0.5 RICH PRESENTATION: FAIL (missing bridge input)")
		get_tree().quit(1)
		return
	var catalog_text := FileAccess.get_file_as_string(CATALOG_PATH)
	var catalog = JSON.parse_string(catalog_text)
	var dormancy := {}
	if typeof(catalog) == TYPE_DICTIONARY:
		for entry in Array((catalog as Dictionary)["entries"]):
			var genome: Dictionary = (entry as Dictionary)["genome"]
			dormancy[String(genome["genome_id"])] = float(((entry as Dictionary)["recruitment_traits"] as Dictionary)["dormancy_fraction"])

	_build_environment()

	var report: Array[String] = []
	var group_centers := [Vector3(-2.4, 0, 0), Vector3(2.6, 0, 0)]
	for s in range(2):
		var subject: Dictionary = (subjects as Dictionary)["subjects"][s]
		var traits: Dictionary = (subject["development_traits"] as Dictionary).duplicate(true)
		traits["branching_depth"] = int(traits["branching_depth"])
		var base_seed := int(subject["individual_seed"])
		var wp: float = float((subject["development_traits"] as Dictionary).get("_water_preference", 0.0))
		# water/shade preference are metabolic fields; read them from accepted catalog genome if present
		wp = _metabolic_field(catalog, String(subject["genome_id"]), "water_preference", wp)
		var shade: float = _metabolic_field(catalog, String(subject["genome_id"]), "shade_tolerance", 0.3)
		var dorm: float = float(dormancy.get(String(subject["genome_id"]), 0.25))
		var center: Vector3 = group_centers[s]
		for c in range(COHORT_SCALES.size()):
			var seed_value := base_seed + c * 7919
			var built := Presentation.build_rich_subject(traits, seed_value, wp, shade, dorm, FOLIAGE_DENSITY)
			if built.is_empty():
				print("ECO.EVO4/E4.B0.5 RICH PRESENTATION: FAIL (subject %s cohort %d)" % [String(subject["genome_id"]), c])
				get_tree().quit(1)
				return
			var root := _instantiate_built(built)
			root.position = center + Vector3(float(c - 1) * 1.05, 0.0, absf(float(c - 1)) * 0.8)
			root.scale = Vector3.ONE * COHORT_SCALES[c]
			add_child(root)
			var stats: Dictionary = built["stats"]
			report.append("%s c%d seed=%d hash=%s twigs=%d leaves=%d flowers=%d arch=%s palette=%s" % [
				String(subject["genome_id"]), c, seed_value, String(stats["presentation_hash"]).substr(0, 12),
				int(stats["twig_count"]), int(stats["leaf_count"]), int(stats["flower_count"]),
				String(stats["archetype"]), String(stats["palette_id"]),
			])
	await _capture("res://artifacts/evo4_b05_rich_presentation.png")
	print("ECO.EVO4/E4.B0.5 RICH PRESENTATION: PASS (%d cohorts, foliage_density=%.1f)" % [COHORT_SCALES.size() * 2, FOLIAGE_DENSITY])
	for line in report:
		print(line)
	print("screenshot=artifacts/evo4_b05_rich_presentation.png")
	get_tree().quit(0)

func _metabolic_field(catalog, genome_id: String, field: String, fallback: float) -> float:
	if typeof(catalog) != TYPE_DICTIONARY:
		return fallback
	for entry in Array((catalog as Dictionary)["entries"]):
		var genome: Dictionary = (entry as Dictionary)["genome"]
		if String(genome["genome_id"]) == genome_id:
			return float(genome[field])
	return fallback

func _instantiate_built(built: Dictionary) -> Node3D:
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
	sky_mat.ground_horizon_color = Color(0.92, 0.76, 0.58)
	sky_mat.ground_bottom_color = Color(0.23, 0.20, 0.16)
	var sky_res := Sky.new()
	sky_res.sky_material = sky_mat
	env.sky = sky_res
	env.fog_enabled = true
	env.fog_light_color = Color(0.85, 0.74, 0.62)
	env.fog_density = 0.005
	env.fog_sky_affect = 0.0
	world_env.environment = env
	add_child(world_env)

	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(40.0, 40.0)
	ground.mesh = plane
	var ground_material := StandardMaterial3D.new()
	ground_material.albedo_color = Color(0.17, 0.13, 0.09)
	ground_material.roughness = 1.0
	ground.material_override = ground_material
	add_child(ground)

	_add_scatter()

	var camera := Camera3D.new()
	camera.name = "Camera3D"
	camera.current = true
	add_child(camera)
	camera.position = Vector3(-1.0, 3.4, 12.5)
	camera.look_at(Vector3(0.0, 2.4, 0.0), Vector3.UP)

func _add_scatter() -> void:
	var grass_mesh := _grass_tuft_mesh()
	var grass_transforms: Array[Transform3D] = []
	var grass_colors: Array[Color] = []
	for i in range(150):
		var key := "grass/%d" % i
		var angle := TAU * Presentation._unit(key + "/a")
		var radius := 2.2 + 11.0 * Presentation._unit(key + "/r")
		var pos := Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
		var yaw := TAU * Presentation._unit(key + "/y")
		var s := 0.7 + 0.9 * Presentation._unit(key + "/s")
		grass_transforms.append(Transform3D(Basis(Vector3.UP, yaw), pos).scaled(Vector3(s, s, s)))
		grass_colors.append(Color.from_hsv(0.22 + 0.06 * Presentation._unit(key + "/c"), 0.45, 0.30 + 0.14 * Presentation._unit(key + "/v")))
	add_child(_instanced(grass_mesh, grass_transforms, grass_colors, true))

	var rock_mesh := SphereMesh.new()
	rock_mesh.radius = 0.09
	rock_mesh.height = 0.11
	var rock_transforms: Array[Transform3D] = []
	var rock_colors: Array[Color] = []
	for i in range(18):
		var key := "rock/%d" % i
		var angle := TAU * Presentation._unit(key + "/a")
		var radius := 1.6 + 10.0 * Presentation._unit(key + "/r")
		var pos := Vector3(cos(angle) * radius, 0.02, sin(angle) * radius)
		var s := 0.5 + 1.3 * Presentation._unit(key + "/s")
		rock_transforms.append(Transform3D(Basis(Vector3.UP, TAU * Presentation._unit(key + "/y")), pos).scaled(Vector3(s, s * 0.6, s)))
		rock_colors.append(Color(0.36, 0.34, 0.31).lightened(0.15 * Presentation._unit(key + "/v")))
	add_child(_instanced(rock_mesh, rock_transforms, rock_colors, false))

func _grass_tuft_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for blade in range(2):
		var ang := float(blade) * PI * 0.5
		var dir := Vector3(cos(ang), 0.0, sin(ang))
		var side := Vector3(-dir.z, 0.0, dir.x) * 0.02
		st.set_normal(Vector3.UP); st.set_color(Color(1, 1, 1)); st.add_vertex(-side)
		st.set_normal(Vector3.UP); st.set_color(Color(1, 1, 1)); st.add_vertex(side)
		st.set_normal(Vector3.UP); st.set_color(Color(1, 1, 1)); st.add_vertex(dir * 0.07 + Vector3.UP * 0.16)
		st.set_normal(Vector3.UP); st.set_color(Color(1, 1, 1)); st.add_vertex(side)
		st.set_normal(Vector3.UP); st.set_color(Color(1, 1, 1)); st.add_vertex(-side + dir * 0.03)
		st.set_normal(Vector3.UP); st.set_color(Color(1, 1, 1)); st.add_vertex(dir * -0.05 + Vector3.UP * 0.13)
	return st.commit(ArrayMesh.new())

func _capture(target_res_path: String) -> void:
	for frame_index in range(24):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var absolute := ProjectSettings.globalize_path(target_res_path)
	DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	image.save_png(absolute)
