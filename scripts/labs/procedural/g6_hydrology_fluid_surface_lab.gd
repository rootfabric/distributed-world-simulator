extends Node3D

const RiverSpline = preload("res://scripts/simulation/procedural/contracts/river_spline.gd")
const RiverChannelProfile = preload("res://scripts/simulation/procedural/contracts/river_channel_profile.gd")
const RiverFeature = preload("res://scripts/simulation/procedural/features/river_feature.gd")
const Fixture = preload("res://tests/procedural/fixtures/g6_hydrology_fixture_factory.gd")

const SAMPLE_COUNT: int = 96
const VISUAL_WIDTH_SCALE: float = 120.0


func _ready() -> void:
	var provider = Fixture.provider()
	if provider == null:
		push_error("G6 river lab failed to configure provider")
		get_tree().quit(1)
		return
	var feature: Dictionary = provider.river_feature()
	var spline: Dictionary = RiverFeature.spline(feature)
	var profile: Dictionary = RiverFeature.channel_profile(feature)
	var midpoint: Dictionary = RiverSpline.sample(spline, 0.5)
	if not bool(midpoint.get("success", false)):
		push_error("G6 river lab failed to sample midpoint")
		get_tree().quit(1)
		return
	var origin := _vector3(midpoint["details"]["position_m"])
	var up := origin.normalized()
	var flow := _vector3(midpoint["details"]["tangent"])
	flow = (flow - up * flow.dot(up)).normalized()
	var lateral := up.cross(flow).normalized()

	var mesh := ImmediateMesh.new()
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.08, 0.38, 0.82, 0.82)
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP, material)
	for index in range(SAMPLE_COUNT + 1):
		var u := float(index) / float(SAMPLE_COUNT)
		var sample: Dictionary = RiverSpline.sample(spline, u)
		var channel: Dictionary = RiverChannelProfile.sample(profile, u)
		if not bool(sample.get("success", false)) or not bool(channel.get("success", false)):
			continue
		var world := _vector3(sample["details"]["position_m"])
		var local := _lab_position(world - origin, lateral, up, flow)
		var width := float(channel["details"]["width_m"]) * VISUAL_WIDTH_SCALE
		mesh.surface_add_vertex(local + Vector3(-width * 0.5, 0.0, 0.0))
		mesh.surface_add_vertex(local + Vector3(width * 0.5, 0.0, 0.0))
	mesh.surface_end()
	var mesh_node := MeshInstance3D.new()
	mesh_node.name = "RiverRibbon"
	mesh_node.mesh = mesh
	add_child(mesh_node)

	var camera := get_node_or_null("Camera3D") as Camera3D
	if camera != null:
		camera.look_at(Vector3.ZERO, Vector3.UP)
	var label := get_node_or_null("CanvasLayer/Label") as Label
	if label != null:
		label.text = "G6 Hydrology / Fluid Surface v0\nRiverFeature: %s\nFluidRegion: %s\nLength: %.1f km\nCanonical width: %.0f -> %.0f m\nBlue ribbon width is presentation-exaggerated x%.0f" % [
			String(feature["feature_id"]).substr(0, 34),
			String(provider.fluid_surface_descriptor()["fluid_region_id"]).substr(0, 34),
			float(midpoint["details"]["total_length_m"]) / 1000.0,
			float(profile["width_source_m"]),
			float(profile["width_mouth_m"]),
			VISUAL_WIDTH_SCALE,
		]
	print("G6 hydrology visual lab: PASS feature=%s region=%s manifest=%s" % [
		String(feature["feature_id"]),
		String(provider.fluid_surface_descriptor()["fluid_region_id"]),
		String(provider.manifest_hash()),
	])


func _lab_position(delta: Vector3, lateral: Vector3, up: Vector3, flow: Vector3) -> Vector3:
	return Vector3(delta.dot(lateral), delta.dot(up), -delta.dot(flow))


func _vector3(value: Array) -> Vector3:
	return Vector3(float(value[0]), float(value[1]), float(value[2]))
