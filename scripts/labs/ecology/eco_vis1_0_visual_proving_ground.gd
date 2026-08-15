extends Node3D

const VIS1_STAGE := "ECO.VIS1.0"
const TERRAIN_SIZE_M := 500.0
const TERRAIN_HALF_M := TERRAIN_SIZE_M * 0.5
const GRID_CELLS := 64
const CAMERA_SPEED_MPS := 28.0
const CAMERA_BOOST_MULTIPLIER := 4.0
const CAMERA_MIN_CLEARANCE_M := 1.5
const CAMERA_MAX_ALTITUDE_M := 220.0
const MOUSE_SENSITIVITY := 0.0022

@onready var _terrain_root: Node3D = $Terrain
@onready var _camera: Camera3D = $Camera3D
@onready var _status_label: Label = $HUD/Margin/Panel/VBox/Status
@onready var _controls_label: Label = $HUD/Margin/Panel/VBox/Controls

var _yaw := 0.0
var _pitch := 0.0
var _mouse_captured := false
var _terrain_mesh: ArrayMesh


func _ready() -> void:
	_build_terrain()
	_build_reference_markers()
	_reset_camera()
	_set_mouse_capture(DisplayServer.get_name() != "headless")
	_controls_label.text = "WASD move | Q/E down/up | Shift boost | mouse look | Esc release/capture | Home reset"
	_update_status()


func _process(delta: float) -> void:
	_update_camera(delta)
	_update_status()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and _mouse_captured:
		var motion := event as InputEventMouseMotion
		_yaw -= motion.relative.x * MOUSE_SENSITIVITY
		_pitch = clamp(_pitch - motion.relative.y * MOUSE_SENSITIVITY, deg_to_rad(-85.0), deg_to_rad(85.0))
		_camera.rotation = Vector3(_pitch, _yaw, 0.0)
		get_viewport().set_input_as_handled()
		return

	if event is InputEventKey:
		var key_event := event as InputEventKey
		if not key_event.pressed or key_event.echo:
			return
		if key_event.keycode == KEY_ESCAPE:
			_set_mouse_capture(not _mouse_captured)
			get_viewport().set_input_as_handled()
		elif key_event.keycode == KEY_HOME:
			_reset_camera()
			get_viewport().set_input_as_handled()


func sample_terrain_height(x: float, z: float) -> float:
	var nx: float = clamp(x / TERRAIN_HALF_M, -1.0, 1.0)
	var nz: float = clamp(z / TERRAIN_HALF_M, -1.0, 1.0)
	var rolling: float = 7.5 * sin(nx * PI * 1.65) * cos(nz * PI * 1.35)
	var ridge_dx: float = (nx + 0.28) * 2.15
	var ridge_dz: float = (nz + 0.30) * 1.20
	var ridge: float = 19.0 * exp(-(ridge_dx * ridge_dx + ridge_dz * ridge_dz))
	var basin_dx: float = (nx - 0.34) * 2.20
	var basin_dz: float = (nz - 0.20) * 2.00
	var basin: float = -13.0 * exp(-(basin_dx * basin_dx + basin_dz * basin_dz))
	var broad_slope: float = 5.5 * nx - 2.0 * nz
	return rolling + ridge + basin + broad_slope


func get_polygon_bounds() -> Rect2:
	return Rect2(-TERRAIN_HALF_M, -TERRAIN_HALF_M, TERRAIN_SIZE_M, TERRAIN_SIZE_M)


func get_terrain_mesh() -> ArrayMesh:
	return _terrain_mesh


func reset_operator_camera() -> void:
	_reset_camera()


func _build_terrain() -> void:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)

	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 0.94
	material.metallic = 0.0
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	surface.set_material(material)

	var step: float = TERRAIN_SIZE_M / float(GRID_CELLS)
	for z_index in range(GRID_CELLS):
		var z0: float = -TERRAIN_HALF_M + float(z_index) * step
		var z1: float = z0 + step
		for x_index in range(GRID_CELLS):
			var x0: float = -TERRAIN_HALF_M + float(x_index) * step
			var x1: float = x0 + step
			var p00 := Vector3(x0, sample_terrain_height(x0, z0), z0)
			var p10 := Vector3(x1, sample_terrain_height(x1, z0), z0)
			var p01 := Vector3(x0, sample_terrain_height(x0, z1), z1)
			var p11 := Vector3(x1, sample_terrain_height(x1, z1), z1)
			_add_terrain_vertex(surface, p00)
			_add_terrain_vertex(surface, p01)
			_add_terrain_vertex(surface, p10)
			_add_terrain_vertex(surface, p10)
			_add_terrain_vertex(surface, p01)
			_add_terrain_vertex(surface, p11)

	surface.generate_normals()
	_terrain_mesh = surface.commit()
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "TerrainMesh"
	mesh_instance.mesh = _terrain_mesh
	_terrain_root.add_child(mesh_instance)


func _add_terrain_vertex(surface: SurfaceTool, point: Vector3) -> void:
	var height01: float = inverse_lerp(-18.0, 28.0, point.y)
	var low := Color(0.16, 0.27, 0.12)
	var mid := Color(0.24, 0.38, 0.17)
	var high := Color(0.31, 0.41, 0.22)
	var color: Color = low.lerp(mid, clamp(height01 * 1.5, 0.0, 1.0))
	if height01 > 0.66:
		color = mid.lerp(high, clamp((height01 - 0.66) / 0.34, 0.0, 1.0))
	surface.set_color(color)
	surface.set_uv(Vector2((point.x + TERRAIN_HALF_M) / TERRAIN_SIZE_M, (point.z + TERRAIN_HALF_M) / TERRAIN_SIZE_M))
	surface.add_vertex(point)


func _build_reference_markers() -> void:
	var marker_material := StandardMaterial3D.new()
	marker_material.albedo_color = Color(0.88, 0.74, 0.24)
	marker_material.roughness = 0.8

	var positions: Array[Vector2] = [
		Vector2(-TERRAIN_HALF_M, -TERRAIN_HALF_M),
		Vector2(TERRAIN_HALF_M, -TERRAIN_HALF_M),
		Vector2(-TERRAIN_HALF_M, TERRAIN_HALF_M),
		Vector2(TERRAIN_HALF_M, TERRAIN_HALF_M),
		Vector2.ZERO,
	]
	for index in range(positions.size()):
		var marker_xz: Vector2 = positions[index]
		var marker := MeshInstance3D.new()
		marker.name = "ReferenceMarker%02d" % index
		var cylinder := CylinderMesh.new()
		cylinder.top_radius = 0.32
		cylinder.bottom_radius = 0.32
		cylinder.height = 4.0 if index < 4 else 2.2
		cylinder.material = marker_material
		marker.mesh = cylinder
		var base_y: float = sample_terrain_height(marker_xz.x, marker_xz.y)
		marker.position = Vector3(marker_xz.x, base_y + cylinder.height * 0.5, marker_xz.y)
		$ReferenceMarkers.add_child(marker)


func _reset_camera() -> void:
	_camera.position = Vector3(0.0, 72.0, 145.0)
	_camera.look_at(Vector3(0.0, 4.0, 0.0), Vector3.UP)
	_pitch = _camera.rotation.x
	_yaw = _camera.rotation.y


func _set_mouse_capture(enabled: bool) -> void:
	_mouse_captured = enabled
	if DisplayServer.get_name() == "headless":
		return
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED if enabled else Input.MOUSE_MODE_VISIBLE)


func _update_camera(delta: float) -> void:
	if delta <= 0.0:
		return
	var local_motion := Vector3.ZERO
	if Input.is_key_pressed(KEY_W):
		local_motion.z -= 1.0
	if Input.is_key_pressed(KEY_S):
		local_motion.z += 1.0
	if Input.is_key_pressed(KEY_A):
		local_motion.x -= 1.0
	if Input.is_key_pressed(KEY_D):
		local_motion.x += 1.0
	if Input.is_key_pressed(KEY_Q):
		local_motion.y -= 1.0
	if Input.is_key_pressed(KEY_E):
		local_motion.y += 1.0
	if local_motion.is_zero_approx():
		return

	local_motion = local_motion.normalized()
	var speed: float = CAMERA_SPEED_MPS
	if Input.is_key_pressed(KEY_SHIFT):
		speed *= CAMERA_BOOST_MULTIPLIER
	var world_motion: Vector3 = _camera.global_transform.basis * local_motion
	_camera.global_position += world_motion * speed * delta
	_clamp_camera_to_lab()


func _clamp_camera_to_lab() -> void:
	var position := _camera.position
	position.x = clamp(position.x, -TERRAIN_HALF_M + 1.0, TERRAIN_HALF_M - 1.0)
	position.z = clamp(position.z, -TERRAIN_HALF_M + 1.0, TERRAIN_HALF_M - 1.0)
	var ground_y: float = sample_terrain_height(position.x, position.z)
	position.y = clamp(position.y, ground_y + CAMERA_MIN_CLEARANCE_M, CAMERA_MAX_ALTITUDE_M)
	_camera.position = position


func _update_status() -> void:
	if not is_instance_valid(_camera) or not is_instance_valid(_status_label):
		return
	var position := _camera.position
	var ground_y: float = sample_terrain_height(position.x, position.z)
	_status_label.text = "%s  |  polygon %.0f x %.0f m\nCamera  x=%7.1f  y=%6.1f  z=%7.1f  |  ground=%6.1f  clearance=%5.1f" % [
		VIS1_STAGE,
		TERRAIN_SIZE_M,
		TERRAIN_SIZE_M,
		position.x,
		position.y,
		position.z,
		ground_y,
		position.y - ground_y,
	]
