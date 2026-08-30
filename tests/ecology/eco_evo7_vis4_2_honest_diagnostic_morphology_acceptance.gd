extends SceneTree

const EarthWorld = preload("res://scripts/world/earth/procedural_earth_world.gd")
const ViewerScene = preload("res://scenes/labs/ecology/eco_evo7_vis4_2_diagnostic_morphology_viewer.tscn")
const Mapper = preload("res://scripts/labs/ecology/eco_evo7_vis4_2_diagnostic_morphology_mapper.gd")
const Overlay = preload("res://scripts/labs/ecology/eco_evo7_vis4_2_diagnostic_morphology_overlay.gd")

var assertions := 0
var failures: Array[String] = []

func _init() -> void:
	var world = EarthWorld.new()
	root.add_child(world)
	_check(world.setup(null), "real Earth source initializes")

	var viewer = ViewerScene.instantiate()
	viewer.auto_initialize = false
	viewer.ensure_ui_built()
	root.add_child(viewer)
	_check(viewer.initialize_runtime(world), "VIS4.2 initializes over public Workbench + Descriptor V2")

	_identity_and_founder_gate(viewer)
	_generation_one_honest_morphology(viewer)
	_deterministic_replay(world, viewer)
	_source_guard()

	viewer.queue_free()
	world.queue_free()
	_finish()

func _identity_and_founder_gate(viewer) -> void:
	var identity: Dictionary = viewer.get_runtime_identity()
	_check(String(identity.get("scene_name", "")) == "EcoEvo7VIS42DiagnosticMorphologyViewer", "VIS4.2 scene identity exact")
	_check(String(identity.get("viewer_title", "")) == "ECO EVO7 — VIS4.2 Honest Diagnostic Morphology", "VIS4.2 title exact")
	_check(String(identity.get("revision", "")) == "ECO.EVO7-VIS4.2.R1", "VIS4.2 runtime revision exact")

	var contract: Dictionary = viewer.get_ui_contract()
	for key in [
		"descriptor_v2_only", "honest_realized_crown", "honest_realized_density",
		"branch_silhouette", "neutral_color_mode", "diagnostic_only", "presentation_only",
	]:
		_check(bool(contract.get(key, false)), "VIS4.2 UI contract exposes %s" % key)
	_check(not bool(contract.get("primary_play0_replacement", true)), "VIS4.2 explicitly does not replace PLAY0")

	var overlay_contract: Dictionary = viewer.overlay.get_render_contract()
	for key in [
		"descriptor_v2_only", "realized_height", "realized_crown_radius", "realized_crown_density",
		"branch_silhouette", "structural_cue", "leaf_strategy_cue", "neutral_color",
		"presentation_only", "diagnostic_only",
	]:
		_check(bool(overlay_contract.get(key, false)), "VIS4.2 overlay contract exposes %s" % key)
	_check(not bool(overlay_contract.get("seed_shape_jitter", true)), "VIS4.2 defers seed-based individuality to VIS4.5")

	var state0: Dictionary = viewer.get_view_state()
	var ecology_hash0 := String(state0.get("ecology_state_hash", ""))
	_check(int(state0.get("generation", -1)) == 0, "VIS4.2 starts at generation zero")
	_check(ecology_hash0.length() == 64, "generation-zero ecology hash valid")
	var source0: Dictionary = viewer.get_source_descriptor_snapshot()
	_check(not source0.is_empty(), "generation zero still has Descriptor V2 founder source")
	_check(int(source0.get("founder_marker_count", -1)) == int(source0.get("descriptor_count", -2)), "generation-zero Descriptor V2 remains founder-only")
	_check(viewer.get_diagnostic_snapshot().is_empty(), "VIS4.2 fabricates no realized diagnostic morphology at generation zero")
	_check(viewer.get_diagnostic_descriptors().is_empty(), "generation-zero diagnostic descriptor set is empty")
	_check(viewer.overlay.set_descriptors([]), "VIS4.2 overlay accepts untyped empty founder/fail-closed descriptor arrays")
	_check(not viewer.overlay.set_descriptors([{"record_id": "invalid"}]), "VIS4.2 overlay still rejects malformed generic descriptor arrays")

	_check(viewer.set_neutral_color(false), "lineage color mode toggles")
	_check(viewer.set_camera_state(1.7, Vector2(31.0, -14.0)), "diagnostic camera state accepts bounded presentation transform")
	_check(viewer.set_neutral_color(true), "neutral color mode restores")
	var state_after_controls: Dictionary = viewer.get_view_state()
	_check(String(state_after_controls.get("ecology_state_hash", "")) == ecology_hash0, "neutral/color camera controls cannot mutate ecology")

func _generation_one_honest_morphology(viewer) -> void:
	var ecology_hash0 := String(viewer.get_view_state().get("ecology_state_hash", ""))
	_check(viewer.manual_step(1), "VIS4.2 advances one real ecology generation")
	var view1: Dictionary = viewer.get_view_state()
	var source1: Dictionary = viewer.get_source_descriptor_snapshot()
	var diagnostic: Dictionary = viewer.get_diagnostic_snapshot()
	var descriptors: Array = viewer.get_diagnostic_descriptors()

	_check(int(view1.get("generation", -1)) == 1, "VIS4.2 follows generation one")
	_check(String(view1.get("ecology_state_hash", "")) != ecology_hash0, "only real ecology step changes ecology state")
	_check(not source1.is_empty(), "generation-one Descriptor V2 source exists")
	_check(not diagnostic.is_empty(), "generation-one diagnostic morphology exists")
	_check(Mapper.new().validate_result(diagnostic), "VIS4.2 diagnostic result validates")
	_check(int(source1.get("descriptor_count", -1)) == 61, "generation-one source population remains exact accepted 61 survivors")
	_check(int(diagnostic.get("descriptor_count", -1)) == 61, "VIS4.2 maps all 61 living plants")
	_check(descriptors.size() == 61, "overlay-facing descriptors are non-vacuous and complete")
	_check(String(diagnostic.get("source_adapter_hash", "")) == String(source1.get("adapter_hash", "")), "diagnostic result binds exact Descriptor V2 hash")
	_check(String(diagnostic.get("source_ecology_state_hash", "")) == String(view1.get("ecology_state_hash", "")), "diagnostic result binds exact ecology state")
	_check(String(diagnostic.get("source_morphology_evidence_hash", "")) == String(view1.get("morphology_evidence_hash", "")), "diagnostic result binds exact morphology sidecar")
	_check(String(diagnostic.get("render_hash", "")).length() == 64, "diagnostic render hash valid")
	_check(String(view1.get("diagnostic_render_hash", "")) == String(diagnostic.get("render_hash", "")), "viewer exposes exact diagnostic render hash")

	var source_by_id := _by_id(Array(source1.get("descriptors", [])))
	var unique_silhouettes := {}
	for value in descriptors:
		if not value is Dictionary:
			_check(false, "diagnostic descriptor dictionary")
			continue
		var item: Dictionary = value
		var record_id := String(item.get("record_id", ""))
		_check(source_by_id.has(record_id), "VIS4.2 descriptor has exact Descriptor V2 source %s" % record_id)
		if not source_by_id.has(record_id):
			continue
		var source: Dictionary = source_by_id[record_id]
		var functional: Dictionary = source.get("functional_morphology", {})
		var topology: Dictionary = source.get("realized_topology", {})
		var potential: Dictionary = source.get("potential_morphology", {})
		_check(String(item.get("source_descriptor_hash", "")) == String(source.get("descriptor_hash", "")), "source descriptor seal exact")
		_check(String(item.get("source_evidence_record_hash", "")) == String(source.get("source_evidence_record_hash", "")), "source evidence record seal exact")
		_check(String(item.get("source_growth_graph_hash", "")) == String(source.get("growth_graph_hash", "")), "GrowthGraph seal exact")
		_check(int(item.get("hereditary_individual_seed", -1)) == int(source.get("hereditary_individual_seed", -2)), "hereditary seed passes through")
		_check(int(item.get("development_individual_seed", -1)) == int(source.get("development_individual_seed", -2)), "development seed passes through")
		_check(is_equal_approx(float(item.get("realized_height_m", NAN)), float(functional.get("realized_height_m", NAN))), "realized height passes through")
		_check(is_equal_approx(float(item.get("realized_crown_radius_m", NAN)), float(functional.get("realized_crown_radius_m", NAN))), "realized crown radius passes through")
		_check(is_equal_approx(float(item.get("realized_crown_density", NAN)), float(functional.get("realized_crown_density", NAN))), "realized crown density passes through")
		_check(is_equal_approx(float(item.get("structural_investment", NAN)), float(functional.get("structural_investment", NAN))), "structural investment passes through")
		_check(is_equal_approx(float(item.get("leaf_conservative_strategy", NAN)), float(functional.get("leaf_conservative_strategy", NAN))), "leaf strategy passes through")
		_check(is_equal_approx(float(item.get("apical_dominance", NAN)), float(topology.get("apical_dominance", NAN))), "realized apical dominance passes through")
		_check(is_equal_approx(float(item.get("branch_probability", NAN)), float(topology.get("branch_probability", NAN))), "realized branch probability passes through")
		_check(is_equal_approx(float(item.get("branch_angle_deg", NAN)), float(topology.get("branch_angle_deg", NAN))), "realized branch angle passes through")
		_check(is_equal_approx(float(item.get("branch_length_ratio", NAN)), float(topology.get("branch_length_ratio", NAN))), "realized branch length ratio passes through")
		_check(int(item.get("branching_depth", -1)) == int(topology.get("branching_depth", -2)), "realized branching depth passes through")
		_check(is_equal_approx(float(item.get("crown_spread_m", NAN)), float(topology.get("crown_spread_m", NAN))), "realized crown spread passes through")
		_check(is_equal_approx(float(item.get("foliage_density", NAN)), float(potential.get("foliage_density", NAN))), "hereditary foliage potential remains explicitly separate")
		_check(String(item.get("silhouette_hash", "")).length() == 64, "morphology-only silhouette hash valid")
		unique_silhouettes[String(item.get("silhouette_hash", ""))] = true
	_check(unique_silhouettes.size() > 1, "live generation contains more than one source-derived morphology silhouette")

	var overlay = viewer.overlay
	var base: Dictionary = Dictionary(descriptors[0]).duplicate(true)
	var low: Dictionary = base.duplicate(true)
	var high: Dictionary = base.duplicate(true)

	low["realized_height_m"] = 1.0
	high["realized_height_m"] = 10.0
	_check(overlay.stem_height_px(high, 40.0) > overlay.stem_height_px(low, 40.0), "realized height monotonically changes stem height")

	low = base.duplicate(true); high = base.duplicate(true)
	low["realized_crown_radius_m"] = 0.4
	high["realized_crown_radius_m"] = 5.0
	_check(overlay.crown_radius_px(high, 40.0) > overlay.crown_radius_px(low, 40.0), "realized crown radius directly changes crown width")

	low = base.duplicate(true); high = base.duplicate(true)
	low["realized_crown_density"] = 0.08
	high["realized_crown_density"] = 0.92
	_check(overlay.crown_alpha(high) > overlay.crown_alpha(low), "realized crown density changes visual density alpha")
	_check(overlay.foliage_cluster_count(high) > overlay.foliage_cluster_count(low), "realized crown density changes foliage cluster count")

	low = base.duplicate(true); high = base.duplicate(true)
	low["structural_investment"] = 0.05
	high["structural_investment"] = 0.95
	_check(overlay.stem_width_px(high, 40.0) > overlay.stem_width_px(low, 40.0), "structural investment changes structural stem cue")

	low = base.duplicate(true); high = base.duplicate(true)
	low["branch_probability"] = 0.10; low["branching_depth"] = 1
	high["branch_probability"] = 0.95; high["branching_depth"] = 5
	_check(overlay.branch_count(high) > overlay.branch_count(low), "realized branching probability/depth change branch count")

	low = base.duplicate(true); high = base.duplicate(true)
	low["branch_angle_deg"] = 10.0; low["branch_length_ratio"] = 0.65
	high["branch_angle_deg"] = 70.0; high["branch_length_ratio"] = 0.65
	_check(overlay.branch_lateral_reach_px(high, 18.0) > overlay.branch_lateral_reach_px(low, 18.0), "realized branch angle changes silhouette spread")

	low = base.duplicate(true); high = base.duplicate(true)
	low["branch_angle_deg"] = 55.0; low["branch_length_ratio"] = 0.20
	high["branch_angle_deg"] = 55.0; high["branch_length_ratio"] = 0.95
	_check(overlay.branch_lateral_reach_px(high, 18.0) > overlay.branch_lateral_reach_px(low, 18.0), "realized branch length ratio changes branch reach")

	low = base.duplicate(true); high = base.duplicate(true)
	low["apical_dominance"] = 0.05
	high["apical_dominance"] = 0.95
	_check(overlay.crown_vertical_scale(high) > overlay.crown_vertical_scale(low), "realized apical dominance changes crown vertical silhouette")

	low = base.duplicate(true); high = base.duplicate(true)
	low["leaf_conservative_strategy"] = 0.05
	high["leaf_conservative_strategy"] = 0.95
	_check(overlay.leaf_cluster_radius_px(high, 18.0) < overlay.leaf_cluster_radius_px(low, 18.0), "leaf conservative strategy changes diagnostic leaf-size cue")

	var same_shape_a: Dictionary = base.duplicate(true)
	var same_shape_b: Dictionary = base.duplicate(true)
	same_shape_b["lineage_id"] = String(base.get("lineage_id", "")) + "/different-color"
	overlay.set_neutral_color(true)
	_check(overlay.foliage_color(same_shape_a) == overlay.foliage_color(same_shape_b), "neutral color removes lineage hue")
	_check(overlay.shape_signature(same_shape_a) == overlay.shape_signature(same_shape_b), "lineage identity does not change morphology shape signature")
	overlay.set_neutral_color(false)
	_check(overlay.foliage_color(same_shape_a) != overlay.foliage_color(same_shape_b), "optional lineage-color mode remains available")
	overlay.set_neutral_color(true)

	var state_before_presentation: Dictionary = viewer.get_view_state()
	_check(viewer.select_record(String(base.get("record_id", ""))), "diagnostic record selection works")
	_check(viewer.set_camera_state(2.3, Vector2(-22.0, 19.0)), "diagnostic zoom/pan works")
	_check(viewer.set_neutral_color(false), "diagnostic color mode can switch after evolution")
	_check(viewer.set_neutral_color(true), "diagnostic neutral mode can restore after evolution")
	var state_after_presentation: Dictionary = viewer.get_view_state()
	_check(String(state_after_presentation.get("ecology_state_hash", "")) == String(state_before_presentation.get("ecology_state_hash", "")), "selection/camera/color cannot mutate ecology")
	_check(String(state_after_presentation.get("diagnostic_render_hash", "")) == String(state_before_presentation.get("diagnostic_render_hash", "")), "neutral/lineage color mode cannot change shape/render source hash")

	var tampered_source: Dictionary = source1.duplicate(true)
	var source_descriptors: Array = Array(tampered_source.get("descriptors", []))
	var changed: Dictionary = Dictionary(source_descriptors[0]).duplicate(true)
	changed["functional_morphology"] = Dictionary(changed.get("functional_morphology", {})).duplicate(true)
	changed["functional_morphology"]["realized_crown_radius_m"] = float(changed["functional_morphology"].get("realized_crown_radius_m", 0.0)) + 0.5
	source_descriptors[0] = changed
	tampered_source["descriptors"] = source_descriptors
	_check(Mapper.new().build(tampered_source).is_empty(), "VIS4.2 rejects tampered Descriptor V2 instead of trusting unsealed morphology")

func _deterministic_replay(world, reference_viewer) -> void:
	var reference_state: Dictionary = reference_viewer.get_view_state()
	var reference_diag: Dictionary = reference_viewer.get_diagnostic_snapshot()
	_check(not reference_diag.is_empty() and int(reference_diag.get("descriptor_count", 0)) > 0, "reference diagnostic replay subject is non-vacuous")

	var replay = ViewerScene.instantiate()
	replay.auto_initialize = false
	replay.ensure_ui_built()
	root.add_child(replay)
	_check(replay.initialize_runtime(world), "VIS4.2 deterministic replay initializes")
	_check(replay.manual_step(1), "VIS4.2 deterministic replay advances")
	var replay_state: Dictionary = replay.get_view_state()
	var replay_diag: Dictionary = replay.get_diagnostic_snapshot()
	_check(not replay_diag.is_empty() and int(replay_diag.get("descriptor_count", 0)) > 0, "replay diagnostic subject is non-vacuous")
	_check(String(replay_state.get("ecology_state_hash", "")) == String(reference_state.get("ecology_state_hash", "")), "VIS4.2 does not perturb deterministic ecology")
	_check(String(replay_state.get("morphology_evidence_hash", "")) == String(reference_state.get("morphology_evidence_hash", "")), "VIS4.2 consumes deterministic morphology evidence")
	_check(String(replay_state.get("descriptor_v2_hash", "")) == String(reference_state.get("descriptor_v2_hash", "")), "Descriptor V2 source deterministic")
	_check(String(replay_diag.get("render_hash", "")) == String(reference_diag.get("render_hash", "")), "VIS4.2 diagnostic render hash deterministic")
	replay.queue_free()

func _source_guard() -> void:
	var mapper_source := FileAccess.get_file_as_string("res://scripts/labs/ecology/eco_evo7_vis4_2_diagnostic_morphology_mapper.gd").to_lower()
	var overlay_source := FileAccess.get_file_as_string("res://scripts/labs/ecology/eco_evo7_vis4_2_diagnostic_morphology_overlay.gd").to_lower()
	var viewer_source := FileAccess.get_file_as_string("res://scripts/labs/ecology/eco_evo7_vis4_2_diagnostic_morphology_viewer.gd").to_lower()
	var play0_source := FileAccess.get_file_as_string("res://scripts/labs/ecology/eco_evo7_play0_planet_presentation.gd").to_lower()

	_check(mapper_source.contains("eco_evo7_vis4_morphology_render_adapter.gd"), "VIS4.2 mapper imports Descriptor V2 as its only morphology source contract")
	_check(not overlay_source.contains("preload(") and not overlay_source.contains("load("), "VIS4.2 overlay imports no simulation/source implementation")
	_check(viewer_source.contains("eco_evo7_ls36_rule_workbench_v1.gd") and viewer_source.contains("eco_evo7_vis4_morphology_render_adapter.gd"), "VIS4.2 viewer uses public Workbench + Descriptor V2")
	for forbidden in [
		"plant_environment_coupled_development", "plant_functional_phenotype",
		"plant_growth_graph_skeleton", "plant_resource_model",
		"eco_evo7_ls34_local_competition",
	]:
		_check(not mapper_source.contains(forbidden) and not overlay_source.contains(forbidden) and not viewer_source.contains(forbidden), "VIS4.2 contains no biology import/call %s" % forbidden)
	_check(not overlay_source.contains("leaf_area_index_proxy"), "VIS4.2 crown mapping contains no LAI-to-crown heuristic")
	_check(overlay_source.contains("realized_crown_radius_m"), "VIS4.2 crown width reads realized crown radius directly")
	_check(overlay_source.contains("realized_crown_density"), "VIS4.2 crown density reads realized crown density directly")
	_check(not overlay_source.contains("individual_seed"), "VIS4.2 overlay adds no seed-driven shape randomness before VIS4.5")
	_check(not viewer_source.contains("boxmesh") and not viewer_source.contains("spheremesh"), "VIS4.2 does not create a competing Box/Sphere primary renderer")
	_check(play0_source.contains("boxmesh") and play0_source.contains("spheremesh"), "PLAY0 remains unchanged at VIS4.2 and is intentionally replaced only at VIS4.4")
	for source in [mapper_source, overlay_source, viewer_source]:
		_check(not source.contains("reproduce_bundle(") and not source.contains("mutation_seed(") and not source.contains("dispersal_seed("), "VIS4.2 owns no mutation/reproduction/dispersal authority")
		_check(not source.contains("fileaccess.open") and not source.contains("diraccess") and not source.contains("multiplayer"), "VIS4.2 owns no persistence/network authority")
	for archetype_token in ["tree_type", "bush_type", "grass_type", "tree_class", "bush_class", "grass_class", "tree_bush_grass"]:
		_check(not mapper_source.contains(archetype_token) and not overlay_source.contains(archetype_token), "VIS4.2 defines no canonical archetype %s" % archetype_token)

func _by_id(values: Array) -> Dictionary:
	var out := {}
	for value in values:
		if value is Dictionary:
			var item: Dictionary = value
			var record_id := String(item.get("record_id", ""))
			if not record_id.is_empty():
				out[record_id] = item
	return out

func _check(condition: bool, label: String) -> void:
	assertions += 1
	if not condition:
		failures.append(label)

func _finish() -> void:
	if failures.is_empty():
		print("ECO.EVO7 VIS4.2 Honest Diagnostic Morphology: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error("ECO.EVO7 VIS4.2 FAIL: %s" % failure)
	print("ECO.EVO7 VIS4.2 Honest Diagnostic Morphology: FAIL (%d assertions, %d failures)" % [assertions, failures.size()])
	quit(1)
