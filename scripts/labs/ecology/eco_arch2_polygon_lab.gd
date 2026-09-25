# ECO ARCH2 A10.5 / ECO-POLYGON-1 — LAB HOST (P3), composition root.
# Creates the manifest (3 zones WET/DRY/DARK + 2 canonical founders),
# creates + initializes the ExperimentController, instantiates the
# reusable EcologyWorkbench and binds the controller into it. Also builds
# the test camera / light / ground with zone highlights. Carries ZERO
# biology logic: every state transition stays inside the controller.
extends Node3D

const Controller = preload("res://scripts/ecology/workbench/experiment_controller_v1.gd")
const Protocol = preload("res://scripts/research/ecology/v2/observatory_protocol_v1.gd")
const Fixtures = preload("res://scripts/research/ecology/v2/body_program_fixtures_v1.gd")
const WorkbenchScene = preload("res://scenes/ecology/workbench/ecology_workbench.tscn")

const MM_PER_SCENE_UNIT := 100.0
const ZONE_COLORS := {
	"wet": Color(0.20, 0.45, 0.85),
	"dry": Color(0.85, 0.62, 0.20),
	"dark": Color(0.45, 0.25, 0.65),
}
const CELL_SIZE_MM := 1000
const FIELD_WIDTH := 3
const FIELD_DEPTH := 1

var controller: Object = null
var workbench: Node = null  # EcologyWorkbench instance (typed via preload below)
var manifest: Dictionary = {}
var zone_bounds: Array = []

func _ready() -> void:
	name = "EcoArch2PolygonLab"
	_build_manifest()
	_build_controller()
	_build_world_visuals()
	_build_workbench()

func _build_manifest() -> void:
	# Founders are canonical genomes (A7 ancestor + A5 body-program fixture);
	# zones WET/DRY/DARK per the P3 work order.
	var founder_a := Protocol.ancestor()
	var founder_b := Fixtures.make(1)
	manifest = {
		"schema": "dws.ecology.workbench.experiment-manifest.v1",
		"experiment_id": "eco-polygon/lab-p3",
		"seed": 20260912,
		"horizon_ticks": 64,
		"founders": [
			{"founder_id": "founder/a", "biological_hash": null, "genome": founder_a},
			{"founder_id": "founder/b", "biological_hash": null, "genome": founder_b},
		],
		"environment": {
			"spatial": {"origin_mm": [0, 0, 0], "cell_size_mm": CELL_SIZE_MM, "width": FIELD_WIDTH, "depth": FIELD_DEPTH},
			"zones": [
				{"id": "wet", "water_mg": 500000, "light": 700, "temperature": 500, "nutrient_mg": 1000, "organic_mg": 0},
				{"id": "dry", "water_mg": 50000, "light": 900, "temperature": 600, "nutrient_mg": 100, "organic_mg": 0},
				{"id": "dark", "water_mg": 20000, "light": 100, "temperature": 450, "nutrient_mg": 50, "organic_mg": 0},
			],
		},
		"placement": {
			"entries": [
				{"founder_ref": "founder/a", "zone_id": "wet", "position_mm": [500, 0, 500]},
				{"founder_ref": "founder/b", "zone_id": "dry", "position_mm": [1500, 0, 500]},
			],
		},
		"mutation": {"operator": "small", "mutations_enabled": true},
		"organization_profile": "FREE",
		"feedback": {"enabled": true, "decomposition_enabled": true},
		"metrics": {"requested": ["population"]},
		"checkpoint": {"interval_ticks": 16},
		"mode": "LAB",
	}
	# Zone bands (mm) for the presentation-only color mapping.
	var zone_ids := ["wet", "dry", "dark"]
	for index in FIELD_WIDTH:
		zone_bounds.append({
			"min_x": index * CELL_SIZE_MM,
			"max_x": (index + 1) * CELL_SIZE_MM,
			"zone_id": zone_ids[mini(zone_ids.size() - 1, index * zone_ids.size() / FIELD_WIDTH)],
		})

func _build_controller() -> void:
	controller = Controller.new()
	var result: Dictionary = controller.initialize(manifest, {})
	if not bool(result.get("success", false)):
		push_error("ECO_POLYGON_LAB controller initialize failed: " + str(result))

func _build_workbench() -> void:
	if controller == null:
		return
	workbench = WorkbenchScene.instantiate()
	workbench.name = "EcologyWorkbench"
	add_child(workbench)
	workbench.setup({
		"controller": controller,
		"founder_registry": {},
		"zone_color_provider": zone_color,
	})

## Presentation-only mapping: position_mm -> zone color. No biological data.
func zone_color(position_mm: Array) -> Color:
	var x := int(position_mm[0])
	for band in zone_bounds:
		if x >= band.min_x and x < band.max_x:
			return ZONE_COLORS[band.zone_id]
	return Color(0.5, 0.5, 0.5)

# --- Test world visuals (camera/light/ground belong to the LAB host) ---------

func _build_world_visuals() -> void:
	var camera := Camera3D.new()
	camera.name = "LabCamera"
	var field_width_m := float(FIELD_WIDTH * CELL_SIZE_MM) / MM_PER_SCENE_UNIT
	var field_depth_m := float(FIELD_DEPTH * CELL_SIZE_MM) / MM_PER_SCENE_UNIT
	camera.position = Vector3(field_width_m * 0.5, 18.0, field_depth_m * 0.5 + 24.0)
	add_child(camera)
	camera.look_at(Vector3(field_width_m * 0.5, 0.0, field_depth_m * 0.5), Vector3.UP)
	camera.make_current()

	var light := DirectionalLight3D.new()
	light.name = "LabLight"
	light.rotation_degrees = Vector3(-55.0, 30.0, 0.0)
	light.light_energy = 1.2
	add_child(light)

	var ground := MeshInstance3D.new()
	ground.name = "Ground"
	var plane := PlaneMesh.new()
	plane.size = Vector2(field_width_m, field_depth_m)
	ground.mesh = plane
	var ground_material := StandardMaterial3D.new()
	ground_material.albedo_color = Color(0.12, 0.16, 0.12)
	ground.material_override = ground_material
	add_child(ground)

	# Zone highlight quads: one per zone cell, three colors, presentation only.
	for index in FIELD_WIDTH:
		var quad := MeshInstance3D.new()
		quad.name = "ZoneHighlight%d" % index
		var quad_mesh := PlaneMesh.new()
		quad_mesh.size = Vector2(float(CELL_SIZE_MM) / MM_PER_SCENE_UNIT, field_depth_m)
		quad.mesh = quad_mesh
		var zone_id: String = zone_bounds[index].zone_id
		var quad_material := StandardMaterial3D.new()
		var color: Color = ZONE_COLORS[zone_id]
		quad_material.albedo_color = Color(color.r, color.g, color.b, 0.35)
		quad_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		quad_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		quad.material_override = quad_material
		quad.position = Vector3(
			(index + 0.5) * float(CELL_SIZE_MM) / MM_PER_SCENE_UNIT,
			0.02,
			field_depth_m * 0.5
		)
		add_child(quad)
