extends SceneTree

const EnvironmentSample = preload("res://scripts/research/ecology/environment_sample_v1.gd")
const Provider = preload("res://scripts/labs/ecology/lab_environment_provider.gd")
const SCENE_PATH := "res://scenes/labs/ecology/eco_vis1_1_environment_proving_ground.tscn"

var _assertions := 0
var _failures := 0

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var provider = Provider.new(73191)
	var wet := provider.sample(Vector3(0.0, 0.0, provider.sample_water_center_z(0.0)))
	var dry := provider.sample(Vector3(-210.0, 20.0, -210.0))
	_expect(bool(EnvironmentSample.validate(wet).get("success", false)), "provider returns canonical EnvironmentSample")
	_expect(wet == provider.sample(Vector3(0.0, 0.0, provider.sample_water_center_z(0.0))), "same seed and position are deterministic")
	_expect(float(wet["soil_moisture"]) > float(dry["soil_moisture"]), "water gradient produces wetter ground")
	_expect(float(wet["flood_frequency"]) > float(dry["flood_frequency"]), "water gradient produces flood contrast")
	_expect(String(wet["environment_revision"]) == Provider.ENVIRONMENT_REVISION, "environment revision is explicit")
	var other = Provider.new(73192).sample(Vector3(80.0, 4.0, -60.0))
	var base = provider.sample(Vector3(80.0, 4.0, -60.0))
	_expect(String(other["checksum"]) != String(base["checksum"]), "seed participates in deterministic sample identity")
	var grid_valid := true
	for z_index in range(11):
		for x_index in range(11):
			var x := lerpf(-250.0, 250.0, float(x_index) / 10.0)
			var z := lerpf(-250.0, 250.0, float(z_index) / 10.0)
			var probe := provider.sample(Vector3(x, 30.0 * sin(x * 0.01) * cos(z * 0.01), z))
			if not bool(EnvironmentSample.validate(probe).get("success", false)):
				grid_valid = false
	_expect(grid_valid, "provider remains canonical across polygon grid")
	var packed := load(SCENE_PATH) as PackedScene
	_expect(packed != null, "VIS1.1 scene loads")
	if packed == null:
		_finish()
		return
	var lab := packed.instantiate() as Node3D
	_expect(lab != null, "VIS1.1 scene instantiates")
	if lab == null:
		_finish()
		return
	get_root().add_child(lab)
	await process_frame
	var sample: Dictionary = lab.call("sample_environment_at", 25.0, 15.0)
	_expect(bool(EnvironmentSample.validate(sample).get("success", false)), "scene exposes valid environment sampling")
	var sample_again: Dictionary = lab.call("sample_environment_at", 25.0, 15.0)
	_expect(String(sample["checksum"]) == String(sample_again["checksum"]), "scene environment sampling is deterministic")
	var context: Dictionary = lab.call("sample_environment_context_at", 25.0, 15.0)
	_expect(context.has("altitude_m") and context.has("slope_degrees") and context.has("water_distance_m") and context.has("water_availability"), "surface diagnostics preserve non-v1 causal fields")
	_expect(float(context["slope_degrees"]) >= 0.0 and is_finite(float(context["slope_degrees"])), "terrain slope diagnostic is finite")
	_expect(float(context["water_distance_m"]) >= 0.0, "water distance diagnostic is nonnegative")
	var terrain := lab.get_node_or_null("Terrain/TerrainMesh") as MeshInstance3D
	_expect(terrain != null and terrain.mesh != null, "environment-colored terrain materializes")
	if terrain != null and terrain.mesh is ArrayMesh:
		var arrays := (terrain.mesh as ArrayMesh).surface_get_arrays(0)
		var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
		_expect(colors.size() > 100, "terrain carries derived environment vertex colors")
		if colors.size() > 1:
			var distinct := false
			var first := colors[0]
			for color in colors:
				if absf(color.r - first.r) + absf(color.g - first.g) + absf(color.b - first.b) > 0.02:
					distinct = true
					break
			_expect(distinct, "environment vertex colors contain spatial contrast")
	var water_axis := lab.get_node_or_null("EnvironmentReferences/WaterGradientAxis") as MeshInstance3D
	_expect(water_axis != null and water_axis.mesh != null, "water gradient reference materializes")
	var status := lab.get_node_or_null("HUD/Margin/Panel/VBox/Status") as Label
	_expect(status != null and status.text.contains("moisture=") and status.text.contains("nutrients=") and status.text.contains("water_dist="), "HUD exposes causal environment sample")
	lab.queue_free()
	await process_frame
	_finish()

func _expect(condition: bool, message: String) -> void:
	_assertions += 1
	if condition:
		return
	_failures += 1
	push_error("ECO.VIS1.1 assertion failed: %s" % message)

func _finish() -> void:
	if _failures == 0:
		print("ECO.VIS1.1 headless scene smoke: PASS (%d assertions)" % _assertions)
		quit(0)
		return
	print("ECO.VIS1.1 headless scene smoke: FAIL (%d assertions, %d failures)" % [_assertions, _failures])
	quit(1)
