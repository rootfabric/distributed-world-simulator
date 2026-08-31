extends SceneTree

const Playground = preload("res://scripts/labs/ecology/eco_evo7_play0_live_planet_playground.gd")
const InspectorModel = preload("res://scripts/labs/ecology/eco_evo7_vis4_7_morphology_inspector_model.gd")

var assertions := 0
var failures: Array[String] = []
var _finished := false


func _init() -> void:
	call_deferred("_run")
	call_deferred("_watchdog")


func _run() -> void:
	_controlled_model_contract()

	var playground = Playground.new()
	playground.auto_initialize = false
	root.add_child(playground)
	await process_frame
	await process_frame

	_check(playground.initialize_runtime(), "VIS4.7 PLAY0 runtime initializes")
	if not playground.ready_success:
		_finish()
		return

	var presentation = playground.get_presentation()
	_check(presentation != null, "VIS4.7 presentation exists")
	_check(not playground.is_morphology_inspector_visible(), "VIS4.7 inspector starts hidden")

	var panel: PanelContainer = playground.get_node_or_null("Play0HUD/VIS47MorphologyInspectorPanel") as PanelContainer
	var label: Label = playground.get_node_or_null("Play0HUD/VIS47MorphologyInspectorPanel/VIS47MorphologyInspectorText") as Label
	_check(panel is PanelContainer and not panel.visible, "VIS4.7 inspector panel starts hidden")
	_check(label is Label, "VIS4.7 inspector label exists")
	if panel is PanelContainer:
		_check(panel.mouse_filter == Control.MOUSE_FILTER_IGNORE, "VIS4.7 panel cannot intercept gameplay mouse")
	if label is Label:
		_check(label.mouse_filter == Control.MOUSE_FILTER_IGNORE, "VIS4.7 text cannot intercept gameplay mouse")

	var g0_ecology_hash := String(playground.get_published_snapshot().get("ecology_state_hash", ""))
	_check(playground.set_morphology_inspector_visible(true), "VIS4.7 F6-equivalent opens unavailable generation-zero panel")
	_check(playground.is_morphology_inspector_visible(), "VIS4.7 unavailable panel is visibly open")
	_check(playground.get_morphology_inspector_state().is_empty(), "generation-zero inspector does not fabricate phenotype")
	_check(playground.get_morphology_inspector_text().contains("Unavailable until a completed generation > 0"), "generation-zero inspector states evidence boundary")
	_check(String(playground.get_published_snapshot().get("ecology_state_hash", "")) == g0_ecology_hash, "generation-zero inspector cannot mutate ecology")
	_check(not playground.toggle_morphology_inspector(), "VIS4.7 toggle closes generation-zero inspector")
	_check(not playground.is_morphology_inspector_visible(), "VIS4.7 inspector hidden before live generation")

	_check(playground.request_generation(), "VIS4.7 generation request accepted")
	_check(await _wait_generation(playground, 60000), "VIS4.7 generation one completes")

	var published: Dictionary = playground.get_published_snapshot()
	var descriptors_snapshot: Dictionary = playground.get_published_morphology_descriptors()
	var descriptors: Array = Array(descriptors_snapshot.get("descriptors", []))
	var ecology_hash := String(published.get("ecology_state_hash", ""))
	_check(int(published.get("generation", -1)) == 1, "VIS4.7 source is completed generation one")
	_check(ecology_hash.length() == 64, "VIS4.7 source ecology hash valid")
	_check(not descriptors.is_empty(), "VIS4.7 has live Descriptor V2 records")

	var geometry_hash_before: String = presentation.get_ph5_geometry_identity_hash()
	var individuality_hash_before: String = presentation.get_ph5_individuality_identity_hash()
	var appearance_hash_before: String = presentation.get_ph5_grid_appearance_identity_hash()
	_check(geometry_hash_before.length() == 64, "VIS4.7 geometry identity available")
	_check(individuality_hash_before.length() == 64, "VIS4.7 individuality identity available")
	_check(appearance_hash_before.length() == 64, "VIS4.7 grid appearance identity available")

	var active_view: Vector3 = playground.get_player().get_world_position()
	var expected_nearest := -1
	var expected_distance := INF
	for index in range(descriptors.size()):
		if not presentation.is_ph5_record_individual_materialized(index):
			continue
		var candidate_world: Vector3 = presentation.get_ph5_record_visual_world_position(index)
		var candidate_distance := candidate_world.distance_squared_to(active_view)
		if candidate_distance < expected_distance:
			expected_distance = candidate_distance
			expected_nearest = index

	_check(playground.set_morphology_inspector_visible(true), "VIS4.7 opens live morphology inspector")
	_check(playground.is_morphology_inspector_visible(), "VIS4.7 live inspector visible")
	var selected_index: int = playground.get_morphology_inspector_selected_index()
	_check(selected_index >= 0 and selected_index < descriptors.size(), "VIS4.7 selects a live PH5 record")
	_check(expected_nearest >= 0 and selected_index == expected_nearest, "VIS4.7 F6 selects the exact nearest materialized PH5 plant")
	if selected_index >= 0 and selected_index < descriptors.size():
		_check(presentation.is_ph5_record_individual_materialized(selected_index), "VIS4.7 F6 selection prefers a visually materialized PH5 plant")
	var status: Dictionary = playground.get_play0_status()
	_check(bool(status.get("morphology_inspector_visible", false)), "VIS4.7 status reports inspector visible")
	_check(int(status.get("morphology_inspector_selected_index", -1)) == selected_index, "VIS4.7 status reports selected index")
	if selected_index < 0 or selected_index >= descriptors.size():
		playground.queue_free()
		await process_frame
		_finish()
		return

	var descriptor: Dictionary = Dictionary(descriptors[selected_index])
	var render_identity: Dictionary = presentation.get_ph5_record_identity(selected_index)
	var grid_appearance: Dictionary = presentation.get_ph5_record_grid_appearance(selected_index)
	var state: Dictionary = playground.get_morphology_inspector_state()
	_check(not state.is_empty() and InspectorModel.validate(state), "VIS4.7 selected inspector state validates")
	_check(String(state.get("record_id", "")) == String(descriptor.get("record_id", "")), "VIS4.7 selected record id exact")
	_check(int(state.get("cell_index", -1)) == int(descriptor.get("cell_index", -2)), "VIS4.7 selected cell exact")
	_check(String(state.get("lineage_id", "")) == String(descriptor.get("lineage_id", "")), "VIS4.7 lineage exact")
	_check(int(state.get("hereditary_individual_seed", -1)) == int(descriptor.get("hereditary_individual_seed", -2)), "VIS4.7 hereditary seed exact")
	_check(int(state.get("development_individual_seed", -1)) == int(descriptor.get("development_individual_seed", -2)), "VIS4.7 development seed exact")
	_check(String(state.get("descriptor_hash", "")) == String(descriptor.get("descriptor_hash", "")), "VIS4.7 descriptor hash exact")
	_check(String(state.get("phenotype_hash", "")) == String(descriptor.get("phenotype_hash", "")), "VIS4.7 phenotype hash exact")
	_check(String(state.get("growth_graph_hash", "")) == String(descriptor.get("growth_graph_hash", "")), "VIS4.7 GrowthGraph hash exact")
	_check(Dictionary(state.get("potential_morphology", {})) == Dictionary(descriptor.get("potential_morphology", {})), "VIS4.7 genetic potential is exact pass-through")
	_check(Dictionary(state.get("realized_topology", {})) == Dictionary(descriptor.get("realized_topology", {})), "VIS4.7 realized topology is exact pass-through")
	_check(Dictionary(state.get("functional_morphology", {})) == Dictionary(descriptor.get("functional_morphology", {})), "VIS4.7 functional morphology is exact pass-through")
	_check(Dictionary(state.get("competition_context", {})) == Dictionary(descriptor.get("competition_context", {})), "VIS4.7 water/light/resource context exact")

	_check(String(state.get("individuality_hash", "")) == String(render_identity.get("individuality_hash", "")), "VIS4.7 individuality hash exact")
	_check(String(state.get("render_description_hash", "")) == String(render_identity.get("render_description_hash", "")), "VIS4.7 render description hash exact")
	_check(String(state.get("representation_hash", "")) == String(render_identity.get("representation_hash", "")), "VIS4.7 representation hash exact")
	_check(String(state.get("materialization_hash", "")) == String(render_identity.get("materialization_hash", "")), "VIS4.7 materialization hash exact")
	_check(String(state.get("tier", "")) == String(render_identity.get("tier", "")), "VIS4.7 current PH5 tier exact")
	_check(absf(float(state.get("orientation_yaw_deg", NAN)) - float(render_identity.get("orientation_yaw_deg", NAN))) < 0.000001, "VIS4.7 deterministic yaw exact")
	_check(String(state.get("appearance_hash", "")) == String(grid_appearance.get("appearance_hash", "")), "VIS4.7 appearance hash exact")
	_check(Vector3(state.get("canonical_world", Vector3.ZERO)).distance_to(Vector3(grid_appearance.get("canonical_world", Vector3.ZERO))) < 0.000001, "VIS4.7 canonical position exact")
	_check(Vector3(state.get("visual_world", Vector3.ZERO)).distance_to(Vector3(grid_appearance.get("visual_world", Vector3.ZERO))) < 0.000001, "VIS4.7 visual position exact")
	_check(not bool(state.get("visual_offset_is_canonical", true)), "VIS4.7 labels VIS4.6 scatter noncanonical")

	var text_value: String = playground.get_morphology_inspector_text()
	for required in [
		"VIS4.7 MORPHOLOGY INSPECTOR",
		"REALIZED",
		"GENETIC POTENTIAL",
		"PRESENTATION",
		"HASHES",
		"crown radius",
		"crown density",
		"LAI",
		"branch p",
		"foliage density",
		"structural",
		"roots depth",
		"water",
		"light",
		"resource balance",
		"visual offset NONCANONICAL",
	]:
		_check(text_value.contains(required), "VIS4.7 panel exposes %s" % required)
	_check(text_value.contains(String(state.get("record_id", ""))), "VIS4.7 panel names selected record")
	_check(text_value.contains(String(state.get("lineage_id", ""))), "VIS4.7 panel names lineage")
	_check(text_value.contains(String(state.get("descriptor_hash", "")).substr(0, 16)), "VIS4.7 panel exposes source descriptor hash")
	_check(text_value.contains(String(state.get("growth_graph_hash", "")).substr(0, 16)), "VIS4.7 panel exposes GrowthGraph hash")
	_check(text_value.contains(String(state.get("materialization_hash", "")).substr(0, 16)), "VIS4.7 panel exposes materialization hash")

	var first_state_hash := String(state.get("inspector_hash", ""))
	var target_index := descriptors.size() - 1
	_check(playground.select_morphology_inspector_index(target_index), "VIS4.7 explicit record selection succeeds")
	var selected_state: Dictionary = playground.get_morphology_inspector_state()
	_check(String(selected_state.get("record_id", "")) == String(Dictionary(descriptors[target_index]).get("record_id", "")), "VIS4.7 explicit selection resolves exact Descriptor record")
	if descriptors.size() > 1:
		_check(String(selected_state.get("inspector_hash", "")) != first_state_hash, "VIS4.7 selection changes only inspector identity")

	var preserved_state: Dictionary = playground.get_morphology_inspector_state()
	_check(not playground.select_morphology_inspector_index(-1), "VIS4.7 rejects invalid negative selection")
	_check(playground.get_morphology_inspector_state() == preserved_state, "invalid selection preserves last valid inspector state")
	_check(not playground.select_morphology_inspector_index(descriptors.size()), "VIS4.7 rejects out-of-range selection")
	_check(playground.get_morphology_inspector_state() == preserved_state, "out-of-range selection preserves last valid inspector state")

	_check(String(playground.get_published_snapshot().get("ecology_state_hash", "")) == ecology_hash, "VIS4.7 selection/opening cannot mutate ecology")
	_check(presentation.get_ph5_geometry_identity_hash() == geometry_hash_before, "VIS4.7 cannot change geometry identity")
	_check(presentation.get_ph5_individuality_identity_hash() == individuality_hash_before, "VIS4.7 cannot change individuality identity")
	_check(presentation.get_ph5_grid_appearance_identity_hash() == appearance_hash_before, "VIS4.7 cannot change grid appearance identity")

	var tampered_identity: Dictionary = render_identity.duplicate(true)
	tampered_identity["source_descriptor_hash"] = "f".repeat(64)
	_check(
		InspectorModel.build(1, ecology_hash, descriptor, tampered_identity, grid_appearance).is_empty(),
		"VIS4.7 model rejects render identity bound to another descriptor"
	)
	var tampered_grid: Dictionary = grid_appearance.duplicate(true)
	tampered_grid["source_descriptor_hash"] = "e".repeat(64)
	_check(
		InspectorModel.build(1, ecology_hash, descriptor, render_identity, tampered_grid).is_empty(),
		"VIS4.7 model rejects appearance identity bound to another descriptor"
	)

	_check(not playground.toggle_morphology_inspector(), "VIS4.7 toggle closes live inspector")
	_check(not playground.is_morphology_inspector_visible(), "VIS4.7 panel closes cleanly")
	if panel is PanelContainer:
		_check(not panel.visible, "VIS4.7 panel node hidden after close")
	_check(String(playground.get_published_snapshot().get("ecology_state_hash", "")) == ecology_hash, "closing VIS4.7 inspector leaves ecology unchanged")

	_source_guard()

	playground.queue_free()
	await process_frame
	_finish()


func _controlled_model_contract() -> void:
	var descriptor := {
		"record_id": "vis4.7-controlled",
		"cell_index": 17,
		"lineage_id": "lineage-controlled",
		"hereditary_individual_seed": 101,
		"development_individual_seed": 202,
		"evidence_level": "LS3.4_SOURCE_BOUND_MORPHOLOGY",
		"descriptor_hash": "a".repeat(64),
		"phenotype_hash": "b".repeat(64),
		"plasticity_phenotype_hash": "c".repeat(64),
		"growth_graph_hash": "d".repeat(64),
		"source_evidence_record_hash": "e".repeat(64),
		"source_evaluation_hash": "f".repeat(64),
		"potential_morphology": {
			"max_height_m": 4.0,
			"internode_length_m": 0.3,
			"apical_dominance": 0.5,
			"branch_probability": 0.6,
			"branch_angle_deg": 38.0,
			"branch_length_ratio": 0.8,
			"branching_depth": 2,
			"crown_spread_m": 1.7,
			"foliage_density": 0.7,
			"leaf_economics_proxy": 0.4,
			"structural_investment": 0.65,
			"root_depth_m": 1.2,
			"root_spread_m": 1.8,
			"root_shoot_ratio": 0.45,
		},
		"realized_topology": {
			"max_height_m": 3.7,
			"internode_length_m": 0.28,
			"apical_dominance": 0.52,
			"branch_probability": 0.58,
			"branch_angle_deg": 39.0,
			"branch_length_ratio": 0.77,
			"branching_depth": 2,
			"crown_spread_m": 1.55,
		},
		"functional_morphology": {
			"realized_height_m": 3.4,
			"realized_crown_radius_m": 1.3,
			"realized_crown_density": 0.72,
			"leaf_area_index_proxy": 2.1,
			"leaf_size_proxy": 0.55,
			"leaf_conservative_strategy": 0.33,
			"structural_investment": 0.61,
			"realized_root_depth_m": 1.05,
			"realized_root_spread_m": 1.62,
			"root_shoot_ratio": 0.43,
		},
		"competition_context": {
			"water_satisfaction": 0.81,
			"effective_light": 0.74,
			"realized_resource_balance": 0.22,
		},
	}
	var render_identity := {
		"record_id": "vis4.7-controlled",
		"source_descriptor_hash": "a".repeat(64),
		"source_growth_graph_hash": "d".repeat(64),
		"orientation_yaw_deg": 123.5,
		"individuality_hash": "1".repeat(64),
		"render_description_hash": "2".repeat(64),
		"representation_hash": "3".repeat(64),
		"materialization_hash": "4".repeat(64),
		"tier": "TIER_0_FULL",
	}
	var grid := {
		"record_id": "vis4.7-controlled",
		"cell_index": 17,
		"source_descriptor_hash": "a".repeat(64),
		"appearance_hash": "5".repeat(64),
		"canonical_world": Vector3(1.0, 2.0, 3.0),
		"visual_world": Vector3(1.2, 2.1, 3.1),
	}
	var model: Dictionary = InspectorModel.build(1, "6".repeat(64), descriptor, render_identity, grid)
	_check(not model.is_empty() and InspectorModel.validate(model), "controlled VIS4.7 model validates")
	var replay: Dictionary = InspectorModel.build(1, "6".repeat(64), descriptor, render_identity, grid)
	_check(String(model.get("inspector_hash", "")) == String(replay.get("inspector_hash", "")), "controlled VIS4.7 model replays exact inspector hash")
	var formatted := InspectorModel.format_text(model)
	_check(formatted.contains("crown radius 1.300 m"), "controlled VIS4.7 text exposes realized crown radius")
	_check(formatted.contains("water 0.810"), "controlled VIS4.7 text exposes water context")
	_check(formatted.contains("visual offset NONCANONICAL"), "controlled VIS4.7 text preserves VIS4.6 boundary")


func _source_guard() -> void:
	var model_source := FileAccess.get_file_as_string("res://scripts/labs/ecology/eco_evo7_vis4_7_morphology_inspector_model.gd").to_lower()
	var playground_source := FileAccess.get_file_as_string("res://scripts/labs/ecology/eco_evo7_play0_live_planet_playground.gd").to_lower()

	_check(playground_source.contains("key_f6"), "VIS4.7 PLAY0 binds F6")
	_check(playground_source.contains("_select_nearest_morphology_inspector_record"), "VIS4.7 F6 resolves a selected live record")
	_check(playground_source.contains("get_published_morphology_descriptors"), "VIS4.7 exposes only completed published morphology source")
	_check(model_source.contains("presentation_only := true"), "VIS4.7 model declares presentation-only")
	_check(model_source.contains("visual_offset_is_canonical"), "VIS4.7 inspector exposes VIS4.6 noncanonical visual offset")
	_check(not model_source.contains("growthgraph.build"), "VIS4.7 does not rebuild GrowthGraph")
	_check(not model_source.contains("functionalphenotype"), "VIS4.7 does not recompute FunctionalPhenotype")
	_check(not model_source.contains("coupleddevelopment"), "VIS4.7 does not rerun PH2 biology")

	_check(
		not model_source.contains("reproduce_bundle(")
		and not model_source.contains("mutation_seed(")
		and not model_source.contains("dispersal_seed("),
		"VIS4.7 model owns no reproduction/mutation/dispersal"
	)
	_check(
		not model_source.contains("fileaccess.open")
		and not model_source.contains("diraccess")
		and not model_source.contains("multiplayer"),
		"VIS4.7 model owns no persistence/network authority"
	)
	_check(not playground_source.contains("morphologyinspectormodel.new"), "VIS4.7 uses static read model without hidden mutable inspector service")


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
		push_error("ECO.EVO7 VIS4.7 watchdog timeout")
		print("ECO.EVO7 VIS4.7 Morphology Inspector: FAIL (watchdog timeout)")
		quit(1)


func _check(condition: bool, label: String) -> void:
	assertions += 1
	if not condition:
		failures.append(label)
		push_error("VIS4.7: " + label)


func _finish() -> void:
	if _finished:
		return
	_finished = true
	if failures.is_empty():
		print("ECO.EVO7 VIS4.7 Morphology Inspector: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		print("FAIL: " + failure)
	print("ECO.EVO7 VIS4.7 Morphology Inspector: FAIL (%d/%d)" % [failures.size(), assertions])
	quit(1)
