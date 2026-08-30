extends SceneTree

const RuntimeScript = preload(
	"res://scripts/world/matter/lunar_matter_bubble_runtime.gd"
)

var _assertions := 0
var _failures := 0


class FakeMoonWorld:
	extends Node3D

	var installed_adapter = null
	var prepare_calls := 0
	var last_prepare_direction := Vector3.ZERO
	var render_origin := Vector3(10.0, 20.0, 30.0)

	func get_moon_radius() -> float:
		return 1737400.0

	func get_coarse_surface_height(_direction: Vector3) -> float:
		return 25.0

	func set_matter_surface_adapter(adapter) -> Dictionary:
		installed_adapter = adapter
		return {"success": true, "error_code": "", "details": {}}

	func prepare_surface_region(direction: Vector3, _include_collision: bool = true) -> void:
		prepare_calls += 1
		last_prepare_direction = direction

	func world_to_render(world_position: Vector3) -> Vector3:
		return world_position - render_origin


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_runtime_wiring_and_rollback()
	_test_production_hook_guards()
	print("V0-P7.2 lunar surface seam: PASS (%d assertions, %d failures)" % [
		_assertions, _failures,
	])
	quit(0 if _failures == 0 else 1)


func _test_runtime_wiring_and_rollback() -> void:
	var moon := FakeMoonWorld.new()
	moon.name = "FakeMoonWorld"
	get_root().add_child(moon)
	var runtime = RuntimeScript.new()
	runtime.name = "P7LunarMatterBubbleRuntime"
	get_root().add_child(runtime)
	var result: Dictionary = runtime.configure(moon, {
		"anchor_direction": [0.0, 1.0, 0.0],
		"half_extent_m": 16.0,
		"legacy_mask_radius_m": 8.0,
		"legacy_center_tolerance_m": 2.0,
		"mutation_level": 2,
		"presentation_level": 1,
		"max_level": 2,
		"brick_interior_resolution": 6,
		"ghost_border_samples": 1,
		"build_collision": true,
		"rebuild_legacy_surface": true,
	})
	_assert_success(result, "runtime configure")
	if not bool(result.get("success", false)):
		runtime.queue_free()
		moon.queue_free()
		return
	var bubble = runtime.bubble()
	var adapter = runtime.legacy_adapter()
	var presenter = runtime.presenter()
	_assert_true(String(bubble.body_definition().get("body_id", "")) == "body/moon", "runtime keeps Moon identity")
	_assert_true(
		absf(float(bubble.surface_radius_m()) - 1737425.0) < 0.000001,
		"runtime freezes stable coarse legacy height into canonical profile"
	)
	_assert_true(moon.installed_adapter == adapter, "legacy route adapter installed on Moon")
	_assert_true(moon.prepare_calls == 1, "legacy local surface rebuilt once with center mask")
	_assert_true(moon.last_prepare_direction.is_equal_approx(Vector3.UP), "fixed bubble anchor rebuild")
	_assert_true(
		absf(float(adapter.legacy_local_inner_radius_m(Vector3.UP)) - 8.0) < 0.000001,
		"legacy center hole exactly matches configured bubble mask"
	)
	_assert_true(presenter.presenter_count() > 0, "Matter mesh presenters created")
	var presenter_contract: Dictionary = presenter.contract_report()
	_assert_true(String(presenter_contract.get("geometry_source", "")) == "MATTER_SNAPSHOT", "Matter snapshot owns visible bubble geometry")
	_assert_true(String(presenter_contract.get("collision_source", "")) == "SAME_MATTER_MESH", "Matter visible and collision mesh share source")
	var anchor: Vector3 = bubble.anchor_body_fixed_m()
	_assert_true(
		String(moon.installed_adapter.route_for_body_fixed_position(anchor)) == "MATTER",
		"Moon route selects Matter inside bubble"
	)
	_assert_true(
		not moon.installed_adapter.legacy_collision_enabled_at(anchor),
		"legacy collision is masked inside bubble"
	)
	var retained_before: int = int(bubble.snapshot_store().size())
	_assert_true(retained_before > 0, "bubble has materialized canonical snapshots")
	var disabled: Dictionary = runtime.disable_and_restore_legacy()
	_assert_success(disabled, "disable bubble")
	_assert_true(moon.installed_adapter == null, "legacy-only route restored")
	_assert_true(moon.prepare_calls == 2, "legacy cap/collision rebuilt after disable")
	_assert_true(
		int(bubble.snapshot_store().size()) == retained_before,
		"feature disable does not delete canonical Matter state"
	)
	_assert_true(not presenter.visible, "Matter presenter hidden after disable")
	runtime.queue_free()
	moon.queue_free()


func _test_production_hook_guards() -> void:
	var terrain_source := FileAccess.get_file_as_string(
		"res://scripts/world/terrain/procedural_moon_terrain.gd"
	)
	_assert_true(
		terrain_source.contains("func set_matter_surface_adapter(adapter) -> Dictionary:"),
		"Moon terrain exposes production Matter surface adapter hook"
	)
	_assert_true(
		terrain_source.count("_get_matter_local_inner_radius_m(surface_center_direction)") == 3,
		"all three LOCAL rebuild paths mask legacy geometry through one seam"
	)
	_assert_true(
		terrain_source.contains("terrain_shape := local_mesh.create_trimesh_shape()"),
		"legacy collision still derives from the exact masked local mesh"
	)
	var app_source := FileAccess.get_file_as_string("res://scripts/app/lunar_app.gd")
	_assert_true(
		app_source.contains('runtime_world_definition.get("p7_matter_bubble_enabled", false)'),
		"LunarApp feature flag defaults bubble off"
	)
	_assert_true(
		app_source.contains("func enable_p7_lunar_matter_bubble(config: Dictionary = {})"),
		"LunarApp exposes production bubble activation"
	)
	_assert_true(
		app_source.contains("func disable_p7_lunar_matter_bubble() -> Dictionary:"),
		"LunarApp exposes rollback to legacy presentation"
	)


func _assert_success(result: Dictionary, message: String) -> void:
	_assert_true(
		bool(result.get("success", false)),
		"%s: %s" % [message, String(result.get("error_code", ""))]
	)


func _assert_true(condition: bool, message: String) -> void:
	_assertions += 1
	if condition:
		return
	_failures += 1
	push_error("[V0-P7.2 seam] %s" % message)
