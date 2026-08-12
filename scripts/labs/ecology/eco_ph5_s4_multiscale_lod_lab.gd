extends Node3D

const Probes = preload("res://scripts/research/ecology/plant_render_description_probes_v1.gd")
const Representation = preload("res://scripts/research/ecology/plant_multiscale_representation_v1.gd")
const MultiscaleMaterializer = preload("res://scripts/research/ecology/plant_multiscale_materializer_v1.gd")

var environment_index := 0
var tier_index := 0
var results: Dictionary = {}
var status_label: Label
var plant_root: Node3D
var camera: Camera3D
var last_representation: Dictionary = {}
var last_materialization: Dictionary = {}
var last_truth_hash := ""

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
		tier_index = (tier_index + 1) % Representation.TIER_ORDER.size()
		_refresh()
	elif event.is_action_pressed("ui_left") or (event is InputEventKey and event.pressed and event.keycode == KEY_A):
		tier_index = (tier_index - 1 + Representation.TIER_ORDER.size()) % Representation.TIER_ORDER.size()
		_refresh()

func _build_scene_shell() -> void:
	plant_root = Node3D.new()
	plant_root.name = "PlantRepresentation"
	add_child(plant_root)

	camera = Camera3D.new()
	camera.name = "Camera3D"
	camera.current = true
	camera.fov = 50.0
	add_child(camera)

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50.0, -25.0, 0.0)
	light.shadow_enabled = true
	add_child(light)

	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-20.0, 145.0, 0.0)
	fill.light_energy = 0.35
	add_child(fill)

	var ground_mesh := PlaneMesh.new()
	ground_mesh.size = Vector2(20.0, 20.0)
	var ground := MeshInstance3D.new()
	ground.mesh = ground_mesh
	var ground_material := StandardMaterial3D.new()
	ground_material.albedo_color = Color(0.08, 0.10, 0.08)
	ground.material_override = ground_material
	add_child(ground)

	var canvas := CanvasLayer.new()
	add_child(canvas)
	status_label = Label.new()
	status_label.position = Vector2(14.0, 12.0)
	status_label.size = Vector2(1240.0, 230.0)
	status_label.add_theme_font_size_override("font_size", 16)
	canvas.add_child(status_label)

func _refresh() -> void:
	if results.is_empty() or plant_root == null:
		return
	for child in plant_root.get_children():
		child.free()

	var environment_name := Probes.ENVIRONMENT_ORDER[environment_index]
	var tier: String = Representation.TIER_ORDER[tier_index]
	var item: Dictionary = results[environment_name]
	var description: Dictionary = item["render_description"]
	last_truth_hash = String(item["growth_graph"]["graph_hash"])
	last_representation = Representation.build(description, tier)
	last_materialization = MultiscaleMaterializer.build(description, last_representation)
	if not bool(last_representation.get("success", false)) or not bool(last_materialization.get("success", false)):
		status_label.text = "ECO.PH5-S4 multiscale materialization failed"
		return

	_materialize_nodes(tier, last_materialization)
	var height := maxf(0.5, float(description["bounds"]["height_m"]))
	var radius := maxf(0.4, float(description["bounds"]["radius_xz_m"]))
	var distance_scale := [1.0, 1.8, 3.2, 7.0, 12.0][tier_index]
	var distance := maxf(3.0, maxf(height, radius * 2.0) * 1.15 * distance_scale)
	camera.position = Vector3(distance * 0.55, height * 0.60, distance)
	camera.look_at(Vector3(0.0, height * 0.50, 0.0), Vector3.UP)

	status_label.text = "\n".join(PackedStringArray([
		"ECO.PH5-S4 — Multi-scale LOD / Truth-Invariance Lab",
		"Environment %d/%d: %s    [Q/E] environment    Tier %d/%d: %s    [A/D or arrows] tier" % [environment_index + 1, Probes.ENVIRONMENT_ORDER.size(), environment_name, tier_index + 1, Representation.TIER_ORDER.size(), tier],
		"FULL -> REDUCED -> CANOPY -> IMPOSTOR -> POPULATION_ONLY; representation is derived and cannot mutate ecology truth",
		"growth_graph_hash=%s" % last_truth_hash,
		"render_description_hash=%s" % String(description["render_description_hash"]),
		"representation_hash=%s" % String(last_representation["representation_hash"]),
		"materialization_hash=%s" % String(last_materialization["materialization_hash"]),
		"cost_units=%d branches=%d foliage=%d far_primitives=%d individual_node_required=%s" % [int(last_representation["cost_units"]), int(last_materialization["branch_primitive_count"]), int(last_materialization["foliage_instance_count"]), int(last_materialization["far_primitive_count"]), str(bool(last_materialization["individual_node_required"]))],
	]))

func _materialize_nodes(tier: String, built: Dictionary) -> void:
	var branch_mesh: ArrayMesh = built.get("branch_mesh")
	if branch_mesh != null:
		var branches := MeshInstance3D.new()
		branches.name = "Branches"
		branches.mesh = branch_mesh
		var branch_material := StandardMaterial3D.new()
		branch_material.albedo_color = Color(0.38, 0.24, 0.12)
		branch_material.roughness = 0.86
		branches.material_override = branch_material
		plant_root.add_child(branches)

	var foliage: MultiMesh = built.get("foliage_multimesh")
	if foliage != null:
		var leaves := MultiMeshInstance3D.new()
		leaves.name = "Foliage"
		leaves.multimesh = foliage
		plant_root.add_child(leaves)

	var far_mesh: Mesh = built.get("far_mesh")
	if far_mesh != null:
		var far_instance := MeshInstance3D.new()
		far_instance.name = "Canopy" if tier == Representation.TIER_2_CANOPY else "Impostor"
		far_instance.mesh = far_mesh
		far_instance.position = built.get("origin", Vector3.ZERO)
		if tier == Representation.TIER_2_CANOPY:
			var canopy_material := StandardMaterial3D.new()
			canopy_material.albedo_color = Color(0.18, 0.55, 0.22)
			canopy_material.roughness = 0.90
			far_instance.material_override = canopy_material
		elif far_mesh.material is StandardMaterial3D:
			(far_mesh.material as StandardMaterial3D).albedo_color = Color(0.22, 0.62, 0.25)
		plant_root.add_child(far_instance)
