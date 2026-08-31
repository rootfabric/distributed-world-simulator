extends SceneTree

const Playground = preload("res://scripts/labs/ecology/eco_evo7_play0_live_planet_playground.gd")
const GridAppearance = preload("res://scripts/labs/ecology/eco_evo7_vis4_6_grid_appearance_boundary.gd")
const Representation = preload("res://scripts/research/ecology/plant_multiscale_representation_v1.gd")

var assertions := 0
var failures: Array[String] = []
var _finished := false


func _init() -> void:
	call_deferred("_run")
	call_deferred("_watchdog")


func _run() -> void:
	_controlled_vis2_semantics()

	var playground = Playground.new()
	playground.auto_initialize = false
	root.add_child(playground)
	await process_frame
	await process_frame

	_check(playground.initialize_runtime(), "VIS4.6 PLAY0 runtime initializes")
	if not playground.ready_success:
		_finish()
		return

	var presentation = playground.get_presentation()
	var earth = playground.get_earth_world()
	var workbench = playground.get_workbench()
	_check(presentation != null and presentation.initialized, "VIS4.6 presentation initialized")
	_check(earth != null and workbench != null, "VIS4.6 keeps real Earth + Workbench")

	var initial_hash := String(playground.get_published_snapshot().get("ecology_state_hash", ""))
	_check(initial_hash.length() == 64, "generation-zero ecology hash valid")

	_check(playground.request_generation(), "VIS4.6 generation request accepted")
	_check(await _wait_generation(playground, 60000), "VIS4.6 generation one completes")

	var published: Dictionary = playground.get_published_snapshot()
	var ecology_hash := String(published.get("ecology_state_hash", ""))
	var descriptors: Dictionary = playground.get_published_morphology_descriptors()
	var source_values: Array = Array(descriptors.get("descriptors", []))
	var patch: Dictionary = workbench.get_patch()
	var cells: Array = Array(patch.get("cells", []))

	_check(int(published.get("generation", -1)) == 1, "VIS4.6 source is generation one")
	_check(ecology_hash.length() == 64 and ecology_hash != initial_hash, "generation-one ecology published")
	_check(not descriptors.is_empty() and not source_values.is_empty(), "VIS4.6 has live Descriptor V2 source")
	_check(cells.size() == 1024, "VIS4.6 keeps accepted 32x32 Spatial Cohort Lattice")

	var contract: Dictionary = presentation.get_contract()
	var ph5: Dictionary = Dictionary(contract.get("ph5", {}))
	_check(bool(contract.get("ph5_active", false)), "VIS4.6 runs on live PH5 path")
	_check(bool(ph5.get("grid_appearance_boundary", false)), "PH5 declares grid appearance boundary")
	_check(not bool(ph5.get("visual_offset_is_canonical", true)), "visual offset explicitly noncanonical")
	_check(int(ph5.get("grid_size", 0)) == 32, "PH5 grid appearance bound to 32x32 lattice")
	_check(absf(float(ph5.get("max_jitter_x_cell", 0.0)) - 0.24) < 0.000001, "VIS4.6 x jitter bound is VIS2 +/-0.24 cell")
	_check(absf(float(ph5.get("max_jitter_y_cell", 0.0)) - 0.15) < 0.000001, "VIS4.6 y jitter bound is VIS2 +/-0.15 cell")
	_check(String(ph5.get("grid_appearance_identity_hash", "")).length() == 64, "grid appearance snapshot hash exists")
	_check(source_values.size() == int(ph5.get("record_count", -1)), "every live PH5 record has a grid appearance record")

	var displaced_count := 0
	var distinct_appearance := {}
	for index in range(source_values.size()):
		if not source_values[index] is Dictionary:
			_check(false, "Descriptor V2 record is Dictionary")
			continue
		var source: Dictionary = Dictionary(source_values[index])
		var cell_index := int(source.get("cell_index", -1))
		_check(cell_index >= 0 and cell_index < cells.size(), "VIS4.6 source cell is inside canonical lattice %d" % index)
		if cell_index < 0 or cell_index >= cells.size():
			continue
		var cell: Dictionary = Dictionary(cells[cell_index])
		var direction_value = cell.get("direction")
		_check(direction_value is Vector3, "canonical ecology cell exposes direction %d" % index)
		if not direction_value is Vector3:
			continue

		var canonical_direction: Vector3 = Vector3(direction_value).normalized()
		var expected_canonical: Vector3 = earth.get_surface_point(canonical_direction)
		var canonical_world: Vector3 = presentation.get_stem_world_position(index)
		var visual_world: Vector3 = presentation.get_ph5_record_visual_world_position(index)
		var appearance: Dictionary = presentation.get_ph5_record_grid_appearance(index)

		_check(canonical_world.distance_to(expected_canonical) < 0.001, "canonical plant position remains exact cell surface point %d" % index)
		_check(not appearance.is_empty(), "grid appearance evidence exists %d" % index)
		if appearance.is_empty():
			continue

		var spacing := Vector2(
			float(appearance.get("cell_spacing_x_m", 0.0)),
			float(appearance.get("cell_spacing_y_m", 0.0))
		)
		var expected: Dictionary = GridAppearance.build(
			String(source.get("record_id", "")),
			cell_index,
			String(source.get("descriptor_hash", "")),
			spacing
		)
		_check(not expected.is_empty() and GridAppearance.validate(expected), "grid appearance contract validates %d" % index)
		_check(String(appearance.get("appearance_hash", "")) == String(expected.get("appearance_hash", "")), "live appearance hash equals deterministic contract %d" % index)
		_check(absf(float(appearance.get("jitter_x_cell", 0.0))) <= 0.240000001, "live x jitter bounded %d" % index)
		_check(absf(float(appearance.get("jitter_y_cell", 0.0))) <= 0.150000001, "live y jitter bounded %d" % index)
		_check(
			absf(float(appearance.get("offset_x_m", 0.0))) <= spacing.x * 0.240000001,
			"live x offset stays inside cell appearance boundary %d" % index
		)
		_check(
			absf(float(appearance.get("offset_y_m", 0.0))) <= spacing.y * 0.150000001,
			"live y offset stays inside cell appearance boundary %d" % index
		)

		var visual_direction: Vector3 = Vector3(appearance.get("visual_direction", Vector3.ZERO))
		_check(visual_direction.length_squared() > 0.99, "visual direction normalized/nonzero %d" % index)
		if visual_direction.length_squared() > 0.99:
			var expected_visual_surface: Vector3 = earth.get_surface_point(visual_direction.normalized())
			_check(visual_world.distance_to(expected_visual_surface) < 0.001, "visual plant is reprojected onto real Earth surface %d" % index)

		var offset_distance := canonical_world.distance_to(visual_world)
		if offset_distance > 0.0001:
			displaced_count += 1
		distinct_appearance[String(appearance.get("appearance_hash", ""))] = true

	_check(displaced_count > 0, "VIS4.6 visibly displaces at least one live plant from the lattice center")
	_check(distinct_appearance.size() == source_values.size(), "live records have distinct sealed grid appearance identities")

	if source_values.is_empty():
		playground.queue_free()
		await process_frame
		_finish()
		return

	var first: Dictionary = Dictionary(source_values[0])
	var first_cell_index := int(first.get("cell_index", -1))
	var first_cell: Dictionary = Dictionary(cells[first_cell_index])
	var first_up: Vector3 = Vector3(first_cell.get("direction", Vector3.UP)).normalized()
	var canonical_before: Vector3 = presentation.get_stem_world_position(0)
	var visual_before: Vector3 = presentation.get_ph5_record_visual_world_position(0)
	var appearance_before: Dictionary = presentation.get_ph5_record_grid_appearance(0)
	var grid_hash_before: String = presentation.get_ph5_grid_appearance_identity_hash()
	var geometry_before: String = presentation.get_ph5_geometry_identity_hash()
	var individuality_before: String = presentation.get_ph5_individuality_identity_hash()
	var height := maxf(0.1, presentation.get_ph5_record_height(0))

	_check(presentation.set_view_world_position(canonical_before + first_up * height * 2.0), "VIS4.6 forces first record near")
	_check(presentation.get_ph5_record_tier(0) == Representation.TIER_0_FULL, "VIS4.6 first record reaches TIER0")
	var applied_render: Vector3 = presentation.get_ph5_record_applied_render_position(0)
	var expected_visual_render: Vector3 = presentation.get_ph5_record_visual_render_position(0)
	_check(applied_render.distance_to(expected_visual_render) < 0.001, "actual PH5 node transform uses visual position")
	_check(presentation.get_stem_world_position(0).distance_to(canonical_before) < 0.000001, "legacy/canonical world API remains ecology truth")

	presentation.set_neutral_color_mode(false)
	_check(presentation.get_ph5_grid_appearance_identity_hash() == grid_hash_before, "lineage color preserves grid appearance identity")
	_check(presentation.get_ph5_geometry_identity_hash() == geometry_before, "lineage color preserves geometry identity")
	_check(presentation.get_ph5_individuality_identity_hash() == individuality_before, "lineage color preserves individuality identity")
	presentation.set_neutral_color_mode(true)
	_check(presentation.get_ph5_grid_appearance_identity_hash() == grid_hash_before, "neutral color preserves grid appearance identity")

	var origin_before: Vector3 = earth.get_render_origin()
	earth.set_render_origin(origin_before + Vector3(700.0, 250.0, -500.0))
	presentation.refresh_render_transform(true)
	_check(presentation.get_stem_world_position(0).distance_to(canonical_before) < 0.000001, "render-origin preserves canonical ecology position")
	_check(presentation.get_ph5_record_visual_world_position(0).distance_to(visual_before) < 0.000001, "render-origin preserves visual world position")
	_check(presentation.get_ph5_grid_appearance_identity_hash() == grid_hash_before, "render-origin preserves grid appearance identity")
	_check(
		presentation.get_ph5_record_applied_render_position(0).distance_to(presentation.get_ph5_record_visual_render_position(0)) < 0.001,
		"render-origin reprojects actual node from visual world position"
	)
	earth.set_render_origin(origin_before)
	presentation.refresh_render_transform(true)

	var tangent := first_up.cross(Vector3.UP)
	if tangent.length_squared() < 0.000001:
		tangent = first_up.cross(Vector3.RIGHT)
	tangent = tangent.normalized()
	var focal_px := 1080.0 / (2.0 * tan(deg_to_rad(70.0) * 0.5))
	_check(presentation.set_view_world_position(canonical_before + tangent * (height * focal_px / 50.0)), "VIS4.6 canopy LOD update succeeds")
	_check(presentation.get_ph5_record_tier(0) == Representation.TIER_2_CANOPY, "VIS4.6 reaches TIER2")
	_check(presentation.get_ph5_grid_appearance_identity_hash() == grid_hash_before, "LOD preserves grid appearance identity")
	_check(presentation.get_stem_world_position(0).distance_to(canonical_before) < 0.000001, "LOD preserves canonical cell position")
	_check(presentation.get_ph5_record_visual_world_position(0).distance_to(visual_before) < 0.000001, "LOD preserves visual scatter position")
	_check(
		String(presentation.get_ph5_record_grid_appearance(0).get("appearance_hash", "")) == String(appearance_before.get("appearance_hash", "")),
		"LOD preserves per-record appearance hash"
	)

	_check(String(playground.get_published_snapshot().get("ecology_state_hash", "")) == ecology_hash, "VIS4.6 presentation operations do not mutate ecology")
	_source_guard()

	playground.queue_free()
	await process_frame
	_finish()


func _controlled_vis2_semantics() -> void:
	var record_id := "vis4.6-controlled-record"
	var source_hash := "a".repeat(64)
	var spacing := Vector2(10.0, 20.0)
	var a: Dictionary = GridAppearance.build(record_id, 77, source_hash, spacing)
	var replay: Dictionary = GridAppearance.build(record_id, 77, source_hash, spacing)
	var b: Dictionary = GridAppearance.build("vis4.6-other-record", 77, source_hash, spacing)
	_check(not a.is_empty() and GridAppearance.validate(a), "controlled VIS4.6 appearance validates")
	_check(String(a.get("appearance_hash", "")) == String(replay.get("appearance_hash", "")), "same record id replays exact appearance hash")
	_check(
		is_equal_approx(float(a.get("jitter_x_cell", 0.0)), float(replay.get("jitter_x_cell", 0.0)))
		and is_equal_approx(float(a.get("jitter_y_cell", 0.0)), float(replay.get("jitter_y_cell", 0.0))),
		"same record id replays exact cell jitter"
	)
	_check(String(a.get("appearance_hash", "")) != String(b.get("appearance_hash", "")), "different record id changes deterministic appearance")

	var token := record_id.sha256_text()
	var ux := float(token.substr(0, 6).hex_to_int()) / 16777215.0
	var uy := float(token.substr(6, 6).hex_to_int()) / 16777215.0
	var expected_fraction := Vector2((ux - 0.5) * 0.48, (uy - 0.5) * 0.30)
	var actual_fraction := GridAppearance.stable_cell_fraction(record_id)
	_check(actual_fraction.distance_to(expected_fraction) < 0.000000001, "VIS4.6 exactly reuses VIS2 SHA-256 jitter semantics")
	_check(absf(actual_fraction.x) <= 0.240000001 and absf(actual_fraction.y) <= 0.150000001, "controlled jitter remains inside VIS2 cell bounds")
	_check(
		is_equal_approx(float(a.get("offset_x_m", 0.0)), actual_fraction.x * spacing.x)
		and is_equal_approx(float(a.get("offset_y_m", 0.0)), actual_fraction.y * spacing.y),
		"VIS4.6 scales VIS2 cell fractions by physical cell spacing only"
	)
	_check(not bool(a.get("canonical_position", true)), "controlled appearance explicitly noncanonical")
	_check(bool(a.get("presentation_only", false)), "controlled appearance explicitly presentation-only")


func _source_guard() -> void:
	var vis2_source := FileAccess.get_file_as_string("res://scripts/labs/ecology/eco_evo7_vis2_plant_overlay.gd").to_lower()
	var boundary_source := FileAccess.get_file_as_string("res://scripts/labs/ecology/eco_evo7_vis4_6_grid_appearance_boundary.gd").to_lower()
	var renderer_source := FileAccess.get_file_as_string("res://scripts/labs/ecology/eco_evo7_vis4_4_play0_ph5_renderer.gd").to_lower()

	_check(vis2_source.contains("record_id.sha256_text()"), "accepted VIS2 source uses record_id SHA-256 jitter")
	_check(vis2_source.contains("* cell_px * 0.48"), "accepted VIS2 x scatter span is 0.48 cell")
	_check(vis2_source.contains("* cell_px * 0.30"), "accepted VIS2 y scatter span is 0.30 cell")
	_check(boundary_source.contains("16777215.0"), "VIS4.6 keeps VIS2 24-bit normalization")
	_check(boundary_source.contains("x_span_cell := 0.48") and boundary_source.contains("y_span_cell := 0.30"), "VIS4.6 keeps exact VIS2 scatter spans")
	_check(renderer_source.contains("\"visual_offset_is_canonical\": false"), "renderer declares visual scatter noncanonical")
	_check(renderer_source.contains("visual_base_world"), "renderer stores visual position separately from canonical base_world")
	_check(renderer_source.contains("earth_world.get_surface_point(visual_direction)"), "visual scatter is reprojected onto Earth surface")
	_check(not boundary_source.contains("growthgraph") and not boundary_source.contains("phenotype"), "VIS4.6 boundary does not recompute biology")
	_check(not boundary_source.contains("randi") and not boundary_source.contains("randf") and not boundary_source.contains("randomize"), "VIS4.6 uses no process RNG")

	for source in [boundary_source, renderer_source]:
		_check(not source.contains("advance_generations"), "VIS4.6 presentation owns no generation mutation")
		_check(not source.contains("reproduce_bundle(") and not source.contains("mutation_seed(") and not source.contains("dispersal_seed("), "VIS4.6 owns no reproduction/mutation/dispersal")
		_check(not source.contains("fileaccess.open") and not source.contains("diraccess") and not source.contains("multiplayer"), "VIS4.6 owns no persistence/network authority")


func _wait_generation(playground, timeout_msec: int) -> bool:
	var started := Time.get_ticks_msec()
	while playground.is_generation_running() and Time.get_ticks_msec() - started < timeout_msec:
		await process_frame
	return not playground.is_generation_running()


func _watchdog() -> void:
	var deadline := Time.get_ticks_msec() + 90000
	while Time.get_ticks_msec() < deadline and not _finished:
		await process_frame
	if not _finished:
		push_error("ECO.EVO7 VIS4.6 watchdog timeout")
		print("ECO.EVO7 VIS4.6 Grid Appearance Boundary: FAIL (watchdog timeout)")
		quit(1)


func _check(condition: bool, label: String) -> void:
	assertions += 1
	if not condition:
		failures.append(label)
		push_error("VIS4.6: " + label)


func _finish() -> void:
	if _finished:
		return
	_finished = true
	if failures.is_empty():
		print("ECO.EVO7 VIS4.6 Grid Appearance Boundary: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		print("FAIL: " + failure)
	print("ECO.EVO7 VIS4.6 Grid Appearance Boundary: FAIL (%d/%d)" % [failures.size(), assertions])
	quit(1)
