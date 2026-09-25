# ECO ARCH2 A10.5 / ECO-POLYGON-1 — SIMULATOR-LIKE HOST (P13, §26 portability).
# Minimal composition root that mimics a REAL simulator host: the world
# (ground/camera/light), the player stub and every world-side authority node
# ALREADY EXIST and belong to THIS host. The SAME reusable EcologyWorkbench
# (identical workbench scene as the lab) is added afterwards and its own
# ExperimentController is bound into it. The workbench must NOT create any
# world/camera/player authority of its own — scene portability contract.
# Carries ZERO biology: identical manifest/seed semantics as the polygon lab;
# every state transition stays inside the controller.
extends Node3D

const Controller = preload("res://scripts/ecology/workbench/experiment_controller_v1.gd")
const Protocol = preload("res://scripts/research/ecology/v2/observatory_protocol_v1.gd")
const Fixtures = preload("res://scripts/research/ecology/v2/body_program_fixtures_v1.gd")
const WorkbenchScene = preload("res://scenes/ecology/workbench/ecology_workbench.tscn")

# Same manifest+seed as the polygon lab (eco_arch2_polygon_lab.gd): identical
# manifest + seed must give the identical canonical state hash regardless of
# the host composition (§26: composition does not affect canonical truth).
const CELL_SIZE_MM := 1000
const FIELD_WIDTH := 3
const FIELD_DEPTH := 1

var controller: Object = null
var workbench: Node = null
var manifest: Dictionary = {}

func _ready() -> void:
	name = "EcoArch2SimulatorLikeHost"
	_build_existing_world_stub()
	_build_manifest()
	_build_controller()
	_build_workbench()

## "Existing world" stub that pre-dates the workbench: ground, camera, light
## and a player placeholder. All host-owned; the workbench adds none of these.
func _build_existing_world_stub() -> void:
	var world_root := Node3D.new()
	world_root.name = "ExistingWorld"
	add_child(world_root)

	var ground := MeshInstance3D.new()
	ground.name = "SimGround"
	var plane := PlaneMesh.new()
	plane.size = Vector2(float(FIELD_WIDTH * CELL_SIZE_MM) / 100.0, float(FIELD_DEPTH * CELL_SIZE_MM) / 100.0)
	ground.mesh = plane
	world_root.add_child(ground)

	var camera := Camera3D.new()
	camera.name = "SimCamera"
	camera.position = Vector3(15.0, 20.0, 28.0)
	world_root.add_child(camera)
	camera.make_current()

	var light := DirectionalLight3D.new()
	light.name = "SimLight"
	light.rotation_degrees = Vector3(-60.0, 15.0, 0.0)
	world_root.add_child(light)

	# Player stub: an external camera/player anchor owned by the host world.
	var player := Node3D.new()
	player.name = "PlayerStub"
	player.position = Vector3(10.0, 2.0, 12.0)
	world_root.add_child(player)

func _build_manifest() -> void:
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

func _build_controller() -> void:
	controller = Controller.new()
	var result: Dictionary = controller.initialize(manifest, {})
	if not bool(result.get("success", false)):
		push_error("ECO_SIM_LIKE_HOST controller initialize failed: " + str(result))

func _build_workbench() -> void:
	if controller == null:
		return
	workbench = WorkbenchScene.instantiate()
	workbench.name = "EcologyWorkbench"
	add_child(workbench)
	# The SAME reusable workbench receives ITS controller from the host.
	workbench.setup({
		"controller": controller,
		"founder_registry": {},
		"zone_color_provider": func(_position_mm: Array) -> Color: return Color(0.6, 0.6, 0.6),
	})
