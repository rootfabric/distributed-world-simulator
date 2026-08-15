extends "res://scripts/labs/ecology/eco_vis1_0_visual_proving_ground.gd"

const EnvironmentSample = preload("res://scripts/research/ecology/environment_sample_v1.gd")
const LabEnvironmentProvider = preload("res://scripts/labs/ecology/lab_environment_provider.gd")
const VIS1_1_STAGE := "ECO.VIS1.1"
const ENVIRONMENT_SEED := 73191

var _environment_provider: RefCounted

func _ready() -> void:
	_environment_provider = LabEnvironmentProvider.new(ENVIRONMENT_SEED)
	super._ready()
	$HUD/Margin/Panel/VBox/Title.text = "ECO.VIS1.1 — Causal Environment Proving Ground"
	_build_water_reference()
	_controls_label.text = "WASD move | Q/E down/up | Shift boost | mouse look | Esc capture | Home reset\nTerrain colors are derived from moisture + nutrients; blue ribbon = water gradient axis"
	_update_status()

func sample_environment_at(x: float, z: float) -> Dictionary:
	var y := sample_terrain_height(x, z)
	return _environment_provider.sample(Vector3(x, y, z))

func sample_environment_context_at(x: float, z: float) -> Dictionary:
	var y := sample_terrain_height(x, z)
	return _environment_provider.sample_context(Vector3(x, y, z), sample_terrain_slope_degrees(x, z))

func sample_terrain_slope_degrees(x: float, z: float) -> float:
	const DELTA_M := 1.0
	var dx := 0.5 * (sample_terrain_height(x + DELTA_M, z) - sample_terrain_height(x - DELTA_M, z)) / DELTA_M
	var dz := 0.5 * (sample_terrain_height(x, z + DELTA_M) - sample_terrain_height(x, z - DELTA_M)) / DELTA_M
	return rad_to_deg(atan(Vector2(dx, dz).length()))

func get_environment_provider() -> RefCounted:
	return _environment_provider

func _add_terrain_vertex(surface: SurfaceTool, point: Vector3) -> void:
	var sample: Dictionary = _environment_provider.sample(point)
	var moisture := float(sample["soil_moisture"])
	var nutrients := float(sample["nutrients"])
	var flood := float(sample["flood_frequency"])
	var dry_color := Color(0.42, 0.33, 0.16)
	var moist_color := Color(0.13, 0.42, 0.20)
	var fertile_color := Color(0.18, 0.56, 0.23)
	var flood_color := Color(0.08, 0.28, 0.34)
	var color := dry_color.lerp(moist_color, moisture)
	color = color.lerp(fertile_color, nutrients * 0.48)
	color = color.lerp(flood_color, flood * 0.64)
	surface.set_color(color)
	surface.set_uv(Vector2((point.x + TERRAIN_HALF_M) / TERRAIN_SIZE_M, (point.z + TERRAIN_HALF_M) / TERRAIN_SIZE_M))
	surface.add_vertex(point)

func _build_water_reference() -> void:
	var root := Node3D.new()
	root.name = "EnvironmentReferences"
	add_child(root)
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.08, 0.42, 0.70, 0.72)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.roughness = 0.32
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	surface.set_material(material)
	const SEGMENTS := 80
	const HALF_WIDTH_M := 2.4
	for index in range(SEGMENTS):
		var x0 := lerpf(-TERRAIN_HALF_M, TERRAIN_HALF_M, float(index) / float(SEGMENTS))
		var x1 := lerpf(-TERRAIN_HALF_M, TERRAIN_HALF_M, float(index + 1) / float(SEGMENTS))
		var z0 := float(_environment_provider.call("sample_water_center_z", x0))
		var z1 := float(_environment_provider.call("sample_water_center_z", x1))
		var p00 := Vector3(x0, sample_terrain_height(x0, z0 - HALF_WIDTH_M) + 0.18, z0 - HALF_WIDTH_M)
		var p01 := Vector3(x0, sample_terrain_height(x0, z0 + HALF_WIDTH_M) + 0.18, z0 + HALF_WIDTH_M)
		var p10 := Vector3(x1, sample_terrain_height(x1, z1 - HALF_WIDTH_M) + 0.18, z1 - HALF_WIDTH_M)
		var p11 := Vector3(x1, sample_terrain_height(x1, z1 + HALF_WIDTH_M) + 0.18, z1 + HALF_WIDTH_M)
		surface.add_vertex(p00)
		surface.add_vertex(p01)
		surface.add_vertex(p10)
		surface.add_vertex(p10)
		surface.add_vertex(p01)
		surface.add_vertex(p11)
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "WaterGradientAxis"
	mesh_instance.mesh = surface.commit()
	root.add_child(mesh_instance)

func _update_status() -> void:
	if not is_instance_valid(_camera) or not is_instance_valid(_status_label) or _environment_provider == null:
		return
	var position := _camera.position
	var ground_y := sample_terrain_height(position.x, position.z)
	var context := sample_environment_context_at(position.x, position.z)
	var sample: Dictionary = context["environment"]
	var validation: Dictionary = EnvironmentSample.validate(sample)
	_status_label.text = "%s | polygon %.0f x %.0f m | seed=%d | sample=%s\nCamera x=%7.1f y=%6.1f z=%7.1f | ground=%6.1f slope=%4.1f° water_dist=%5.1fm\nT=%5.1f°C | moisture=%.3f | light=%.3f | nutrients=%.3f | flood=%.3f | water=%.3f" % [
		VIS1_1_STAGE,
		TERRAIN_SIZE_M,
		TERRAIN_SIZE_M,
		int(_environment_provider.call("get_seed")),
		"VALID" if bool(validation.get("success", false)) else "INVALID",
		position.x,
		position.y,
		position.z,
		ground_y,
		float(context["slope_degrees"]),
		float(context["water_distance_m"]),
		float(sample["temperature_c"]),
		float(sample["soil_moisture"]),
		float(sample["sunlight"]),
		float(sample["nutrients"]),
		float(sample["flood_frequency"]),
		float(context["water_availability"]),
	]
