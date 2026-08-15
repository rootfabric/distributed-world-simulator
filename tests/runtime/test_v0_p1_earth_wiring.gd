extends SceneTree

const P1_RUNTIME_PATH := "res://scripts/app/earth_p1_modern_inventory_app.gd"
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
	extends Node3D
	var render_origin := Vector3.ZERO
	var radius_m := 100.0

	func get_surface_point(direction: Vector3) -> Vector3:
		return direction.normalized() * radius_m

	func get_render_origin() -> Vector3:
		return render_origin

	func get_canonical_spawn_direction() -> Vector3:
		return Vector3(0.3, 0.9, 0.2).normalized()


func _init() -> void:
	_test_runtime_compiles_and_is_routed()
	_test_projector_matches_mvp_axes_and_reference_frame()
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
		_assert(runtime.has_method("_ensure_mvp_inventory_shell"), "P1 runtime owns the modern inventory convergence boundary")
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
	_assert(earth_runtime == P1_RUNTIME_PATH, "Earth catalog routes network MVP through V0-P1 modern inventory runtime")


func _test_projector_matches_mvp_axes_and_reference_frame() -> void:
	var earth := FakeEarthWorld.new()
	get_root().add_child(earth)
	var anchor := earth.get_canonical_spawn_direction()
	var projector = EarthItemSpatialProjector.new()
	_assert(
		bool(projector.setup(earth, anchor).get("success", false)),
		"Earth item spatial projector configures"
	)
	var canonical := Transform3D(Basis.IDENTITY, Vector3(2.0, 1.0, -3.0))
	var first: Dictionary = projector.project_transform(canonical)
	_assert(bool(first.get("success", false)), "projector resolves canonical tangent transform")
	var first_details: Dictionary = first.get("details", {})
	var first_value = first_details.get("transform")
	_assert(typeof(first_value) == TYPE_TRANSFORM3D, "projector returns render Transform3D")

	var east := Vector3.UP.cross(anchor).normalized()
	var north := anchor.cross(east).normalized()
	var expected_direction := (
		earth.get_surface_point(anchor)
		+ east * canonical.origin.x
		- north * canonical.origin.z
	).normalized()
	var actual_direction: Vector3 = first_details.get("surface_direction", Vector3.ZERO)
	_assert(
		actual_direction.distance_to(expected_direction) < 0.000001,
		"projector uses the same +X east / -Z north convention as Earth MVP"
	)

	var world_position: Vector3 = first_details.get("world_position", Vector3.ZERO)
	var render_shift := Vector3(11.0, -7.0, 5.0)
	var frame_basis := Basis(Vector3.UP, deg_to_rad(37.0))
	earth.render_origin = render_shift
	earth.basis = frame_basis
	var second: Dictionary = projector.project_transform(canonical)
	_assert(bool(second.get("success", false)), "projector resolves after render-origin/reference-frame movement")
	var second_value = second.get("details", {}).get("transform")
	_assert(typeof(second_value) == TYPE_TRANSFORM3D, "second projection remains Transform3D")
	if typeof(second_value) == TYPE_TRANSFORM3D:
		var second_transform: Transform3D = second_value
		var expected_render_position := frame_basis * (world_position - render_shift)
		_assert(
			second_transform.origin.distance_to(expected_render_position) < 0.0001,
			"render origin and reference-frame basis affect presentation only"
		)
	var second_world_position: Vector3 = second.get("details", {}).get("world_position", Vector3.ZERO)
	_assert(
		second_world_position.distance_to(world_position) < 0.000001,
		"canonical Earth-fixed item position is invariant across presentation frame changes"
	)
	earth.queue_free()


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
