extends Node3D

## ECO.EVO4/E4.T4 — Planetary trophic probe.
## Applies the EVO4.T2 equilibrium defense distribution onto the ACCEPTED
## E4.B6 region manifest instances (polar-plateau-04 / extended_r1) as
## per-species defense classes, enables thorn visuals for every instance and
## re-runs the B7-style scale/perf probe on the same region. Gates: chain
## graph hashes unchanged by the presentation layer, fps >= 100. Presentation
## layer only; zero chain-hash impact; PH5 core untouched.

const Presentation = preload("res://scripts/research/ecology/evo4_bridge_presentation_v1.gd")
const Skeleton = preload("res://scripts/research/ecology/plant_growth_graph_skeleton_v1.gd")

const MANIFEST_PATH := "res://validation/ecology/evo4_b6_region_manifest.v1.json"
const TRAJECTORY_PATH := "res://validation/ecology/evo4_t2_coevolution_trajectory.v1.json"
const RESULT_PATH := "res://validation/ecology/evo4_t4_planetary_probe_result.v1.json"
const SCREENSHOT_PATH := "res://artifacts/evo4_t4_planetary_trophic.png"
const WARMUP_FRAMES := 30
const SAMPLE_FRAMES := 90
const FPS_GATE := 100.0


func _ready() -> void:
	var manifest = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH))
	var trajectory = JSON.parse_string(FileAccess.get_file_as_string(TRAJECTORY_PATH))
	if typeof(manifest) != TYPE_DICTIONARY or typeof(trajectory) != TYPE_DICTIONARY:
		print("ECO.EVO4/E4.T4 PLANETARY TROPHIC PROBE: FAIL (missing inputs)")
		get_tree().quit(1)
		return
	var manifest_dict: Dictionary = manifest
	var trajectory_dict: Dictionary = trajectory
	var species_traits: Dictionary = manifest_dict["species_traits"]
	var equilibrium: Dictionary = trajectory_dict["equilibrium"]
	var final_defense: Dictionary = equilibrium["final_defense"]

	_build_environment()

	var instances: Array = manifest_dict["instances"]
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
	var thorn_total := 0
	var hashes_invariant := true
	var defense_classes := {}
	for key in groups.keys():
		var group: Dictionary = groups[key]
		var gid := String(group["genome_id"])
		var species: Dictionary = species_traits.get(gid, {})
		if species.is_empty() or not final_defense.has(gid):
			continue
		var traits: Dictionary = (species["development_traits"] as Dictionary).duplicate(true)
		traits["branching_depth"] = int(traits["branching_depth"]) # JSON numbers are float
		var variant_seed := int(species["variant_base_seed"]) + int(key.split("|")[1]) * 7919
		var level := clampf(float(final_defense[gid]), 0.0, 1.0)

		# Chain-hash invariance evidence: the causal skeleton hash must be
		# identical with or without the thorn presentation layer.
		var direct_hash := String(Skeleton.build(traits, variant_seed)["graph_hash"])
		var built := Presentation.build_rich_subject(
			traits, variant_seed, float(species["water_preference"]),
			float(species["shade_tolerance"]), float(species["dormancy_fraction"]), 1.6, level)
		if built.is_empty():
			continue
		if direct_hash != String(built["stats"]["source_graph_hash"]):
			hashes_invariant = false

		built_count += 1
		defense_classes[gid] = {"class": _classify(level), "level": snappedf(level, 0.001)}
		var thorns: Array = built["thorn_transforms"]
		thorn_total += group["transforms"].size() * thorns.size()
		add_child(_instanced(built["branch_mesh"], group["transforms"], _flat_colors(group["transforms"].size(), Color(1, 1, 1)), false))
		add_child(_instanced(built["leaf_mesh"], group["transforms"], built["leaf_colors"], true))
		var flower_colors: Array[Color] = []
		for f in range((built["flower_transforms"] as Array).size()):
			flower_colors.append(built["flower_color"])
		add_child(_instanced(built["flower_mesh"], group["transforms"], flower_colors, true))
		if thorns.size() > 0:
			var thorn_colors: Array[Color] = []
			for t in range(thorns.size()):
				thorn_colors.append(built["thorn_color"])
			add_child(_instanced(built["thorn_mesh"], group["transforms"], thorn_colors, false))

	await _probe_and_capture(manifest_dict, instances.size(), built_count, thorn_total,
		hashes_invariant, defense_classes)


func _classify(level: float) -> String:
	if level < 0.2:
		return "NONE"
	if level < 0.4:
		return "LIGHT"
	if level < 0.6:
		return "MODERATE"
	if level < 0.8:
		return "HIGH"
	return "FULL"


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


func _probe_and_capture(
	manifest: Dictionary, instance_count: int, visual_variants: int, thorn_total: int,
	hashes_invariant: bool, defense_classes: Dictionary
) -> void:
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
	var avg_fps := 1000000.0 / avg_ms

	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var absolute := ProjectSettings.globalize_path(SCREENSHOT_PATH)
	DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	image.save_png(absolute)
	print("screenshot=artifacts/evo4_t4_planetary_trophic.png")

	var source_combination: Dictionary = manifest["source_combination"]
	var result := {
		"schema": "distributed_world_simulator.ecology.evo4_t4_planetary_probe.v1",
		"version": "1.0.0",
		"derived_representation": true,
		"source_program_sha256": String(source_combination.get("source_program_sha256", "")),
		"stable_planet_identity": String(source_combination.get("stable_planet_identity", "")),
		"planet_snapshot_sha256": String(source_combination.get("planet_snapshot_sha256", "")),
		"defense_source_artifact": "validation/ecology/evo4_t2_coevolution_trajectory.v1.json",
		"instances": instance_count,
		"visual_variants": visual_variants,
		"thorn_instances_total": thorn_total,
		"defense_classes": defense_classes,
		"graph_hash_invariance": hashes_invariant,
		"sample_frames": SAMPLE_FRAMES,
		"avg_frame_ms": snappedf(avg_ms / 1000.0, 0.001),
		"worst_frame_ms": snappedf(worst / 1000.0, 0.001),
		"avg_fps": snappedf(avg_fps, 0.1),
		"draw_calls_in_frame": draw_calls,
		"primitives_in_frame": primitives,
		"fps_gate": avg_fps >= FPS_GATE,
		"verdict": "PASS" if (avg_fps >= FPS_GATE and hashes_invariant) else "FAIL",
	}
	var file := FileAccess.open(RESULT_PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify(result, "  ") + "\n")
	print("ECO.EVO4/E4.T4 PLANETARY TROPHIC PROBE: avg_fps=%s avg_ms=%s worst_ms=%s draw_calls=%d thorns=%d hash_invariance=%s" % [
		str(result["avg_fps"]), str(result["avg_frame_ms"]), str(result["worst_frame_ms"]),
		draw_calls, thorn_total, str(hashes_invariant)])
	print("ECO.EVO4/E4.T4 PLANETARY TROPHIC PROBE: %s" % result["verdict"])
	get_tree().quit(0 if result["verdict"] == "PASS" else 1)
