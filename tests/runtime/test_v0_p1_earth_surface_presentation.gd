extends SceneTree

const EarthAssetLibraryScript = preload("res://scripts/world/earth/earth_asset_library.gd")

var assertions := 0
var failures: Array[String] = []


func _init() -> void:
	var assets = EarthAssetLibraryScript.new()
	assets.setup()

	var local_material = assets.get_surface_material(false)
	_assert(local_material is ShaderMaterial, "local Earth surface uses presentation shader")
	if local_material is ShaderMaterial:
		var shader := (local_material as ShaderMaterial).shader
		_assert(shader != null, "local presentation shader is assigned")
		if shader != null:
			var code := shader.code
			_assert(code.contains("macro_scale"), "shader contains macro terrain variation")
			_assert(code.contains("detail_scale"), "shader contains detail terrain variation")
			_assert(code.contains("surface_local_position"), "shader pattern is anchored to local Earth surface geometry")
			_assert(not code.contains("TIME"), "surface pattern is deterministic and does not swim with time")

	var global_material = assets.get_surface_material(true)
	_assert(global_material is StandardMaterial3D, "global orbital Earth keeps cheap standard material")

	assets.set_surface_debug_mode(true)
	if local_material is ShaderMaterial:
		_assert(
			bool((local_material as ShaderMaterial).get_shader_parameter("debug_mode")),
			"debug view bypasses decorative terrain modulation"
		)
	assets.set_surface_debug_mode(false)
	if local_material is ShaderMaterial:
		_assert(
			not bool((local_material as ShaderMaterial).get_shader_parameter("debug_mode")),
			"final surface restores decorative terrain modulation"
		)

	if failures.is_empty():
		print("V0-P1 Earth surface presentation: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("V0-P1 Earth surface presentation: FAIL (%d failures)" % failures.size())
	quit(1)


func _assert(value: bool, message: String) -> void:
	assertions += 1
	if not value:
		failures.append(message)
