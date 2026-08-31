extends SceneTree

const RuntimeScript = preload(
	"res://scripts/world/matter/lunar_matter_bubble_runtime.gd"
)
const TerrainScript = preload(
	"res://scripts/world/terrain/procedural_moon_terrain.gd"
)
const SeamClipperScript = preload(
	"res://scripts/world/matter/legacy_moon_matter_seam_clipper.gd"
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


class FakeClipAdapter:
	extends RefCounted

	var bounds: Dictionary = {}

	func legacy_exclusion_bounds() -> Dictionary:
		return bounds.duplicate(true)

	func route_for_body_fixed_position(position_m: Vector3) -> String:
		return "MATTER" if _contains(position_m) else "LEGACY"

	func legacy_collision_enabled_at(position_m: Vector3) -> bool:
		return not _contains(position_m)

	func _contains(position_m: Vector3) -> bool:
		var minimum_m := _vector3(bounds.get("minimum_m", []))
		var maximum_m := _vector3(bounds.get("maximum_m", []))
		return position_m.x >= minimum_m.x and position_m.x <= maximum_m.x \
			and position_m.y >= minimum_m.y and position_m.y <= maximum_m.y \
			and position_m.z >= minimum_m.z and position_m.z <= maximum_m.z

	static func _vector3(value: Array) -> Vector3:
		if value.size() != 3:
			return Vector3(INF, INF, INF)
		return Vector3(float(value[0]), float(value[1]), float(value[2]))


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_runtime_wiring_and_rollback()
	_test_adversarial_triangle_clipper()
	_test_off_center_terrain_clip()
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
		"legacy_seam_clearance_m": 0.02,
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
	_assert_true(moon.prepare_calls == 1, "legacy surface rebuilt once with body-fixed seam clip")
	_assert_true(moon.last_prepare_direction.is_equal_approx(Vector3.UP), "fixed bubble anchor rebuild")
	var exclusion: Dictionary = adapter.legacy_exclusion_bounds()
	_assert_true(not exclusion.is_empty(), "adapter exposes fixed body-frame exclusion bounds")
	_assert_true(
		absf(float(exclusion.get("clearance_m", -1.0)) - 0.02) < 0.000001,
		"legacy seam has explicit positive clearance"
	)
	_assert_true(
		String(adapter.contract_report().get("seam_strategy", "")) == "BODY_FIXED_AABB_TRIANGLE_CLIP",
		"seam strategy is body-fixed triangle clipping, not observer-centered masking"
	)
	_assert_true(presenter.presenter_count() > 0, "Matter mesh presenters created")
	var presenter_contract: Dictionary = presenter.contract_report()
	_assert_true(String(presenter_contract.get("geometry_source", "")) == "MATTER_SNAPSHOT", "Matter snapshot owns visible bubble geometry")
	_assert_true(String(presenter_contract.get("collision_source", "")) == "SAME_MATTER_MESH", "Matter visible and collision mesh share source")
	var anchor: Vector3 = bubble.anchor_body_fixed_m()
	var old_circle_escape := anchor + Vector3(15.5, 0.0, 15.5)
	_assert_true(
		String(adapter.route_for_body_fixed_position(old_circle_escape)) == "MATTER",
		"adversarial root corner remains Matter-owned beyond the old circular mask"
	)
	_assert_true(
		not adapter.legacy_collision_enabled_at(old_circle_escape),
		"legacy collision is forbidden at old circular-mask escape corner"
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


func _test_adversarial_triangle_clipper() -> void:
	var anchor := Vector3(100.0, 200.0, 300.0)
	var bounds := {
		"minimum_m": [anchor.x - 1.0, anchor.y - 1.0, anchor.z - 1.0],
		"maximum_m": [anchor.x + 1.0, anchor.y + 1.0, anchor.z + 1.0],
		"clearance_m": 0.10,
	}
	var body_a := anchor + Vector3(-2.0, -2.0, 0.0)
	var body_b := anchor + Vector3(2.0, -2.0, 0.0)
	var body_c := anchor + Vector3(0.0, 2.0, 0.0)
	_assert_true(
		not SeamClipperScript.triangle_fully_outside_exclusion(body_a, body_b, body_c, bounds),
		"adversarial triangle crosses Matter although every source vertex is outside"
	)
	var vertices := PackedVector3Array([
		body_a - anchor,
		body_b - anchor,
		body_c - anchor,
	])
	var uvs := PackedVector2Array([Vector2.ZERO, Vector2.RIGHT, Vector2.UP])
	var clipped: Dictionary = SeamClipperScript.clip_mesh_arrays(
		vertices,
		uvs,
		PackedInt32Array([0, 1, 2]),
		anchor,
		bounds
	)
	_assert_true(not clipped.is_empty(), "adversarial triangle clip returns mesh data")
	_assert_true(
		int(clipped.get("clipped_source_triangle_count", 0)) == 1,
		"crossing triangle is actually partitioned"
	)
	_assert_true(
		PackedInt32Array(clipped.get("indices", PackedInt32Array())).size() >= 3,
		"outside triangle fragments are preserved"
	)
	_assert_all_triangles_outside(
		clipped.get("vertices", PackedVector3Array()),
		clipped.get("indices", PackedInt32Array()),
		anchor,
		bounds,
		"clipped crossing triangle"
	)

	var inside_vertices := PackedVector3Array([
		Vector3(-0.2, -0.2, 0.0),
		Vector3(0.2, -0.2, 0.0),
		Vector3(0.0, 0.2, 0.0),
	])
	var removed: Dictionary = SeamClipperScript.clip_mesh_arrays(
		inside_vertices,
		PackedVector2Array([Vector2.ZERO, Vector2.RIGHT, Vector2.UP]),
		PackedInt32Array([0, 1, 2]),
		anchor,
		bounds
	)
	_assert_true(
		PackedInt32Array(removed.get("indices", PackedInt32Array())).is_empty(),
		"triangle fully inside Matter exclusion is removed"
	)
	_assert_true(
		int(removed.get("removed_source_triangle_count", 0)) == 1,
		"fully owned Matter triangle is counted as removed"
	)


func _test_off_center_terrain_clip() -> void:
	var terrain = TerrainScript.new()
	terrain.setup_generation_only()
	terrain.surface_center_direction = Vector3.UP
	var east: Vector3 = terrain.call("_make_east", terrain.surface_center_direction)
	terrain.surface_east = east
	terrain.surface_north = east.cross(terrain.surface_center_direction).normalized()
	terrain.surface_anchor_world = terrain.get_surface_point(terrain.surface_center_direction)

	var baseline_mesh: ArrayMesh = terrain.call(
		"_build_radial_cap_mesh",
		0.0,
		80.0,
		12,
		64,
		false
	) as ArrayMesh
	_assert_true(baseline_mesh != null and baseline_mesh.get_surface_count() == 1, "baseline legacy cap builds")
	if baseline_mesh == null or baseline_mesh.get_surface_count() == 0:
		terrain.free()
		return
	var box_center: Vector3 = terrain.surface_anchor_world + east * 24.0
	var bounds := {
		"minimum_m": [box_center.x - 10.0, box_center.y - 10.0, box_center.z - 10.0],
		"maximum_m": [box_center.x + 10.0, box_center.y + 10.0, box_center.z + 10.0],
		"clearance_m": 0.02,
	}
	var baseline_arrays: Array = baseline_mesh.surface_get_arrays(0)
	var baseline_candidates := _count_not_fully_outside(
		baseline_arrays[Mesh.ARRAY_VERTEX],
		baseline_arrays[Mesh.ARRAY_INDEX],
		terrain.surface_anchor_world,
		bounds
	)
	_assert_true(
		baseline_candidates > 0,
		"off-center Matter box intersects legacy cap before clipping"
	)

	terrain.recent_surface_cache["stale-unmasked"] = {"schema": "test"}
	terrain.recent_surface_cache_order.append("stale-unmasked")
	var fake_adapter := FakeClipAdapter.new()
	fake_adapter.bounds = bounds
	_assert_success(terrain.set_matter_surface_adapter(fake_adapter), "install off-center seam adapter")
	_assert_true(
		terrain.recent_surface_cache.is_empty() and terrain.recent_surface_cache_order.is_empty(),
		"installing seam adapter invalidates stale unmasked surface cache"
	)
	var clipped_mesh: ArrayMesh = terrain.call(
		"_build_radial_cap_mesh",
		0.0,
		80.0,
		12,
		64,
		false
	) as ArrayMesh
	_assert_true(clipped_mesh != null and clipped_mesh.get_surface_count() == 1, "off-center clipped legacy cap builds")
	if clipped_mesh != null and clipped_mesh.get_surface_count() == 1:
		var clipped_arrays: Array = clipped_mesh.surface_get_arrays(0)
		_assert_all_triangles_outside(
			clipped_arrays[Mesh.ARRAY_VERTEX],
			clipped_arrays[Mesh.ARRAY_INDEX],
			terrain.surface_anchor_world,
			bounds,
			"off-center terrain integration"
		)
	var worker_profile: Dictionary = terrain.call(
		"_profiled_radial_cap_data",
		0.0,
		80.0,
		12,
		64,
		false,
		bounds
	)
	var worker_data: Dictionary = worker_profile.get("data", {})
	_assert_true(not worker_data.is_empty(), "worker/profiled legacy cap builds with seam bounds")
	if not worker_data.is_empty():
		_assert_all_triangles_outside(
			worker_data.get("vertices", PackedVector3Array()),
			worker_data.get("indices", PackedInt32Array()),
			terrain.surface_anchor_world,
			bounds,
			"worker/profiled off-center terrain integration"
		)
	_assert_success(terrain.set_matter_surface_adapter(null), "remove off-center seam adapter")
	terrain.free()


func _test_production_hook_guards() -> void:
	var terrain_source := FileAccess.get_file_as_string(
		"res://scripts/world/terrain/procedural_moon_terrain.gd"
	)
	_assert_true(
		terrain_source.contains("func set_matter_surface_adapter(adapter) -> Dictionary:"),
		"Moon terrain exposes production Matter surface adapter hook"
	)
	_assert_true(
		terrain_source.count("LegacyMatterSeamClipperScript.clip_mesh_arrays(") == 2,
		"same body-fixed clipper protects synchronous and worker-generated legacy meshes"
	)
	_assert_true(
		not terrain_source.contains("_get_matter_local_inner_radius_m"),
		"observer-centered circular seam implementation is removed"
	)
	_assert_true(
		terrain_source.contains("recent_surface_cache.clear()"),
		"adapter changes invalidate stale unmasked legacy surface cache"
	)
	_assert_true(
		terrain_source.contains("terrain_shape := local_mesh.create_trimesh_shape()"),
		"legacy collision still derives from the exact clipped local mesh"
	)
	var streaming_source := FileAccess.get_file_as_string(
		"res://scripts/world/terrain/streaming/terrain_streaming_manager.gd"
	)
	_assert_true(
		streaming_source.contains('request["matter_exclusion_bounds"] = exclusion_bounds.duplicate(true)'),
		"streaming worker receives immutable body-fixed exclusion bounds"
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


func _count_not_fully_outside(
	vertices: PackedVector3Array,
	indices: PackedInt32Array,
	surface_anchor_world: Vector3,
	bounds: Dictionary
) -> int:
	var count := 0
	for offset in range(0, indices.size(), 3):
		var a := surface_anchor_world + vertices[indices[offset]]
		var b := surface_anchor_world + vertices[indices[offset + 1]]
		var c := surface_anchor_world + vertices[indices[offset + 2]]
		if not SeamClipperScript.triangle_fully_outside_exclusion(a, b, c, bounds):
			count += 1
	return count


func _assert_all_triangles_outside(
	vertices: PackedVector3Array,
	indices: PackedInt32Array,
	surface_anchor_world: Vector3,
	bounds: Dictionary,
	message: String
) -> void:
	var violations := 0
	for offset in range(0, indices.size(), 3):
		var a := surface_anchor_world + vertices[indices[offset]]
		var b := surface_anchor_world + vertices[indices[offset + 1]]
		var c := surface_anchor_world + vertices[indices[offset + 2]]
		if not SeamClipperScript.triangle_fully_outside_exclusion(a, b, c, bounds):
			violations += 1
	_assert_true(violations == 0, "%s has %d Matter-overlapping legacy triangles" % [message, violations])


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
