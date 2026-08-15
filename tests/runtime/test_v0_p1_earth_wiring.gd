extends SceneTree

const P1_RUNTIME_PATH := "res://scripts/app/earth_p1_app.gd"
const WORLD_CATALOG_PATH := "res://config/worlds/catalog.json"
const EarthItemSpatialProjector = preload(
	"res://scripts/runtime/networked_gameplay/i2s/earth_item_spatial_projector.gd"
)
const WorldItemTarget = preload(
	"res://scripts/runtime/networked_gameplay/i2s/canonical_world_item_target.gd"
)

var assertions := 0
var failures: Array[String] = []


class FakeEarthWorld:
	extends RefCounted
	var render_origin := Vector3.ZERO

	func get_surface_point(direction: Vector3) -> Vector3:
		return direction.normalized() * 100.0

	func world_to_render(world_position: Vector3) -> Vector3:
		return world_position - render_origin

	func get_canonical_spawn_direction() -> Vector3:
		return Vector3.UP


func _init() -> void:
	_test_runtime_compiles_and_is_routed()
	_test_projector_tracks_moving_render_origin()
	_test_interaction_target_is_non_blocking_area()
	_finish()


func _test_runtime_compiles_and_is_routed() -> void:
	var runtime_script = load(P1_RUNTIME_PATH)
	_assert(runtime_script != null, "Earth V0-P1 runtime script loads")
	_assert(runtime_script != null and runtime_script.can_instantiate(), "Earth V0-P1 runtime script can instantiate")
	if runtime_script != null and runtime_script.can_instantiate():
		var runtime = runtime_script.new()
		_assert(runtime.has_method("attach_m3_multiplayer_client"), "P1 runtime preserves M3 client attach contract")
		_assert(runtime.has_method("_command_i2s_player_interact"), "P1 runtime exposes canonical player interaction handler")
		_assert(runtime.has_method("create_m3_graphical_client_report"), "P1 runtime extends graphical report contract")
		runtime.free()

	var catalog_text := FileAccess.get_file_as_string(WORLD_CATALOG_PATH)
	var parsed = JSON.parse_string(catalog_text)
	_assert(parsed is Dictionary, "world catalog remains valid JSON")
	var earth_runtime := ""
	if parsed is Dictionary:
		for world_value in Dictionary(parsed).get("worlds", []):
			if world_value is Dictionary and String(world_value.get("id", "")) == "earth":
				earth_runtime = String(world_value.get("runtime_script", ""))
				break
	_assert(earth_runtime == P1_RUNTIME_PATH, "Earth catalog routes network MVP through V0-P1 runtime")


func _test_projector_tracks_moving_render_origin() -> void:
	var earth := FakeEarthWorld.new()
	var projector = EarthItemSpatialProjector.new()
	_assert(
		bool(projector.setup(earth, Vector3.UP).get("success", false)),
		"Earth item spatial projector configures"
	)
	var canonical := Transform3D(Basis.IDENTITY, Vector3(2.0, 1.0, -3.0))
	var first: Dictionary = projector.project_transform(canonical)
	_assert(bool(first.get("success", false)), "projector resolves canonical tangent transform")
	var first_value = first.get("details", {}).get("transform")
	_assert(typeof(first_value) == TYPE_TRANSFORM3D, "projector returns render Transform3D")
	var render_shift := Vector3(11.0, -7.0, 5.0)
	earth.render_origin = render_shift
	var second: Dictionary = projector.project_transform(canonical)
	_assert(bool(second.get("success", false)), "projector resolves after render-origin movement")
	var second_value = second.get("details", {}).get("transform")
	_assert(typeof(second_value) == TYPE_TRANSFORM3D, "second projection remains Transform3D")
	if typeof(first_value) == TYPE_TRANSFORM3D and typeof(second_value) == TYPE_TRANSFORM3D:
		var first_transform: Transform3D = first_value
		var second_transform: Transform3D = second_value
		var expected: Vector3 = first_transform.origin - render_shift
		var actual: Vector3 = second_transform.origin
		_assert(actual.distance_to(expected) < 0.0001, "moving render origin changes presentation only, not canonical transform")


func _test_interaction_target_is_non_blocking_area() -> void:
	var target = WorldItemTarget.new()
	_assert(target is Area3D, "world-item interaction target is Area3D, not blocking gameplay body")
	_assert(
		int(WorldItemTarget.INTERACTION_COLLISION_LAYER) == (1 << 19),
		"world-item interaction uses isolated client-only collision layer"
	)
	target.free()


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if condition:
		print("PASS: %s" % message)
	else:
		failures.append(message)
		push_error("FAIL: %s" % message)


func _finish() -> void:
	print("V0-P1 Earth wiring: %d assertions, %d failures" % [assertions, failures.size()])
	quit(0 if failures.is_empty() else 1)
