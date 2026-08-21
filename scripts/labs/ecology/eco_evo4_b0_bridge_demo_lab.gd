extends Node3D

## ECO.EVO4/E4.B0 — Morphology Bridge demo pipe (authorized research demo).
## Reads the derived bridge input JSON, builds GrowthGraph skeletons via the
## accepted PH1 producer, render descriptions via the accepted PH5 builder and
## materializes them with the accepted PH5 3D materializer. Captures one
## viewport PNG into artifacts/ as machine evidence, prints a PASS marker and
## quits. Derived presentation only; no ecology truth claims.

const Traits = preload("res://scripts/research/ecology/plant_development_traits_v1.gd")
const Skeleton = preload("res://scripts/research/ecology/plant_growth_graph_skeleton_v1.gd")
const RenderDescription = preload("res://scripts/research/ecology/plant_render_description_v1.gd")
const RendererProfile = preload("res://scripts/research/ecology/plant_renderer_profile_v1.gd")
const Materializer3D = preload("res://scripts/research/ecology/plant_3d_materializer_v1.gd")

const INPUT_PATH := "res://validation/ecology/evo4_b0_bridge_input.v1.json"
const PROFILE_ID := "BRANCH_LEAF_INSTANCED"

var _failures: Array[String] = []

func _ready() -> void:
	var parsed := _load_input()
	if parsed.is_empty():
		_finish(false)
		return
	_build_scene_shell()
	var report_lines: Array[String] = []
	var x_cursor := 0.0
	var max_height := 0.0
	for subject in parsed["subjects"]:
		var outcome := _materialize_subject(subject)
		if outcome.is_empty():
			_failures.append("subject failed: " + String(subject["genome_id"]))
			continue
		outcome["root"].position = Vector3(x_cursor, 0.0, 0.0)
		x_cursor += maxf(2.6, float(outcome["radius"]) * 2.6 + 0.8)
		max_height = maxf(max_height, float(outcome["height"]))
		report_lines.append(String(outcome["summary"]))
	if not _failures.is_empty():
		for line in report_lines:
			print(line)
		_finish(false)
		return
	var camera: Camera3D = get_node("Camera3D") as Camera3D
	var span := x_cursor
	camera.position = Vector3(span * 0.5 - 0.6, max_height * 0.62, maxf(3.4, max_height * 1.25))
	camera.look_at(Vector3(span * 0.5 - 0.6, max_height * 0.42, 0.0), Vector3.UP)
	await _capture("res://artifacts/evo4_b0_bridge_demo.png")
	print("ECO.EVO4/E4.B0 BRIDGE DEMO: PASS (%d subjects)" % parsed["subjects"].size())
	for line in report_lines:
		print(line)
	print("screenshot=artifacts/evo4_b0_bridge_demo.png profile=%s" % PROFILE_ID)
	_finish(true)

func _finish(success: bool) -> void:
	if not success:
		print("ECO.EVO4/E4.B0 BRIDGE DEMO: FAIL")
		for failure in _failures:
			print("  failure: " + failure)
	get_tree().quit(0 if success else 1)

func _load_input() -> Dictionary:
	var text := FileAccess.get_file_as_string(INPUT_PATH)
	if text.is_empty():
		_failures.append("missing input " + INPUT_PATH)
		return {}
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		_failures.append("input is not an object")
		return {}
	return parsed

func _materialize_subject(subject: Dictionary) -> Dictionary:
	var traits: Dictionary = subject["development_traits"].duplicate(true)
	# JSON.parse_string yields floats for every number; the accepted PH0
	# validator requires a true int for branching_depth.
	traits["branching_depth"] = int(traits["branching_depth"])
	var seed_value := int(subject["individual_seed"])
	if not bool(Traits.validate(traits).get("success", false)):
		_failures.append("traits invalid: " + String(subject["genome_id"]))
		return {}
	# Determinism probe: two independent builds of the same subject must agree.
	var graph_a := Skeleton.build(traits, seed_value)
	var graph_b := Skeleton.build(traits, seed_value)
	if graph_a.is_empty() or String(graph_a["graph_hash"]) != String(graph_b["graph_hash"]):
		_failures.append("graph determinism mismatch: " + String(subject["genome_id"]))
		return {}
	var description := RenderDescription.build(graph_a)
	if description.is_empty() or not bool(RenderDescription.validate(description).get("success", false)):
		_failures.append("render description invalid: " + String(subject["genome_id"]))
		return {}
	var built := Materializer3D.build(description, RendererProfile.create(PROFILE_ID))
	if built.is_empty():
		_failures.append("materialization failed: " + String(subject["genome_id"]))
		return {}
	var root := Node3D.new()
	root.name = "Subject_" + String(subject["genome_id"]).replace("/", "_").replace(".", "_")
	add_child(root)
	var branch_instance := MeshInstance3D.new()
	branch_instance.mesh = built["branch_mesh"]
	var branch_material := StandardMaterial3D.new()
	branch_material.albedo_color = Color(0.36, 0.23, 0.12)
	branch_material.roughness = 0.86
	branch_instance.material_override = branch_material
	root.add_child(branch_instance)
	var foliage := MultiMeshInstance3D.new()
	foliage.multimesh = built["foliage_multimesh"]
	root.add_child(foliage)
	var height := float(description["bounds"]["height_m"])
	var radius := float(description["bounds"]["radius_xz_m"])
	return {
		"root": root,
		"height": height,
		"radius": radius,
		"summary": "%s graph_hash=%s geometry_hash=%s branches=%d foliage=%d h=%.2fm r=%.2fm" % [
			String(subject["genome_id"]), String(graph_a["graph_hash"]),
			String(built["geometry_hash"]), int(built["branch_count"]),
			int(built["foliage_instance_count"]), height, radius,
		],
	}

func _build_scene_shell() -> void:
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-48.0, -30.0, 0.0)
	light.shadow_enabled = true
	add_child(light)

	var ground := MeshInstance3D.new()
	var ground_mesh := PlaneMesh.new()
	ground_mesh.size = Vector2(24.0, 24.0)
	ground.mesh = ground_mesh
	var ground_material := StandardMaterial3D.new()
	ground_material.albedo_color = Color(0.10, 0.13, 0.11)
	ground.material_override = ground_material
	add_child(ground)

	var sky := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	var sky_resource := Sky.new()
	sky_resource.sky_material = ProceduralSkyMaterial.new()
	environment.sky = sky_resource
	sky.environment = environment
	add_child(sky)

	var camera := Camera3D.new()
	camera.name = "Camera3D"
	camera.current = true
	add_child(camera)

func _capture(target_res_path: String) -> void:
	for frame_index in range(24):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var absolute := ProjectSettings.globalize_path(target_res_path)
	DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	image.save_png(absolute)
