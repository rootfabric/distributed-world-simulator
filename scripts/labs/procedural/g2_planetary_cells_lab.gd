extends Node3D

const PlanetDefinition = preload("res://scripts/simulation/procedural/contracts/planet_definition.gd")
const BodyFixedPosition = preload("res://scripts/simulation/procedural/contracts/body_fixed_position.gd")
const SurfaceCellKey = preload("res://scripts/simulation/procedural/contracts/surface_cell_key.gd")
const SurfaceLodPolicy = preload("res://scripts/simulation/procedural/contracts/surface_lod_policy.gd")
const CubeSphereAddressing = preload("res://scripts/simulation/procedural/surface/cube_sphere_addressing.gd")
const SurfaceLodSelector = preload("res://scripts/simulation/procedural/surface/surface_lod_selector.gd")
const SurfaceCellLifecycle = preload("res://scripts/simulation/procedural/surface/surface_cell_lifecycle.gd")

const BODY_ID := "body/procedural-g2-lab"
const RECIPE_ID := "planet-recipe/g2-lab"
const SHAPE_ID := "body-shape/sphere-v1"
const MANIFEST_VERSION := "1.0.0"
const RADIUS_M := 6000000.0
const GRID_OFFSET_M := 25.0
const EDGE_SEGMENTS := 6
const UPDATE_INTERVAL_S := 0.12

@onready var camera: Camera3D = $Camera3D
@onready var grid_mesh_instance: MeshInstance3D = $Grid
@onready var hud: Label = $HUD/Panel/Margin/VBox/Status

var addressing = CubeSphereAddressing.new()
var selector = SurfaceLodSelector.new()
var lifecycle = SurfaceCellLifecycle.new()
var previous_leaves: Array = []
var update_accumulator: float = UPDATE_INTERVAL_S
var line_material: StandardMaterial3D


func _ready() -> void:
	var definition := PlanetDefinition.create(BODY_ID, 2026080803, RECIPE_ID, SHAPE_ID, RADIUS_M, MANIFEST_VERSION)
	var policy := SurfaceLodPolicy.create(0, 8, 0.45, 0.30, 10.0, 1024)
	var configured: Dictionary = selector.configure(definition, policy)
	if not bool(configured.get("success", false)):
		push_error("G2 lab selector configure failed: %s" % configured.get("error_code", ""))
		set_process(false)
		return
	camera.position = Vector3(RADIUS_M + 5000000.0, RADIUS_M * 0.12, RADIUS_M * 0.18)
	camera.look_at(Vector3.ZERO, Vector3.UP)
	camera.near = 1.0
	camera.far = 40000000.0
	line_material = StandardMaterial3D.new()
	line_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	line_material.vertex_color_use_as_albedo = true
	_refresh_selection()


func _process(delta: float) -> void:
	_update_camera(delta)
	update_accumulator += delta
	if update_accumulator >= UPDATE_INTERVAL_S:
		update_accumulator = 0.0
		_refresh_selection()


func _update_camera(delta: float) -> void:
	var position: Vector3 = camera.position
	var radial: Vector3 = position.normalized()
	var altitude_m: float = maxf(position.length() - RADIUS_M, 0.0)
	var radial_speed: float = clampf(maxf(250.0, altitude_m * 0.7), 250.0, 5000000.0)
	if Input.is_key_pressed(KEY_W):
		position -= radial * radial_speed * delta
	if Input.is_key_pressed(KEY_S):
		position += radial * radial_speed * delta
	var orbit_speed: float = deg_to_rad(18.0) * delta
	if Input.is_key_pressed(KEY_A):
		position = Basis(Vector3.UP, orbit_speed) * position
	if Input.is_key_pressed(KEY_D):
		position = Basis(Vector3.UP, -orbit_speed) * position
	var east: Vector3 = Vector3.UP.cross(radial)
	if east.length_squared() > 0.000000001:
		east = east.normalized()
		if Input.is_key_pressed(KEY_Q):
			position = Basis(east, -orbit_speed) * position
		if Input.is_key_pressed(KEY_E):
			position = Basis(east, orbit_speed) * position
	var minimum_radius: float = RADIUS_M + 2.0
	if position.length() < minimum_radius:
		position = position.normalized() * minimum_radius
	camera.position = position
	camera.look_at(Vector3.ZERO, Vector3.UP)


func _refresh_selection() -> void:
	var observer := BodyFixedPosition.create(BODY_ID, [camera.position.x, camera.position.y, camera.position.z])
	var selected: Dictionary = selector.select_cells(observer, previous_leaves)
	if not bool(selected.get("success", false)):
		push_error("G2 lab selection failed: %s" % selected.get("error_code", ""))
		return
	var leaves: Array = selected["details"]["leaves"]
	var reconciled: Dictionary = lifecycle.reconcile(leaves)
	if not bool(reconciled.get("success", false)):
		push_error("G2 lab lifecycle failed: %s" % reconciled.get("error_code", ""))
		return
	# New cover becomes active before old cover is freed.
	for record in lifecycle.snapshot():
		if String(record["state"]) == SurfaceCellLifecycle.STATE_REQUESTED:
			lifecycle.begin_build(record["cell"])
			lifecycle.activate(record["cell"])
	for record in lifecycle.snapshot():
		if String(record["state"]) == SurfaceCellLifecycle.STATE_RETIRING:
			lifecycle.complete_retire(record["cell"])
	previous_leaves = leaves
	_rebuild_grid(lifecycle.snapshot())
	var altitude_m: float = camera.position.length() - RADIUS_M
	hud.text = "Altitude: %.0f m\nLeaves: %d / 1024\nMax LOD: %d\nSelection: %s" % [
		altitude_m,
		int(selected["details"]["leaf_count"]),
		int(selected["details"]["max_selected_lod"]),
		String(selected["details"]["selection_hash"]).left(12),
	]


func _rebuild_grid(records: Array) -> void:
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES, line_material)
	for record in records:
		if String(record["state"]) != SurfaceCellLifecycle.STATE_ACTIVE:
			continue
		var cell: Dictionary = record["cell"]
		var lod: int = int(cell["lod"])
		var color := Color.from_hsv(fposmod(float(lod) * 0.115, 1.0), 0.85, 1.0, 1.0)
		var bounds_result: Dictionary = addressing.cell_uv_bounds(cell)
		if not bool(bounds_result.get("success", false)):
			continue
		var bounds: Dictionary = bounds_result["details"]
		_add_edge(mesh, String(cell["face"]), float(bounds["u_min"]), float(bounds["v_min"]), float(bounds["u_max"]), float(bounds["v_min"]), color)
		_add_edge(mesh, String(cell["face"]), float(bounds["u_max"]), float(bounds["v_min"]), float(bounds["u_max"]), float(bounds["v_max"]), color)
		_add_edge(mesh, String(cell["face"]), float(bounds["u_max"]), float(bounds["v_max"]), float(bounds["u_min"]), float(bounds["v_max"]), color)
		_add_edge(mesh, String(cell["face"]), float(bounds["u_min"]), float(bounds["v_max"]), float(bounds["u_min"]), float(bounds["v_min"]), color)
	mesh.surface_end()
	grid_mesh_instance.mesh = mesh


func _add_edge(mesh: ImmediateMesh, face: String, u0: float, v0: float, u1: float, v1: float, color: Color) -> void:
	var previous: Vector3
	for index in range(EDGE_SEGMENTS + 1):
		var t: float = float(index) / float(EDGE_SEGMENTS)
		var u: float = lerpf(u0, u1, t)
		var v: float = lerpf(v0, v1, t)
		var direction_result: Dictionary = addressing.face_uv_to_direction(face, u, v)
		if not bool(direction_result.get("success", false)):
			return
		var direction_array: Array = direction_result["details"]["direction"]
		var point := Vector3(float(direction_array[0]), float(direction_array[1]), float(direction_array[2])) * (RADIUS_M + GRID_OFFSET_M)
		if index > 0:
			mesh.surface_set_color(color)
			mesh.surface_add_vertex(previous)
			mesh.surface_set_color(color)
			mesh.surface_add_vertex(point)
		previous = point
