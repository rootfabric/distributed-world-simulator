extends SceneTree

const Playground = preload("res://scripts/labs/ecology/eco_evo7_play0_live_planet_playground.gd")
const Individuality = preload("res://scripts/labs/ecology/eco_evo7_vis4_5_deterministic_individuality.gd")
const Traits = preload("res://scripts/research/ecology/plant_development_traits_v1.gd")
const GrowthGraph = preload("res://scripts/research/ecology/plant_growth_graph_skeleton_v1.gd")
const RenderDescription = preload("res://scripts/research/ecology/plant_render_description_v1.gd")
const Representation = preload("res://scripts/research/ecology/plant_multiscale_representation_v1.gd")

var assertions := 0
var failures: Array[String] = []
var _finished := false


func _init() -> void:
	call_deferred("_run")
	call_deferred("_watchdog")


func _run() -> void:
	_controlled_seed_contract()

	var playground = Playground.new()
	playground.auto_initialize = false
	root.add_child(playground)
	await process_frame
	await process_frame

	_check(playground.initialize_runtime(), "VIS4.5 PLAY0 runtime initializes")
	if not playground.ready_success:
		_finish()
		return

	var presentation = playground.get_presentation()
	var earth = playground.get_earth_world()
	var workbench = playground.get_workbench()
	_check(presentation != null and presentation.initialized, "VIS4.5 presentation initialized")
	_check(earth != null and workbench != null, "VIS4.5 keeps real Earth + Workbench")

	var initial_ecology: Dictionary = playground.get_published_snapshot()
	var initial_hash := String(initial_ecology.get("ecology_state_hash", ""))
	_check(initial_hash.length() == 64, "generation-zero ecology hash valid")

	_check(playground.request_generation(), "VIS4.5 generation request accepted")
	_check(await _wait_generation(playground, 60000), "VIS4.5 generation one completes")

	var published: Dictionary = playground.get_published_snapshot()
	var ecology_hash := String(published.get("ecology_state_hash", ""))
	var descriptors: Dictionary = playground.get_published_morphology_descriptors()
	_check(int(published.get("generation", -1)) == 1, "VIS4.5 source is generation one")
	_check(ecology_hash.length() == 64 and ecology_hash != initial_hash, "generation-one ecology published")
	_check(not descriptors.is_empty(), "VIS4.5 Descriptor V2 source published")

	var contract: Dictionary = presentation.get_contract()
	var ph5: Dictionary = Dictionary(contract.get("ph5", {}))
	_check(bool(contract.get("ph5_active", false)), "VIS4.5 runs on live PH5 path")
	_check(bool(ph5.get("deterministic_individuality", false)), "PH5 contract exposes deterministic individuality")
	_check(int(ph5.get("seed_bound_record_count", -1)) == int(ph5.get("record_count", -2)), "every PH5 record is seed-bound")
	_check(String(ph5.get("individuality_identity_hash", "")).length() == 64, "snapshot individuality hash exists")

	var source_values: Array = Array(descriptors.get("descriptors", []))
	_check(source_values.size() == int(ph5.get("record_count", -1)), "VIS4.5 covers every Descriptor V2 record")
	var distinct_seeds := {}
	var distinct_yaws := {}
	var distinct_individuality_hashes := {}
	for index in range(source_values.size()):
		if not source_values[index] is Dictionary:
			_check(false, "Descriptor V2 source record is Dictionary")
			continue
		var source: Dictionary = Dictionary(source_values[index])
		var identity: Dictionary = presentation.get_ph5_record_identity(index)
		var expected: Dictionary = Individuality.build(source)
		_check(not identity.is_empty(), "rendered record identity exists %d" % index)
		_check(not expected.is_empty() and Individuality.validate(expected), "individuality contract validates %d" % index)
		if identity.is_empty() or expected.is_empty():
			continue
		var seed := int(source.get("development_individual_seed", -1))
		var yaw := float(identity.get("orientation_yaw_deg", NAN))
		_check(seed >= 0 and int(identity.get("development_individual_seed", -2)) == seed, "exact development seed preserved %d" % index)
		_check(String(identity.get("source_growth_graph_hash", "")) == String(source.get("growth_graph_hash", "")), "individuality preserves source GrowthGraph %d" % index)
		_check(String(identity.get("individuality_hash", "")) == String(expected.get("individuality_hash", "")), "individuality hash exact %d" % index)
		_check(is_finite(yaw) and yaw >= 0.0 and yaw < 360.0, "individual yaw bounded %d" % index)
		_check(absf(yaw - float(expected.get("orientation_yaw_deg", NAN))) < 0.000001, "individual yaw deterministic from seed %d" % index)
		distinct_seeds[seed] = true
		distinct_yaws["%.9f" % yaw] = true
		distinct_individuality_hashes[String(identity.get("individuality_hash", ""))] = true

	_check(distinct_seeds.size() > 1, "live population contains multiple development individual seeds")
	_check(distinct_yaws.size() > 1, "different live seeds produce distinct deterministic orientations")
	_check(distinct_individuality_hashes.size() == source_values.size(), "each live source record has distinct sealed individuality")

	if source_values.is_empty():
		playground.queue_free()
		await process_frame
		_finish()
		return

	var first_source: Dictionary = Dictionary(source_values[0])
	var first_cell_index := int(first_source.get("cell_index", -1))
	var patch: Dictionary = workbench.get_patch()
	var cells: Array = Array(patch.get("cells", []))
	_check(first_cell_index >= 0 and first_cell_index < cells.size(), "first individuality source cell valid")
	if first_cell_index < 0 or first_cell_index >= cells.size():
		playground.queue_free()
		await process_frame
		_finish()
		return

	var first_world: Vector3 = presentation.get_stem_world_position(0)
	var first_up: Vector3 = Vector3(Dictionary(cells[first_cell_index]).get("direction", Vector3.UP)).normalized()
	var first_height := maxf(0.1, presentation.get_ph5_record_height(0))
	_check(presentation.set_view_world_position(first_world + first_up * first_height * 2.0), "VIS4.5 forces first record to near tier")
	_check(presentation.get_ph5_record_tier(0) == Representation.TIER_0_FULL, "VIS4.5 orientation checked on TIER0 PH5 node")

	var first_identity: Dictionary = presentation.get_ph5_record_identity(0)
	var first_seed := int(first_identity.get("development_individual_seed", -1))
	var first_yaw := float(presentation.get_ph5_record_presentation_yaw_deg(0))
	var expected_yaw := Individuality.orientation_yaw_deg(first_seed)
	_check(absf(first_yaw - expected_yaw) < 0.000001, "PLAY0 applied yaw equals deterministic seed contract")

	var actual_basis: Basis = presentation.get_ph5_record_visual_basis(0)
	var expected_basis := _up_basis(first_up) * Basis(Vector3.UP, deg_to_rad(expected_yaw))
	_check(_basis_equal(actual_basis, expected_basis, 0.00001), "PLAY0 plant basis applies surface-up x deterministic local yaw")

	var individuality_before := presentation.get_ph5_individuality_identity_hash()
	var geometry_before := presentation.get_ph5_geometry_identity_hash()
	_check(individuality_before.length() == 64 and geometry_before.length() == 64, "identity hashes available before presentation changes")

	presentation.set_neutral_color_mode(false)
	_check(presentation.get_ph5_individuality_identity_hash() == individuality_before, "lineage color preserves individuality identity")
	_check(presentation.get_ph5_geometry_identity_hash() == geometry_before, "lineage color preserves geometry identity")
	presentation.set_neutral_color_mode(true)
	_check(presentation.get_ph5_individuality_identity_hash() == individuality_before, "neutral color preserves individuality identity")

	var origin_before: Vector3 = earth.get_render_origin()
	var visual_basis_before: Basis = presentation.get_ph5_record_visual_basis(0)
	earth.set_render_origin(origin_before + Vector3(900.0, -400.0, 250.0))
	presentation.refresh_render_transform(true)
	_check(presentation.get_ph5_individuality_identity_hash() == individuality_before, "render-origin shift preserves individuality identity")
	_check(_basis_equal(presentation.get_ph5_record_visual_basis(0), visual_basis_before, 0.00001), "render-origin shift preserves deterministic visual orientation")
	earth.set_render_origin(origin_before)
	presentation.refresh_render_transform(true)

	var tangent := first_up.cross(Vector3.UP)
	if tangent.length_squared() < 0.000001:
		tangent = first_up.cross(Vector3.RIGHT)
	tangent = tangent.normalized()
	var focal_px := 1080.0 / (2.0 * tan(deg_to_rad(70.0) * 0.5))
	_check(presentation.set_view_world_position(first_world + tangent * (first_height * focal_px / 50.0)), "VIS4.5 canopy LOD update succeeds")
	_check(presentation.get_ph5_record_tier(0) == Representation.TIER_2_CANOPY, "VIS4.5 reaches TIER2")
	_check(presentation.get_ph5_individuality_identity_hash() == individuality_before, "LOD switch preserves individuality identity")
	_check(absf(presentation.get_ph5_record_presentation_yaw_deg(0) - first_yaw) < 0.000001, "LOD switch preserves seed-derived yaw")

	_check(presentation.set_view_world_position(first_world + first_up * first_height * 2.0), "VIS4.5 restores near tier")
	_check(presentation.get_ph5_record_tier(0) == Representation.TIER_0_FULL, "VIS4.5 restores TIER0")
	_check(presentation.get_ph5_individuality_identity_hash() == individuality_before, "restored tier preserves individuality identity")

	var replay_tokens := PackedStringArray()
	for value in source_values:
		if value is Dictionary:
			var replay: Dictionary = Individuality.build(Dictionary(value))
			replay_tokens.append(String(replay.get("individuality_hash", "")))
	var replay_hash := "\n".join(replay_tokens).sha256_text()
	var replay_tokens_again := PackedStringArray()
	for value in source_values:
		if value is Dictionary:
			var replay_again: Dictionary = Individuality.build(Dictionary(value))
			replay_tokens_again.append(String(replay_again.get("individuality_hash", "")))
	_check(replay_hash == "\n".join(replay_tokens_again).sha256_text(), "same source seeds replay exact individuality hashes")

	_check(String(playground.get_published_snapshot().get("ecology_state_hash", "")) == ecology_hash, "VIS4.5 presentation operations do not mutate ecology")
	_source_guard()

	playground.queue_free()
	await process_frame
	_finish()


func _controlled_seed_contract() -> void:
	## Controlled proof that the already-accepted GrowthGraph/RenderDescription
	## stack uses individual_seed for bounded topology and foliage individuality.
	var traits: Dictionary = Traits.create(
		"vis4.5/controlled-seed",
		3.2,
		0.32,
		0.0,
		1.0,
		42.0,
		0.78,
		2,
		1.8
	)
	_check(bool(Traits.validate(traits).get("success", false)), "controlled VIS4.5 development traits validate")

	var graph_a: Dictionary = GrowthGraph.build(traits, 41001)
	var graph_a_replay: Dictionary = GrowthGraph.build(traits, 41001)
	var graph_b: Dictionary = GrowthGraph.build(traits, 41002)
	_check(not graph_a.is_empty() and not graph_b.is_empty(), "controlled seed GrowthGraphs build")
	_check(String(graph_a.get("graph_hash", "")) == String(graph_a_replay.get("graph_hash", "")), "same seed reproduces exact GrowthGraph hash")
	_check(JSON.stringify(graph_a.get("segments", [])) == JSON.stringify(graph_a_replay.get("segments", [])), "same seed reproduces exact branch topology")
	_check(JSON.stringify(graph_a.get("segments", [])) != JSON.stringify(graph_b.get("segments", [])), "different seed changes accepted branch geometry")

	var lateral_a: Dictionary = _first_lateral(Array(graph_a.get("segments", [])))
	var lateral_b: Dictionary = _first_lateral(Array(graph_b.get("segments", [])))
	_check(not lateral_a.is_empty() and not lateral_b.is_empty(), "controlled seeds generate lateral branches")
	if not lateral_a.is_empty():
		var angle_a := _segment_angle_deg(lateral_a)
		_check(angle_a >= 42.0 * 0.92 - 0.001 and angle_a <= 42.0 * 1.08 + 0.001, "seed angle jitter remains inside accepted 0.92..1.08 bound")
	if not lateral_a.is_empty() and not lateral_b.is_empty():
		_check(
			JSON.stringify(lateral_a.get("end", [])) != JSON.stringify(lateral_b.get("end", [])),
			"different seeds produce different accepted branch azimuth/length realization"
		)

	var render_a: Dictionary = RenderDescription.build(graph_a)
	var render_a_replay: Dictionary = RenderDescription.build(graph_a_replay)
	var render_b: Dictionary = RenderDescription.build(graph_b)
	_check(not render_a.is_empty() and not render_b.is_empty(), "controlled seed RenderDescriptions build")
	_check(String(render_a.get("render_description_hash", "")) == String(render_a_replay.get("render_description_hash", "")), "same seed reproduces exact RenderDescription")
	_check(JSON.stringify(render_a.get("foliage_anchors", [])) == JSON.stringify(render_a_replay.get("foliage_anchors", [])), "same seed reproduces exact foliage placement")
	_check(JSON.stringify(render_a.get("foliage_anchors", [])) != JSON.stringify(render_b.get("foliage_anchors", [])), "different seed changes deterministic foliage placement")


func _first_lateral(segments: Array) -> Dictionary:
	for value in segments:
		if value is Dictionary and not bool(Dictionary(value).get("main_axis", false)):
			return Dictionary(value)
	return {}


func _segment_angle_deg(segment: Dictionary) -> float:
	var start_values: Array = Array(segment.get("start", []))
	var end_values: Array = Array(segment.get("end", []))
	if start_values.size() != 3 or end_values.size() != 3:
		return NAN
	var start := Vector3(float(start_values[0]), float(start_values[1]), float(start_values[2]))
	var end := Vector3(float(end_values[0]), float(end_values[1]), float(end_values[2]))
	var direction := (end - start).normalized()
	return rad_to_deg(acos(clampf(direction.dot(Vector3.UP), -1.0, 1.0)))


func _basis_equal(a: Basis, b: Basis, epsilon: float) -> bool:
	return (
		a.x.distance_to(b.x) <= epsilon
		and a.y.distance_to(b.y) <= epsilon
		and a.z.distance_to(b.z) <= epsilon
	)


func _up_basis(up: Vector3) -> Basis:
	var helper := Vector3.UP if absf(up.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
	var x_axis := helper.cross(up).normalized()
	var z_axis := x_axis.cross(up).normalized()
	return Basis(x_axis, up, z_axis)


func _wait_generation(playground, timeout_msec: int) -> bool:
	var started := Time.get_ticks_msec()
	while playground.is_generation_running() and Time.get_ticks_msec() - started < timeout_msec:
		await process_frame
	return not playground.is_generation_running()


func _source_guard() -> void:
	var individuality_source := FileAccess.get_file_as_string("res://scripts/labs/ecology/eco_evo7_vis4_5_deterministic_individuality.gd").to_lower()
	var renderer_source := FileAccess.get_file_as_string("res://scripts/labs/ecology/eco_evo7_vis4_4_play0_ph5_renderer.gd").to_lower()
	var graph_source := FileAccess.get_file_as_string("res://scripts/research/ecology/plant_growth_graph_skeleton_v1.gd").to_lower()
	var render_source := FileAccess.get_file_as_string("res://scripts/research/ecology/plant_render_description_v1.gd").to_lower()

	_check(individuality_source.contains("development_individual_seed"), "VIS4.5 consumes canonical development individual seed")
	_check(individuality_source.contains("play0/local-yaw"), "VIS4.5 orientation has stable seed domain")
	_check(renderer_source.contains("* local_yaw"), "VIS4.5 applies individuality only as local presentation orientation")
	_check(not individuality_source.contains("growthgraph.build") and not individuality_source.contains("plant_growth_graph_skeleton"), "VIS4.5 contract does not rebuild/copy GrowthGraph")
	_check(not individuality_source.contains("randi") and not individuality_source.contains("randf") and not individuality_source.contains("randomize"), "VIS4.5 uses no process RNG")
	_check(graph_source.contains("_unit(individual_seed, \"azimuth/%d\""), "accepted GrowthGraph seed controls branch azimuth")
	_check(graph_source.contains("lerpf(0.92, 1.08"), "accepted GrowthGraph angle jitter is bounded")
	_check(graph_source.contains("_unit(individual_seed, \"length/%d/%d\""), "accepted GrowthGraph seed controls bounded branch length jitter")
	_check(render_source.contains("_unit(graph_hash, \"%s/leaf_rot/%d\""), "accepted RenderDescription deterministically seeds foliage from GrowthGraph identity")

	for source in [individuality_source, renderer_source]:
		_check(not source.contains("advance_generations"), "VIS4.5 presentation owns no generation mutation")
		_check(not source.contains("reproduce_bundle(") and not source.contains("mutation_seed(") and not source.contains("dispersal_seed("), "VIS4.5 owns no reproduction/mutation/dispersal")
		_check(not source.contains("fileaccess.open") and not source.contains("diraccess") and not source.contains("multiplayer"), "VIS4.5 owns no persistence/network authority")


func _watchdog() -> void:
	var deadline := Time.get_ticks_msec() + 90000
	while Time.get_ticks_msec() < deadline and not _finished:
		await process_frame
	if not _finished:
		push_error("ECO.EVO7 VIS4.5 watchdog timeout")
		print("ECO.EVO7 VIS4.5 Deterministic Individuality: FAIL (watchdog timeout)")
		quit(1)


func _check(condition: bool, label: String) -> void:
	assertions += 1
	if not condition:
		failures.append(label)
		push_error("VIS4.5: " + label)


func _finish() -> void:
	if _finished:
		return
	_finished = true
	if failures.is_empty():
		print("ECO.EVO7 VIS4.5 Deterministic Individuality: PASS (%d assertions)" % assertions)
		quit(0)
	else:
		for failure in failures:
			print("FAIL: " + failure)
		print("ECO.EVO7 VIS4.5 Deterministic Individuality: FAIL (%d/%d)" % [failures.size(), assertions])
		quit(1)
