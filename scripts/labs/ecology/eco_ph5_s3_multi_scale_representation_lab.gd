extends Node3D

const Probes = preload("res://scripts/research/ecology/plant_render_description_probes_v1.gd")
const RendererProfile = preload("res://scripts/research/ecology/plant_renderer_profile_v1.gd")
const Representation = preload("res://scripts/research/ecology/plant_multiscale_representation_v1.gd")
const FarMaterializer = preload("res://scripts/research/ecology/plant_far_representation_materializer_v1.gd")

const SEED := 530031
var tier_index := 0
var results: Dictionary = {}
var plant_root: Node3D
var status_label: Label
var camera: Camera3D
var ecology_identity := ""
var population_truth: Dictionary = {}
var source_graph_snapshot := ""
var profile: Dictionary = {}

func _ready() -> void:
	results = Probes.run_all()
	var reference: Dictionary = results["REFERENCE"]
	source_graph_snapshot = JSON.stringify(reference["growth_graph"])
	ecology_identity = "|".join(PackedStringArray([
		String(reference["phenotype_hash"]),
		String(reference["growth_graph"]["graph_hash"]),
		String(reference["render_description"]["render_description_hash"]),
	])).sha256_text()
	profile = RendererProfile.create("FULL_PROCEDURAL")
	population_truth = _population_truth_fixture()
	_build_shell()
	_refresh()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_right") or (event is InputEventKey and event.pressed and event.keycode == KEY_D):
		tier_index = (tier_index + 1) % Representation.TIER_ORDER.size()
		_refresh()
	elif event.is_action_pressed("ui_left") or (event is InputEventKey and event.pressed and event.keycode == KEY_A):
		tier_index = (tier_index - 1 + Representation.TIER_ORDER.size()) % Representation.TIER_ORDER.size()
		_refresh()
	elif event is InputEventKey and event.pressed and event.keycode >= KEY_1 and event.keycode <= KEY_5:
		tier_index = int(event.keycode - KEY_1)
		_refresh()

func _build_shell() -> void:
	plant_root = Node3D.new()
	plant_root.name = "TierRepresentation"
	add_child(plant_root)
	camera = Camera3D.new()
	camera.name = "Camera3D"
	camera.current = true
	add_child(camera)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-48.0, -25.0, 0.0)
	light.shadow_enabled = true
	add_child(light)
	var ground_mesh := PlaneMesh.new()
	ground_mesh.size = Vector2(14.0, 14.0)
	var ground := MeshInstance3D.new()
	ground.mesh = ground_mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.08, 0.10, 0.08)
	ground.material_override = material
	add_child(ground)
	var canvas := CanvasLayer.new()
	add_child(canvas)
	status_label = Label.new()
	status_label.position = Vector2(14.0, 12.0)
	status_label.size = Vector2(1250.0, 230.0)
	status_label.add_theme_font_size_override("font_size", 16)
	canvas.add_child(status_label)

func _refresh() -> void:
	if results.is_empty() or plant_root == null:
		return
	for child in plant_root.get_children():
		child.queue_free()
	var reference: Dictionary = results["REFERENCE"]
	var graph: Dictionary = reference["growth_graph"]
	var description: Dictionary = reference["render_description"]
	var tier: String = Representation.TIER_ORDER[tier_index]
	var artifact := {}
	if tier == Representation.TIER_4_POPULATION_ONLY:
		artifact = Representation.build_population(population_truth, profile, SEED)
		_add_far_visual(FarMaterializer.build(artifact), tier)
	else:
		artifact = Representation.build_individual(description, tier, ecology_identity, SEED, profile)
		if tier in [Representation.TIER_0_FULL, Representation.TIER_1_REDUCED]:
			_add_near_visual(Representation.materialize_near(description, tier, profile), tier)
		else:
			_add_far_visual(FarMaterializer.build(artifact), tier)
	var truth_unchanged := JSON.stringify(graph) == source_graph_snapshot
	var height := maxf(1.0, float(description["bounds"]["height_m"]))
	var radius := maxf(1.0, float(description["canopy"]["radius_xz_m"]))
	if tier == Representation.TIER_4_POPULATION_ONLY:
		camera.position = Vector3(0.0, 65.0, 90.0)
		camera.look_at(Vector3.ZERO, Vector3.UP)
	else:
		camera.position = Vector3(maxf(2.4, radius * 4.8), height * 0.62, maxf(3.5, height * 1.15))
		camera.look_at(Vector3(0.0, height * 0.50, 0.0), Vector3.UP)
	var metrics: Dictionary = artifact.get("metrics", {})
	status_label.text = "\n".join(PackedStringArray([
		"ECO.PH5-S3 — Multi-Scale Plant Representation Lab",
		"Tier %d/5: %s    [1..5] direct switch    [A/D or arrows] previous/next" % [tier_index + 1, _friendly_tier(tier)],
		"FULL/REDUCED/CANOPY/IMPOSTOR share one ecological source identity. POPULATION_ONLY uses aggregate population truth with zero individual GrowthGraphs.",
		"source_ecology_identity=%s" % String(artifact.get("source_ecology_identity", "")),
		"source_growth_graph_hash=%s    truth_unchanged=%s" % [String(graph["graph_hash"]), str(truth_unchanged)],
		"representation_hash=%s    renderer=%s" % [String(artifact.get("representation_hash", "")), String(artifact.get("renderer_version", ""))],
		"objects=%d primitives=%d instances=%d estimated_memory=%dB materialized_growth_graphs=%d" % [int(metrics.get("representation_object_count", 0)), int(metrics.get("geometry_primitive_count", 0)), int(metrics.get("instance_count", 0)), int(metrics.get("estimated_memory_bytes", 0)), int(metrics.get("materialized_growth_graph_count", 0))],
		"Known blocker is unchanged: FULL_POOL_COMPACT / HEIGHT_LOW dominance remains CAL1-owned.",
	]))

func _add_near_visual(built: Dictionary, tier: String) -> void:
	if built.is_empty():
		return
	var branch_mesh: ArrayMesh = built["branch_mesh"]
	if branch_mesh != null:
		var branches := MeshInstance3D.new()
		branches.name = "%s_Branches" % tier
		branches.mesh = branch_mesh
		var branch_material := StandardMaterial3D.new()
		branch_material.albedo_color = Color(0.38, 0.24, 0.12)
		branch_material.roughness = 0.86
		branches.material_override = branch_material
		plant_root.add_child(branches)
	var foliage_multimesh: MultiMesh = built["foliage_multimesh"]
	if foliage_multimesh != null:
		var foliage := MultiMeshInstance3D.new()
		foliage.name = "%s_Foliage" % tier
		foliage.multimesh = foliage_multimesh
		plant_root.add_child(foliage)

func _add_far_visual(materialized: Dictionary, tier: String) -> void:
	if not bool(materialized.get("success", false)):
		return
	var mesh: Mesh = materialized.get("mesh")
	if mesh != null:
		var instance := MeshInstance3D.new()
		instance.name = "%s_Mesh" % tier
		instance.mesh = mesh
		var origin: Vector3 = materialized["origin"]
		instance.position = origin
		if tier == Representation.TIER_2_CANOPY:
			var canopy_material := StandardMaterial3D.new()
			canopy_material.albedo_color = Color(0.18, 0.52, 0.20, 0.70)
			canopy_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			canopy_material.roughness = 1.0
			instance.material_override = canopy_material
		plant_root.add_child(instance)
	var multimesh: MultiMesh = materialized.get("multimesh")
	if multimesh != null:
		var population := MultiMeshInstance3D.new()
		population.name = "%s_AggregateSamples" % tier
		population.multimesh = multimesh
		plant_root.add_child(population)

func _population_truth_fixture() -> Dictionary:
	var truth := {
		"schema": Representation.POPULATION_SOURCE_SCHEMA,
		"patch_id": "eco/ph5-s3/lab-far-population",
		"canonical_organism_count": 1000000,
		"center": [0.0, 0.0, 0.0],
		"radius_m": 52.0,
		"mean_height_m": 2.7,
		"mean_canopy_radius_m": 0.9,
		"foliage_mass_projection": 190000.0,
		"biomass_projection_kg": 760000.0,
		"density_per_m2": 117.721000,
	}
	truth["population_truth_hash"] = Representation.compute_population_truth_hash(truth)
	return truth

func _friendly_tier(tier: String) -> String:
	return {
		Representation.TIER_0_FULL: "FULL",
		Representation.TIER_1_REDUCED: "REDUCED",
		Representation.TIER_2_CANOPY: "CANOPY",
		Representation.TIER_3_IMPOSTOR: "IMPOSTOR",
		Representation.TIER_4_POPULATION_ONLY: "POPULATION_ONLY",
	}.get(tier, tier)
