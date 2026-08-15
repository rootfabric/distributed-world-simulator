extends SceneTree

const SCENE_PATH := "res://scenes/labs/ecology/eco_vis1_0_visual_proving_ground.tscn"
const EXPECTED_SIZE_M := 500.0
const EXPECTED_MARKERS := 5

var _assertions := 0
var _failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed: PackedScene = load(SCENE_PATH) as PackedScene
	_expect(packed != null, "VIS1.0 scene loads")
	if packed == null:
		_finish()
		return

	var lab: Node3D = packed.instantiate() as Node3D
	_expect(lab != null, "VIS1.0 scene instantiates")
	if lab == null:
		_finish()
		return
	get_root().add_child(lab)
	await process_frame

	var terrain_mesh_instance := lab.get_node_or_null("Terrain/TerrainMesh") as MeshInstance3D
	_expect(terrain_mesh_instance != null, "terrain mesh is materialized")
	if terrain_mesh_instance != null:
		var mesh := terrain_mesh_instance.mesh as ArrayMesh
		_expect(mesh != null, "terrain uses ArrayMesh")
		if mesh != null:
			_expect(mesh.get_surface_count() == 1, "terrain has one deterministic surface")
			var aabb: AABB = mesh.get_aabb()
			_expect(aabb.size.x >= EXPECTED_SIZE_M - 0.01, "terrain spans 500m on X")
			_expect(aabb.size.z >= EXPECTED_SIZE_M - 0.01, "terrain spans 500m on Z")
			_expect(aabb.size.y > 10.0, "terrain has meaningful relief")

	var bounds_value: Variant = lab.call("get_polygon_bounds")
	_expect(typeof(bounds_value) == TYPE_RECT2, "polygon bounds are exposed")
	if typeof(bounds_value) == TYPE_RECT2:
		var bounds: Rect2 = bounds_value
		_expect(is_equal_approx(bounds.size.x, EXPECTED_SIZE_M), "polygon bounds width is 500m")
		_expect(is_equal_approx(bounds.size.y, EXPECTED_SIZE_M), "polygon bounds depth is 500m")

	var height_a: float = float(lab.call("sample_terrain_height", 73.25, -41.5))
	var height_b: float = float(lab.call("sample_terrain_height", 73.25, -41.5))
	var height_c: float = float(lab.call("sample_terrain_height", -180.0, -150.0))
	_expect(is_finite(height_a), "terrain sample is finite")
	_expect(is_equal_approx(height_a, height_b), "terrain sampling is deterministic")
	_expect(not is_equal_approx(height_a, height_c), "terrain contains spatial variation")

	var camera := lab.get_node_or_null("Camera3D") as Camera3D
	_expect(camera != null, "operator camera exists")
	if camera != null:
		_expect(camera.is_current(), "operator camera is current")
		_expect(camera.position.y > float(lab.call("sample_terrain_height", camera.position.x, camera.position.z)), "operator camera starts above terrain")

	var markers := lab.get_node_or_null("ReferenceMarkers") as Node3D
	_expect(markers != null, "reference marker root exists")
	if markers != null:
		_expect(markers.get_child_count() == EXPECTED_MARKERS, "five bounded-lab reference markers materialize")

	_expect(lab.get_node_or_null("HUD/Margin/Panel/VBox/Status") is Label, "numerical position HUD exists")
	_expect(lab.get_node_or_null("HUD/Margin/Panel/VBox/Controls") is Label, "operator controls HUD exists")

	lab.queue_free()
	await process_frame
	_finish()


func _expect(condition: bool, message: String) -> void:
	_assertions += 1
	if condition:
		return
	_failures += 1
	push_error("ECO.VIS1.0 assertion failed: %s" % message)


func _finish() -> void:
	if _failures == 0:
		print("ECO.VIS1.0 headless scene smoke: PASS (%d assertions)" % _assertions)
		quit(0)
		return
	print("ECO.VIS1.0 headless scene smoke: FAIL (%d assertions, %d failures)" % [_assertions, _failures])
	quit(1)
