extends SceneTree

const Playground = preload("res://scripts/labs/ecology/eco_evo7_play0_live_planet_playground.gd")
const Representation = preload("res://scripts/research/ecology/plant_multiscale_representation_v1.gd")

var assertions := 0
var failures: Array[String] = []
var _finished := false


func _init() -> void:
	call_deferred("_run")
	call_deferred("_watchdog")


func _run() -> void:
	var playground = Playground.new()
	playground.auto_initialize = false
	root.add_child(playground)
	await process_frame
	await process_frame

	_check(playground.initialize_runtime(), "VIS4.4 PLAY0 runtime initializes")
	if not playground.ready_success:
		_finish()
		return

	var presentation = playground.get_presentation()
	var earth = playground.get_earth_world()
	var workbench = playground.get_workbench()
	_check(presentation != null and presentation.initialized, "PLAY0 presentation initialized")
	_check(earth != null and workbench != null, "PLAY0 keeps real Earth + Workbench sources")

	var founder_contract: Dictionary = presentation.get_contract()
	_check(not bool(founder_contract.get("ph5_active", true)), "generation zero uses founder fallback")
	_check(bool(founder_contract.get("legacy_founder_fallback", false)), "founder fallback explicitly observable")
	_check(int(founder_contract.get("founder_marker_count", 0)) > 0, "generation zero contains founder markers")

	var initial: Dictionary = playground.get_published_snapshot()
	var initial_hash := String(initial.get("ecology_state_hash", ""))
	_check(initial_hash.length() == 64, "initial ecology hash valid")

	_check(playground.request_generation(), "VIS4.4 generation request accepted")
	_check(await _wait_generation(playground, 60000), "generation one completes")
	var published: Dictionary = playground.get_published_snapshot()
	var ecology_hash := String(published.get("ecology_state_hash", ""))
	_check(int(published.get("generation", -1)) == 1, "generation one published")
	_check(ecology_hash.length() == 64 and ecology_hash != initial_hash, "generation one ecology hash committed")

	var morph: Dictionary = playground.get_published_morphology_descriptors()
	var reconstruction: Dictionary = playground.get_published_reconstruction_evidence()
	_check(not morph.is_empty(), "VIS4.1 Descriptor V2 published")
	_check(not reconstruction.is_empty(), "VIS4.3 reconstruction evidence published")
	_check(String(morph.get("source_ecology_state_hash", "")) == ecology_hash, "Descriptor V2 binds published ecology")

	var contract: Dictionary = presentation.get_contract()
	var ph5: Dictionary = contract.get("ph5", {})
	_check(bool(contract.get("ph5_active", false)), "generation > 0 primary path is PH5")
	_check(bool(contract.get("uses_vis4_exact_ph5", false)), "presentation reports exact VIS4 PH5")
	_check(not bool(contract.get("legacy_founder_fallback", true)), "legacy fallback disabled for live plants")
	_check(not presentation.stems_node.visible and not presentation.crowns_node.visible, "Box/Sphere nodes hidden on live generation")
	_check(String(contract.get("source_ecology_hash", "")) == ecology_hash, "PH5 presentation binds ecology hash")
	_check(String(ph5.get("source_ecology_hash", "")) == ecology_hash, "PH5 renderer binds exact ecology hash")
	_check(String(ph5.get("source_adapter_hash", "")) == String(morph.get("adapter_hash", "")), "PH5 binds Descriptor V2 adapter hash")
	_check(String(ph5.get("source_reconstruction_hash", "")) == String(reconstruction.get("evidence_hash", "")), "PH5 binds reconstruction evidence hash")
	_check(String(ph5.get("source_bridge_hash", "")).length() == 64, "PH5 complete bridge hash present")
	_check(int(ph5.get("record_count", -1)) == int(published.get("population_count", ph5.get("record_count", -1))), "PH5 record count is non-vacuous")
	_check(int(ph5.get("record_count", 0)) == int(morph.get("descriptor_count", -1)), "every Descriptor V2 record reaches PH5")
	_check(int(ph5.get("visible_individual_count", 0)) > 0, "initial live view materializes individual PH5 nodes")
	_check(int(ph5.get("materialization_build_count", 0)) > 0, "PH5 materialization executed")

	var identity := presentation.get_ph5_record_identity(0)
	_check(not identity.is_empty(), "first PH5 record identity observable")
	for key in ["source_descriptor_hash", "source_growth_graph_hash", "render_description_hash", "representation_hash", "materialization_hash"]:
		_check(String(identity.get(key, "")).length() == 64, "first PH5 identity has %s" % key)

	var source_by_id := _by_id(Array(morph.get("descriptors", [])))
	var source: Dictionary = source_by_id.get(String(identity.get("record_id", "")), {})
	_check(not source.is_empty(), "PH5 record maps to Descriptor V2 record")
	_check(String(identity.get("source_growth_graph_hash", "")) == String(source.get("growth_graph_hash", "")), "rendered plant binds exact GrowthGraph hash")

	var cell_index := int(source.get("cell_index", -1))
	var patch: Dictionary = workbench.get_patch()
	var cells: Array = Array(patch.get("cells", []))
	_check(cell_index >= 0 and cell_index < cells.size(), "rendered record cell index valid")
	if cell_index >= 0 and cell_index < cells.size():
		var direction: Vector3 = Dictionary(cells[cell_index]).get("direction", Vector3.ZERO)
		var expected_world: Vector3 = earth.get_surface_point(direction)
		_check(presentation.get_stem_world_position(0).distance_to(expected_world) < 0.001, "PH5 uses physical get_surface_point placement")

	var world_base := presentation.get_stem_world_position(0)
	var up := world_base.normalized()
	var height := maxf(0.1, presentation.get_ph5_record_height(0))
	var tangent := up.cross(Vector3.UP)
	if tangent.length_squared() < 0.000001:
		tangent = up.cross(Vector3.RIGHT)
	tangent = tangent.normalized()
	var focal_px := 1080.0 / (2.0 * tan(deg_to_rad(70.0) * 0.5))

	_check(presentation.set_view_world_position(world_base + up * height * 2.0), "near LOD update succeeds")
	_check(presentation.get_ph5_record_tier(0) == Representation.TIER_0_FULL, "near plant reaches TIER0 full PH5")
	_check(presentation.is_ph5_record_individual_materialized(0), "TIER0 has individual PH5 node")

	_check(presentation.set_view_world_position(world_base + tangent * (height * focal_px / 50.0)), "canopy LOD update succeeds")
	_check(presentation.get_ph5_record_tier(0) == Representation.TIER_2_CANOPY, "mid-distance plant reaches TIER2 canopy")
	_check(presentation.is_ph5_record_individual_materialized(0), "TIER2 keeps individual canopy node")

	_check(presentation.set_view_world_position(world_base + tangent * (height * focal_px / 10.0)), "impostor LOD update succeeds")
	_check(presentation.get_ph5_record_tier(0) == Representation.TIER_3_IMPOSTOR, "far plant reaches TIER3 impostor")
	_check(presentation.is_ph5_record_individual_materialized(0), "TIER3 keeps individual impostor node")

	_check(presentation.set_view_world_position(world_base + tangent * (height * focal_px / 1.0)), "population LOD update succeeds")
	_check(presentation.get_ph5_record_tier(0) == Representation.TIER_4_POPULATION_ONLY, "very far plant reaches TIER4 population-only")
	_check(not presentation.is_ph5_record_individual_materialized(0), "TIER4 creates no individual node")

	# Restore an individual tier for transform/color checks.
	_check(presentation.set_view_world_position(world_base + up * height * 2.0), "restore near PH5 tier")
	var before_color_hash := presentation.get_ph5_geometry_identity_hash()
	var ecology_before_color := String(playground.get_published_snapshot().get("ecology_state_hash", ""))
	presentation.set_neutral_color_mode(false)
	var lineage_hash := presentation.get_ph5_geometry_identity_hash()
	presentation.set_neutral_color_mode(true)
	var neutral_hash := presentation.get_ph5_geometry_identity_hash()
	_check(before_color_hash == lineage_hash and lineage_hash == neutral_hash, "neutral/lineage color does not change geometry hashes")
	_check(String(playground.get_published_snapshot().get("ecology_state_hash", "")) == ecology_before_color, "color mode cannot mutate ecology")

	var ph5_before_origin: Dictionary = Dictionary(presentation.get_contract().get("ph5", {}))
	var builds_before := int(ph5_before_origin.get("materialization_build_count", -1))
	var render_before := presentation.get_stem_render_position(0)
	var world_before := presentation.get_stem_world_position(0)
	var origin_before: Vector3 = earth.get_render_origin()
	earth.set_render_origin(origin_before + Vector3(1500.0, 0.0, 0.0))
	presentation.refresh_render_transform(true)
	var render_after := presentation.get_stem_render_position(0)
	var ph5_after_origin: Dictionary = Dictionary(presentation.get_contract().get("ph5", {}))
	_check(absf((render_after - render_before).length() - 1500.0) < 1.0, "render-origin shift reprojects PH5 transform")
	_check(world_before.distance_to(earth.render_to_world(render_after)) < 0.01, "PH5 world position invariant under render-origin shift")
	_check(int(ph5_after_origin.get("materialization_build_count", -2)) == builds_before, "render-origin shift does not rebuild PH5 geometry")
	earth.set_render_origin(origin_before)
	presentation.refresh_render_transform(true)

	# Incomplete/tampered live bridge must preserve the last complete presentation.
	var legacy_descriptors := playground.get_published_descriptors()
	var classification := workbench.get_classification()
	var tampered: Dictionary = reconstruction.duplicate(true)
	tampered["evidence_hash"] = "0".repeat(64)
	var bridge_before := String(Dictionary(presentation.get_contract().get("ph5", {})).get("source_bridge_hash", ""))
	var geometry_before := presentation.get_ph5_geometry_identity_hash()
	_check(not presentation.apply_snapshot(legacy_descriptors, classification, morph, tampered), "tampered reconstruction fails closed")
	var bridge_after := String(Dictionary(presentation.get_contract().get("ph5", {})).get("source_bridge_hash", ""))
	_check(bridge_after == bridge_before, "tampered bridge cannot replace source bridge identity")
	_check(presentation.get_ph5_geometry_identity_hash() == geometry_before, "tampered bridge keeps last completed geometry")
	_check(String(playground.get_published_snapshot().get("ecology_state_hash", "")) == ecology_hash, "tampered presentation attempt cannot mutate published ecology")

	_source_guard()
	playground.queue_free()
	await process_frame
	_finish()


func _wait_generation(playground, timeout_msec: int) -> bool:
	var started := Time.get_ticks_msec()
	while playground.is_generation_running() and Time.get_ticks_msec() - started < timeout_msec:
		await process_frame
	return not playground.is_generation_running()


func _by_id(values: Array) -> Dictionary:
	var out := {}
	for value in values:
		if value is Dictionary:
			var item: Dictionary = value
			out[String(item.get("record_id", ""))] = item
	return out


func _source_guard() -> void:
	var playground_source := FileAccess.get_file_as_string("res://scripts/labs/ecology/eco_evo7_play0_live_planet_playground.gd").to_lower()
	var presentation_source := FileAccess.get_file_as_string("res://scripts/labs/ecology/eco_evo7_play0_planet_presentation.gd").to_lower()
	var renderer_source := FileAccess.get_file_as_string("res://scripts/labs/ecology/eco_evo7_vis4_4_play0_ph5_renderer.gd").to_lower()
	_check(playground_source.contains("eco_evo7_vis4_morphology_render_adapter.gd"), "PLAY0 consumes VIS4.1 Descriptor V2")
	_check(playground_source.contains("get_graph_reconstruction_evidence"), "PLAY0 consumes VIS4.3 reconstruction evidence")
	_check(presentation_source.contains("eco_evo7_vis4_4_play0_ph5_renderer.gd"), "PLAY0 presentation owns VIS4.4 PH5 renderer seam")
	_check(renderer_source.contains("eco_evo7_vis4_3_exact_ph5_bridge.gd"), "VIS4.4 delegates geometry to VIS4.3 bridge")
	_check(renderer_source.contains("materialize_record"), "VIS4.4 delegates tier materialization to PH5")
	_check(not renderer_source.contains("boxmesh.new") and not renderer_source.contains("spheremesh.new"), "VIS4.4 creates no second Box/Sphere live renderer")
	_check(not renderer_source.contains("plant_growth_graph_skeleton_v1.gd"), "VIS4.4 does not copy/rebuild GrowthGraph directly")
	for source in [presentation_source, renderer_source]:
		_check(not source.contains("advance_generations"), "presentation owns no generation mutation")
		_check(not source.contains("reproduce_bundle(") and not source.contains("mutation_seed(") and not source.contains("dispersal_seed("), "presentation owns no reproduction/mutation/dispersal")
		_check(not source.contains("fileaccess.open") and not source.contains("diraccess") and not source.contains("multiplayer"), "presentation owns no persistence/network authority")


func _watchdog() -> void:
	var deadline := Time.get_ticks_msec() + 90000
	while Time.get_ticks_msec() < deadline and not _finished:
		await process_frame
	if not _finished:
		push_error("ECO.EVO7 VIS4.4 watchdog timeout")
		print("ECO.EVO7 VIS4.4 PLAY0.MORPH: FAIL (watchdog timeout)")
		quit(1)


func _check(condition: bool, label: String) -> void:
	assertions += 1
	if not condition:
		failures.append(label)
		push_error("VIS4.4: " + label)


func _finish() -> void:
	if _finished:
		return
	_finished = true
	if failures.is_empty():
		print("ECO.EVO7 VIS4.4 PLAY0.MORPH: PASS (%d assertions)" % assertions)
		quit(0)
	else:
		for failure in failures:
			print("FAIL: " + failure)
		print("ECO.EVO7 VIS4.4 PLAY0.MORPH: FAIL (%d/%d)" % [failures.size(), assertions])
		quit(1)
