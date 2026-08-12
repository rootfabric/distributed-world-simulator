extends Node3D

const Probes = preload("res://scripts/research/ecology/plant_render_description_probes_v1.gd")
const RendererProfile = preload("res://scripts/research/ecology/plant_renderer_profile_v1.gd")
const Materializer3D = preload("res://scripts/research/ecology/plant_3d_materializer_v1.gd")

const PROFILE_IDS := ["BRANCH_TUBES", "BRANCH_LEAF_INSTANCED", "FULL_PROCEDURAL"]

var environment_index := 0
var profile_index := 1
var results: Dictionary = {}
var status_label: Label
var plant_root: Node3D
var camera: Camera3D

func _ready() -> void:
	results = Probes.run_all()
	_build_scene_shell()
	_refresh()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_E:
		environment_index = (environment_index + 1) % Probes.ENVIRONMENT_ORDER.size()
		_refresh()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_Q:
		environment_index = (environment_index - 1 + Probes.ENVIRONMENT_ORDER.size()) % Probes.ENVIRONMENT_ORDER.size()
		_refresh()
	elif event.is_action_pressed("ui_right") or (event is InputEventKey and event.pressed and event.keycode == KEY_D):
		profile_index = (profile_index + 1) % PROFILE_IDS.size()
		_refresh()
	elif event.is_action_pressed("ui_left") or (event is InputEventKey and event.pressed and event.keycode == KEY_A):
		profile_index = (profile_index - 1 + PROFILE_IDS.size()) % PROFILE_IDS.size()
		_refresh()

func _build_scene_shell() -> void:
	plant_root = Node3D.new()
	plant_root.name = "PlantMaterialization"
	add_child(plant_root)

	camera = Camera3D.new()
	camera.name = "Camera3D"
	camera.current = true
	add_child(camera)

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45.0, -25.0, 0.0)
	light.shadow_enabled = true
	add_child(light)

	var ground_mesh := PlaneMesh.new()
	ground_mesh.size = Vector2(8.0, 8.0)
	var ground := MeshInstance3D.new()
	ground.mesh = ground_mesh
	var ground_material := StandardMaterial3D.new()
	ground_material.albedo_color = Color(0.10, 0.12, 0.10)
	ground.material_override = ground_material
	add_child(ground)

	var canvas := CanvasLayer.new()
	add_child(canvas)
	status_label = Label.new()
	status_label.position = Vector2(14.0, 12.0)
	status_label.size = Vector2(1120.0, 180.0)
	status_label.add_theme_font_size_override("font_size", 16)
	canvas.add_child(status_label)

func _refresh() -> void:
	if results.is_empty() or plant_root == null:
		return
	for child in plant_root.get_children():
		child.queue_free()
	var environment_name := Probes.ENVIRONMENT_ORDER[environment_index]
	var profile_id: String = PROFILE_IDS[profile_index]
	var item: Dictionary = results[environment_name]
	var description: Dictionary = item["render_description"]
	var profile := RendererProfile.create(profile_id)
	var built := Materializer3D.build(description, profile)
	if built.is_empty():
		status_label.text = "ECO.PH5-S2 materialization failed"
		return

	var branch_mesh: ArrayMesh = built["branch_mesh"]
	if branch_mesh != null:
		var branch_instance := MeshInstance3D.new()
		branch_instance.name = "TaperedBranches"
		branch_instance.mesh = branch_mesh
		var branch_material := StandardMaterial3D.new()
		branch_material.albedo_color = Color(0.38, 0.24, 0.12)
		branch_material.roughness = 0.86
		branch_instance.material_override = branch_material
		plant_root.add_child(branch_instance)

	var foliage_multimesh: MultiMesh = built["foliage_multimesh"]
	if foliage_multimesh != null:
		var foliage_instance := MultiMeshInstance3D.new()
		foliage_instance.name = "InstancedFoliage"
		foliage_instance.multimesh = foliage_multimesh
		plant_root.add_child(foliage_instance)

	var height := maxf(0.5, float(description["bounds"]["height_m"]))
	var radius := maxf(0.4, float(description["canopy"]["radius_xz_m"]))
	camera.position = Vector3(maxf(2.0, radius * 4.2), height * 0.55, maxf(3.0, height * 1.05))
	camera.look_at(Vector3(0.0, height * 0.52, 0.0), Vector3.UP)
	status_label.text = "\n".join(PackedStringArray([
		"ECO.PH5-S2 — Real 3D Tapered Branch + Instanced Foliage Lab",
		"Environment %d/%d: %s    [Q/E] environment    Profile %d/%d: %s    [A/D or arrows] profile" % [environment_index + 1, Probes.ENVIRONMENT_ORDER.size(), environment_name, profile_index + 1, PROFILE_IDS.size(), profile_id],
		"Derived presentation only — mesh tessellation and foliage instances cannot modify GrowthGraph/ecology truth",
		"growth_graph_hash=%s" % String(item["growth_graph"]["graph_hash"]),
		"render_description_hash=%s" % String(description["render_description_hash"]),
		"geometry_hash=%s" % String(built["geometry_hash"]),
		"branches=%d sides=%d vertices=%d triangles=%d foliage_instances=%d" % [int(built["branch_count"]), int(built["branch_sides"]), int(built["branch_vertex_count"]), int(built["branch_triangle_count"]), int(built["foliage_instance_count"])],
	]))
