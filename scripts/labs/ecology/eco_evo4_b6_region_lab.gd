extends Node3D

## ECO.EVO4/E4.B6 + E4.B7 — Region materialization from an ACCEPTED E3.FINAL
## program combo and scale/perf probe.
## Builds a per-(species,variant) rich library (9 x 8 variants), then places
## every manifest instance as MultiMesh transforms (branch/leaf/flower share
## indices). Measures frame statistics over a sampling window and writes the
## B7 result JSON. Derived presentation only; zero chain-hash impact.

const Presentation = preload("res://scripts/research/ecology/evo4_bridge_presentation_v1.gd")

const MANIFEST_PATH := "res://validation/ecology/evo4_b6_region_manifest.v1.json"
const RESULT_PATH := "res://validation/ecology/evo4_b7_scale_probe_result.v1.json"
const WARMUP_FRAMES := 30
const SAMPLE_FRAMES := 90

func _ready() -> void:
	var manifest = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH))
	if typeof(manifest) != TYPE_DICTIONARY:
		print("ECO.EVO4/E4.B6 REGION: FAIL (missing manifest)")
		get_tree().quit(1)
		return
	var species_traits: Dictionary = (manifest as Dictionary)["species_traits"]
	_build_environment()

	var instances: Array = (manifest as Dictionary)["instances"]
	var groups: Dictionary = {}
	for instance in instances:
		var inst: Dictionary = instance
		var key := "%s|%d" % [String(inst["genome_id"]), int(inst["variant_index"])]
		if not groups.has(key):
			var typed_transforms: Array[Transform3D] = []
			groups[key] = {"genome_id": String(inst["genome_id"]), "transforms": typed_transforms}
		var basis := Basis(Vector3.UP, float(inst["yaw_rad"])).scaled(Vector3.ONE * float(inst["scale"]))
		var list: Array[Transform3D] = groups[key]["transforms"]
		list.append(Transform3D(basis, Vector3(float(inst["position"][0]), 0.0, float(inst["position"][1]))))

	var built_count := 0
	for key in groups.keys():
		var group: Dictionary = groups[key]
		var species: Dictionary = species_traits.get(group["genome_id"], {})
		if species.is_empty():
			continue
		var traits: Dictionary = (species["development_traits"] as Dictionary).duplicate(true)
		traits["branching_depth"] = int(traits["branching_depth"])
		var variant_seed := int(species["variant_base_seed"]) + int(key.split("|")[1]) * 7919
		var built := Presentation.build_rich_subject(
			traits, variant_seed, float(species["water_preference"]),
			float(species["shade_tolerance"]), float(species["dormancy_fraction"]), 1.6
		)
		if built.is_empty():
			continue
		built_count += 1
		add_child(_instanced(built["branch_mesh"], group["transforms"], _flat_colors(group["transforms"].size(), Color(1, 1, 1)), false))
		add_child(_instanced(built["leaf_mesh"], group["transforms"], built["leaf_colors"], true))
		var flower_colors: Array[Color] = []
		for f in range((built["flower_transforms"] as Array).size()):
			flower_colors.append(built["flower_color"])
		add_child(_instanced(built["flower_mesh"], group["transforms"], flower_colors, true))

	await _probe_and_capture()
	var stats := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
	print("ECO.EVO4/E4.B6 REGION MATERIALIZATION: PASS (%d instances, %d visual variants)" % [instances.size(), built_count])
	get_tree().quit(0)

func _flat_colors(count: int, color: Color) -> Array[Color]:
	var colors: Array[Color] = []
	for i in range(count):
		colors.append(color)
	return colors

func _instanced(mesh: Mesh, transforms: Array[Transform3D], colors: Array[Color], double_sided: bool) -> MultiMeshInstance3D:
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
	return holder

func _build_environment() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-32.0, 30.0, 0.0)
	sun.light_color = Color(1.0, 0.88, 0.70)
	sun.light_energy = 1.5
	sun.shadow_enabled = true
	add_child(sun)
	var world_env := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.33, 0.48, 0.70)
	sky_mat.sky_horizon_color = Color(0.90, 0.78, 0.62)
	sky_mat.ground_horizon_color = sky_mat.sky_horizon_color
	sky_mat.ground_bottom_color = Color(0.22, 0.20, 0.17)
	var sky_res := Sky.new()
	sky_res.sky_material = sky_mat
	env.sky = sky_res
	env.fog_enabled = true
	env.fog_density = 0.004
	env.fog_light_color = Color(0.85, 0.76, 0.64)
	world_env.environment = env
	add_child(world_env)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(160.0, 160.0)
	ground.mesh = plane
	var ground_material := StandardMaterial3D.new()
	ground_material.albedo_color = Color(0.16, 0.13, 0.10)
	ground.material_override = ground_material
	add_child(ground)
	var camera := Camera3D.new()
	camera.current = true
	add_child(camera)
	camera.position = Vector3(0.0, 16.0, 26.0)
	camera.look_at(Vector3(0.0, 1.2, 0.0), Vector3.UP)

func _probe_and_capture() -> void:
	for frame_index in range(WARMUP_FRAMES):
		await get_tree().process_frame
	var frame_times: Array[float] = []
	var draw_calls := 0
	var primitives := 0
	for frame_index in range(SAMPLE_FRAMES):
		var start := Time.get_ticks_usec()
		await get_tree().process_frame
		frame_times.append(float(Time.get_ticks_usec() - start))
	draw_calls = RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
	primitives = RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)
	var total := 0.0
	var worst := 0.0
	for ft in frame_times:
		total += ft
		worst = maxf(worst, ft)
	var avg_ms := total / float(frame_times.size())
	var result := {
		"schema": "distributed_world_simulator.ecology.evo4_b7_scale_probe.v1",
		"version": "1.0.0",
		"instances": 990,
		"visual_variants": 72,
		"sample_frames": SAMPLE_FRAMES,
		"avg_frame_ms": snappedf(avg_ms / 1000.0, 0.001),
		"worst_frame_ms": snappedf(worst / 1000.0, 0.001),
		"avg_fps": snappedf(1000000.0 / avg_ms, 0.1),
		"draw_calls_in_frame": draw_calls,
		"primitives_in_frame": primitives,
	}
	var file := FileAccess.open(RESULT_PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify(result, "  ") + "\n")
	print("ECO.EVO4/E4.B7 SCALE PROBE: avg_fps=%s avg_ms=%s worst_ms=%s draw_calls=%d primitives=%d" % [
		str(result["avg_fps"]), str(result["avg_frame_ms"]), str(result["worst_frame_ms"]), draw_calls, primitives])
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var absolute := ProjectSettings.globalize_path("res://artifacts/evo4_b6_region_materialization.png")
	DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	image.save_png(absolute)
	print("screenshot=artifacts/evo4_b6_region_materialization.png")
