extends SceneTree

## ECO.EVO7 VIS5.2 — Noncanonical Ground-Cover Bridge acceptance.

const Bridge = preload(
	"res://scripts/labs/ecology/eco_evo7_vis5_2_noncanonical_ground_cover_bridge.gd"
)
const Adapter = preload(
	"res://scripts/labs/ecology/eco_evo7_vis5_1_terrain_surface_frame_adapter.gd"
)

var assertions := 0
var failures: Array[String] = []


class FakeEarthWorld extends RefCounted:
	var radius_m := 1000.0
	var slope_gain_m := 80.0
	var grass_density := 1.0
	var water_kind := 0
	var snow_mask := 0.0
	var state_calls := 0
	var point_calls := 0

	func get_planet_radius() -> float:
		return radius_m

	func get_surface_state(
		direction: Vector3,
		lod_level: int = 0
	) -> Dictionary:
		state_calls += 1
		return {
			"elevation_m": slope_gain_m * direction.normalized().x,
			"grass_density": grass_density,
			"water_kind": water_kind,
			"snow_mask": snow_mask,
			"lod_level": lod_level,
		}

	func get_surface_point(direction: Vector3) -> Vector3:
		point_calls += 1
		var d := direction.normalized()
		return d * (radius_m + slope_gain_m * d.x)


class FakeAssets extends RefCounted:
	var mesh_calls: Array[String] = []
	var material_calls: Array[String] = []

	func get_grass_mesh(type_id: String) -> Mesh:
		mesh_calls.append(type_id)
		var mesh := QuadMesh.new()
		mesh.size = Vector2(0.4, 0.8)
		return mesh

	func get_grass_material(type_id: String) -> Material:
		material_calls.append(type_id)
		return StandardMaterial3D.new()


func _init() -> void:
	_m1_setup_fail_closed()
	_m2_ground_cover_materialization()
	_m3_determinism()
	_m4_environment_filters()
	_m5_authority_and_source_boundary()
	_finish()


func _config() -> Dictionary:
	return {
		"seed": 9137,
		"grass_radius_m": 30.0,
		"max_grass_instances": 24,
		"maximum_grass_slope_deg": 20.0,
		"snow_grass_cutoff": 0.16,
		"surface_sample_distance_m": 2.0,
		"grass_attempts_multiplier": 3,
		"grass_types": [
			{
				"id": "short",
				"weight": 2.0,
				"min_scale": 0.8,
				"max_scale": 1.1,
			},
			{
				"id": "tall",
				"weight": 1.0,
				"min_scale": 1.0,
				"max_scale": 1.4,
			},
		],
	}


func _m1_setup_fail_closed() -> void:
	var node := Bridge.new()
	root.add_child(node)
	_check(
		not node.setup(null, FakeAssets.new(), _config()),
		"null terrain source rejected"
	)
	_check(
		not node.setup(FakeEarthWorld.new(), null, _config()),
		"null assets rejected"
	)
	var bad := _config()
	bad["grass_types"] = []
	_check(
		not node.setup(FakeEarthWorld.new(), FakeAssets.new(), bad),
		"empty grass types rejected"
	)
	bad = _config()
	bad["max_grass_instances"] = 50001
	_check(
		not node.setup(FakeEarthWorld.new(), FakeAssets.new(), bad),
		"oversized instance budget rejected"
	)
	_check(
		node.regenerate(Vector3.UP, Vector3.ZERO).is_empty(),
		"regenerate rejected before valid setup"
	)
	node.free()


func _m2_ground_cover_materialization() -> void:
	var earth := FakeEarthWorld.new()
	var assets := FakeAssets.new()
	var node := Bridge.new()
	root.add_child(node)
	_check(
		node.setup(earth, assets, _config()),
		"valid ground-cover setup accepted"
	)
	var anchor := earth.get_surface_point(Vector3.UP)
	var summary := node.regenerate(Vector3.UP, anchor, 77, 0)

	_check(not summary.is_empty(), "ground-cover generation succeeds")
	_check(Bridge.validate_summary(summary), "summary validates")
	_check(
		String(summary.get("truth_status", "")) == Bridge.TRUTH_STATUS,
		"explicit noncanonical scenery marker"
	)
	_check(
		bool(summary.get("presentation_only", false)),
		"presentation-only marker"
	)
	_check(
		int(summary.get("grass_instances", -1)) == 24,
		"fixture reaches exact grass budget"
	)
	_check(
		not bool(summary.get("procedural_trees_created", true)),
		"procedural trees remain absent"
	)
	_check(
		not bool(summary.get("ecology_individuals_created", true)),
		"decorative grass does not create ecology individuals"
	)
	_check(
		String(summary.get("surface_frame_schema", "")) == Adapter.SCHEMA,
		"VIS5.1 surface frame is explicit dependency"
	)
	_check(
		float(summary.get("min_normal_alignment", 0.0)) > 0.999999,
		"planned transforms preserve terrain-normal Y exactly"
	)
	_check(node.get_child_count() > 0, "MultiMesh presentation nodes created")

	var total_instances := 0
	for child in node.get_children():
		_check(
			child is MultiMeshInstance3D,
			"every generated child is MultiMeshInstance3D"
		)
		_check(
			String(child.name).begins_with("GroundCover_"),
			"generated node uses ground-cover namespace"
		)
		_check(
			not String(child.name).contains("Tree"),
			"generated node cannot masquerade as tree"
		)
		var instance := child as MultiMeshInstance3D
		_check(instance.multimesh != null, "generated node owns MultiMesh")
		if instance.multimesh != null:
			total_instances += instance.multimesh.instance_count
			_check(
				instance.multimesh.mesh != null,
				"grass mesh supplied by asset library"
			)
	_check(total_instances == 24, "MultiMesh counts equal summary count")
	_check(
		assets.mesh_calls.size() == 2,
		"setup requests only configured grass meshes"
	)
	_check(
		assets.material_calls.size() == 2,
		"setup requests only configured grass materials"
	)
	_check(
		earth.state_calls > 0 and earth.point_calls > 0,
		"bridge consumes read-only terrain source"
	)

	node.apply_lod_flags({"ground_cover": false})
	for child in node.get_children():
		_check(not child.visible, "ground-cover LOD can hide all batches")
	node.apply_lod_flags({"ground_cover": true})
	for child in node.get_children():
		_check(child.visible, "ground-cover LOD can restore all batches")
	node.free()


func _m3_determinism() -> void:
	var earth := FakeEarthWorld.new()
	var node := Bridge.new()
	root.add_child(node)
	_check(
		node.setup(earth, FakeAssets.new(), _config()),
		"determinism setup accepted"
	)
	var anchor := earth.get_surface_point(Vector3.UP)
	var first := node.regenerate(Vector3.UP, anchor, 991, 1)
	var first_hash := String(first.get("generation_hash", ""))
	var second := node.regenerate(Vector3.UP, anchor, 991, 1)
	_check(
		String(second.get("generation_hash", "")) == first_hash,
		"same seed reproduces generation hash"
	)
	_check(
		Dictionary(second.get("bucket_counts", {}))
		== Dictionary(first.get("bucket_counts", {})),
		"same seed reproduces batch counts"
	)
	var changed := node.regenerate(Vector3.UP, anchor, 992, 1)
	_check(
		String(changed.get("generation_hash", "")) != first_hash,
		"different presentation seed changes generation hash"
	)
	_check(
		int(second.get("lod_level", -1)) == 1,
		"requested LOD is recorded"
	)
	node.free()


func _m4_environment_filters() -> void:
	var earth := FakeEarthWorld.new()
	var node := Bridge.new()
	root.add_child(node)
	_check(
		node.setup(earth, FakeAssets.new(), _config()),
		"filter setup accepted"
	)
	var anchor := earth.get_surface_point(Vector3.UP)

	earth.grass_density = 0.0
	var summary := node.regenerate(Vector3.UP, anchor, 1, 0)
	_check(
		int(summary.get("grass_instances", -1)) == 0,
		"zero density creates no scenery"
	)
	_check(
		int(summary.get("rejected_density", 0)) > 0,
		"zero density is diagnosed"
	)

	earth.grass_density = 1.0
	earth.water_kind = 1
	summary = node.regenerate(Vector3.UP, anchor, 1, 0)
	_check(
		int(summary.get("grass_instances", -1)) == 0,
		"water excludes ground cover"
	)
	_check(
		int(summary.get("rejected_water", 0)) > 0,
		"water rejection diagnosed"
	)

	earth.water_kind = 0
	earth.snow_mask = 1.0
	summary = node.regenerate(Vector3.UP, anchor, 1, 0)
	_check(
		int(summary.get("grass_instances", -1)) == 0,
		"snow cutoff excludes ground cover"
	)
	_check(
		int(summary.get("rejected_snow", 0)) > 0,
		"snow rejection diagnosed"
	)
	node.free()


func _m5_authority_and_source_boundary() -> void:
	var source := _source(
		"res://scripts/labs/ecology/"
		+ "eco_evo7_vis5_2_noncanonical_ground_cover_bridge.gd"
	)
	_check(
		source.contains("NONCANONICAL_SCENERY"),
		"source permanently labels noncanonical scenery"
	)
	_check(source.contains("get_grass_mesh"), "source uses grass asset path")
	_check(
		source.contains("get_grass_material"),
		"source uses grass material path"
	)
	_check(
		not source.contains("get_tree_mesh"),
		"bridge has no tree mesh path"
	)
	_check(
		not source.contains("get_billboard_mesh"),
		"bridge has no billboard tree path"
	)
	_check(
		not source.contains("tree_density"),
		"bridge never reads procedural tree density"
	)
	_check(
		not source.contains("get_tree_material"),
		"bridge has no tree material path"
	)

	var summary := {
		"schema": Bridge.SCHEMA,
		"version": Bridge.VERSION,
		"revision": Bridge.REVISION,
		"truth_status": Bridge.TRUTH_STATUS,
		"presentation_only": true,
		"grass_instances": 1,
		"lod_level": 0,
		"surface_frame_schema": Adapter.SCHEMA,
		"min_normal_alignment": 1.0,
		"procedural_trees_created": false,
		"ecology_individuals_created": false,
		"ecology_count_meaning": false,
		"fitness_meaning": false,
		"mutation_meaning": false,
		"descriptor_v2_changed": false,
		"ecology_state_hash_changed": false,
		"terrain_written": false,
		"generation_hash": "a".repeat(64),
	}
	_check(
		Bridge.validate_summary(summary),
		"authority boundary summary accepted"
	)

	var tampered := summary.duplicate(true)
	tampered["ecology_count_meaning"] = true
	_check(
		not Bridge.validate_summary(tampered),
		"ecology-count semantics are rejected"
	)
	tampered = summary.duplicate(true)
	tampered["truth_status"] = "CANONICAL"
	_check(
		not Bridge.validate_summary(tampered),
		"canonical truth claim is rejected"
	)
	tampered = summary.duplicate(true)
	tampered["procedural_trees_created"] = true
	_check(
		not Bridge.validate_summary(tampered),
		"procedural-tree claim is rejected"
	)


func _source(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	return file.get_as_text() if file != null else ""


func _check(condition: bool, label: String) -> void:
	assertions += 1
	if not condition:
		failures.append(label)


func _finish() -> void:
	if failures.is_empty():
		print(
			"ECO.EVO7 VIS5.2 Noncanonical Ground-Cover Bridge: "
			+ "PASS (%d assertions)" % assertions
		)
		quit(0)
		return
	for failure in failures:
		push_error("ECO.EVO7 VIS5.2 FAIL: %s" % failure)
	print(
		"ECO.EVO7 VIS5.2 Noncanonical Ground-Cover Bridge: "
		+ "FAIL (%d assertions, %d failures)"
		% [assertions, failures.size()]
	)
	quit(1)
