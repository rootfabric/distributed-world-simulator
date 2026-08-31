extends SceneTree

const Playground = preload("res://scripts/labs/ecology/eco_evo7_play0_live_planet_playground.gd")
const DiversityEvidence = preload("res://scripts/labs/ecology/eco_evo7_vis4_8_diversity_evidence.gd")
const Traits = preload("res://scripts/research/ecology/plant_development_traits_v1.gd")
const GrowthGraph = preload("res://scripts/research/ecology/plant_growth_graph_skeleton_v1.gd")
const RenderDescription = preload("res://scripts/research/ecology/plant_render_description_v1.gd")
const DiagnosticOverlay = preload("res://scripts/labs/ecology/eco_evo7_vis4_2_diagnostic_morphology_overlay.gd")

var assertions := 0
var failures: Array[String] = []
var _finished := false


func _init() -> void:
	call_deferred("_run")
	call_deferred("_watchdog")


func _run() -> void:
	_controlled_renderer_fidelity()
	_controlled_live_diversity_contract()

	var playground = Playground.new()
	playground.auto_initialize = false
	root.add_child(playground)
	await process_frame
	await process_frame

	_check(playground.initialize_runtime(), "VIS4.8 PLAY0 runtime initializes")
	if not playground.ready_success:
		_finish("")
		return

	var presentation = playground.get_presentation()
	_check(presentation != null, "VIS4.8 presentation exists")
	_check(not playground.is_diversity_evidence_visible(), "VIS4.8 evidence panel starts hidden")
	_check(playground.get_diversity_evidence_state().is_empty(), "generation-zero diversity evidence starts empty")

	var panel: PanelContainer = playground.get_node_or_null("Play0HUD/VIS48DiversityEvidencePanel") as PanelContainer
	var label: Label = playground.get_node_or_null("Play0HUD/VIS48DiversityEvidencePanel/VIS48DiversityEvidenceText") as Label
	_check(panel != null and not panel.visible, "VIS4.8 panel node starts hidden")
	_check(label != null, "VIS4.8 evidence label exists")
	if panel != null:
		_check(panel.mouse_filter == Control.MOUSE_FILTER_IGNORE, "VIS4.8 panel cannot intercept gameplay mouse")
	if label != null:
		_check(label.mouse_filter == Control.MOUSE_FILTER_IGNORE, "VIS4.8 label cannot intercept gameplay mouse")

	var g0_hash := String(playground.get_published_snapshot().get("ecology_state_hash", ""))
	_check(playground.set_diversity_evidence_visible(true), "VIS4.8 F7-equivalent opens generation-zero evidence panel")
	_check(playground.is_diversity_evidence_visible(), "VIS4.8 generation-zero panel visible")
	_check(playground.get_diversity_evidence_state().is_empty(), "VIS4.8 generation zero fabricates no diversity report")
	_check(playground.get_diversity_evidence_text().contains("Unavailable until a completed generation > 0"), "VIS4.8 generation-zero panel states source boundary")
	_check(String(playground.get_published_snapshot().get("ecology_state_hash", "")) == g0_hash, "VIS4.8 generation-zero panel cannot mutate ecology")
	_check(not playground.toggle_diversity_evidence(), "VIS4.8 F7 toggle closes generation-zero panel")

	_check(playground.request_generation(), "VIS4.8 generation request accepted")
	_check(await _wait_generation(playground, 60000), "VIS4.8 generation one completes")

	var published: Dictionary = playground.get_published_snapshot()
	var descriptor_snapshot: Dictionary = playground.get_published_morphology_descriptors()
	var descriptors: Array = Array(descriptor_snapshot.get("descriptors", []))
	var ecology_hash := String(published.get("ecology_state_hash", ""))
	_check(int(published.get("generation", -1)) == 1, "VIS4.8 live source is completed generation one")
	_check(ecology_hash.length() == 64, "VIS4.8 live ecology hash valid")
	_check(not descriptors.is_empty(), "VIS4.8 live Descriptor V2 population non-empty")

	var geometry_before: String = presentation.get_ph5_geometry_identity_hash()
	var individuality_before: String = presentation.get_ph5_individuality_identity_hash()
	var appearance_before: String = presentation.get_ph5_grid_appearance_identity_hash()

	_check(playground.set_diversity_evidence_visible(true), "VIS4.8 opens live diversity evidence")
	var report: Dictionary = playground.get_diversity_evidence_state()
	_check(not report.is_empty() and DiversityEvidence.validate(report), "VIS4.8 live diversity report validates")
	if report.is_empty():
		playground.queue_free()
		await process_frame
		_finish("")
		return

	_check(int(report.get("population", -1)) == descriptors.size(), "VIS4.8 live report covers exact population")
	_check(int(report.get("metric_count", -1)) == DiversityEvidence.METRICS.size(), "VIS4.8 reports all fixed morphology metrics")
	_check(int(report.get("cluster_count", 0)) >= 1, "VIS4.8 reports at least one morphology cluster")
	_check(int(report.get("unique_descriptor_count", 0)) >= 1, "VIS4.8 reports descriptor identity diversity")
	_check(int(report.get("unique_growth_graph_count", 0)) >= 1, "VIS4.8 reports GrowthGraph identity diversity")
	_check(int(report.get("unique_render_description_count", 0)) >= 1, "VIS4.8 reports render-description identity diversity")
	_check(String(report.get("renderer_fidelity_gate", "")) == DiversityEvidence.RENDERER_GATE, "VIS4.8 live report keeps renderer gate independent")
	_check(
		String(report.get("live_diversity_status", "")) in [
			DiversityEvidence.LIVE_STATUS_SUFFICIENT,
			DiversityEvidence.LIVE_STATUS_INSUFFICIENT,
		],
		"VIS4.8 live report emits honest bounded diversity status"
	)

	_check(not bool(report.get("archetype_classification", true)), "VIS4.8 live report defines no morphology archetypes")
	_check(not bool(report.get("lineage_counts_as_morphology", true)), "VIS4.8 excludes lineage from morphology diversity")
	_check(not bool(report.get("seed_counts_as_morphology", true)), "VIS4.8 excludes seed from morphology diversity")
	_check(not bool(report.get("yaw_counts_as_morphology", true)), "VIS4.8 excludes yaw from morphology diversity")
	_check(not bool(report.get("scatter_counts_as_morphology", true)), "VIS4.8 excludes visual scatter from morphology diversity")

	var render_identities: Array = []
	for index in range(descriptors.size()):
		render_identities.append(presentation.get_ph5_record_identity(index))
	var replay: Dictionary = DiversityEvidence.build(1, ecology_hash, descriptor_snapshot, render_identities)
	_check(not replay.is_empty(), "VIS4.8 exact live report replay builds")
	_check(String(replay.get("evidence_hash", "")) == String(report.get("evidence_hash", "")), "VIS4.8 live report deterministic replay exact")
	_check(Dictionary(replay.get("metrics", {})) == Dictionary(report.get("metrics", {})), "VIS4.8 live variance metrics replay exact")
	_check(Array(replay.get("cluster_histogram", [])) == Array(report.get("cluster_histogram", [])), "VIS4.8 live morphology clusters replay exact")

	var text_value: String = playground.get_diversity_evidence_text()
	for required in [
		"VIS4.8 DIVERSITY EVIDENCE",
		"renderer fidelity: CONTROLLED ACCEPTANCE GATE",
		"live diversity:",
		"MORPHOLOGY VARIANCE",
		"NO TREE/BUSH/GRASS ARCHETYPES",
		"lineage / seed / yaw / visual scatter are excluded",
		"realized_height_m",
		"realized_crown_radius_m",
		"branch_angle_deg",
		"foliage_density",
	]:
		_check(text_value.contains(required), "VIS4.8 panel exposes %s" % required)
	_check(text_value.contains(String(report.get("evidence_hash", ""))), "VIS4.8 panel exposes full evidence hash")

	var status: Dictionary = playground.get_play0_status()
	_check(bool(status.get("diversity_evidence_visible", false)), "VIS4.8 PLAY0 status reports evidence panel visible")
	_check(String(status.get("diversity_evidence_hash", "")) == String(report.get("evidence_hash", "")), "VIS4.8 PLAY0 status exposes exact evidence hash")
	_check(String(status.get("live_diversity_status", "")) == String(report.get("live_diversity_status", "")), "VIS4.8 PLAY0 status exposes live diversity status")
	_check(int(status.get("morphology_cluster_count", -1)) == int(report.get("cluster_count", -2)), "VIS4.8 PLAY0 status exposes morphology cluster count")
	_check(int(status.get("morphology_varying_field_count", -1)) == int(report.get("varying_field_count", -2)), "VIS4.8 PLAY0 status exposes varying-field count")

	_check(String(playground.get_published_snapshot().get("ecology_state_hash", "")) == ecology_hash, "VIS4.8 evidence generation cannot mutate ecology")
	_check(presentation.get_ph5_geometry_identity_hash() == geometry_before, "VIS4.8 cannot change PH5 geometry identity")
	_check(presentation.get_ph5_individuality_identity_hash() == individuality_before, "VIS4.8 cannot change VIS4.5 individuality identity")
	_check(presentation.get_ph5_grid_appearance_identity_hash() == appearance_before, "VIS4.8 cannot change VIS4.6 appearance identity")

	# F6 and F7 intentionally share one diagnostic HUD slot.
	_check(playground.set_morphology_inspector_visible(true), "VIS4.8 can switch to VIS4.7 inspector")
	_check(playground.is_morphology_inspector_visible(), "VIS4.7 inspector becomes visible")
	_check(not playground.is_diversity_evidence_visible(), "opening F6 hides F7 panel without changing evidence")
	_check(playground.set_diversity_evidence_visible(true), "VIS4.8 reopens after inspector")
	_check(not playground.is_morphology_inspector_visible(), "opening F7 hides F6 panel")
	_check(String(playground.get_diversity_evidence_state().get("evidence_hash", "")) == String(report.get("evidence_hash", "")), "F6/F7 panel switching preserves exact diversity evidence")

	var tampered_render: Array = render_identities.duplicate(true)
	var first_render: Dictionary = Dictionary(tampered_render[0]).duplicate(true)
	first_render["source_descriptor_hash"] = "f".repeat(64)
	tampered_render[0] = first_render
	_check(
		DiversityEvidence.build(1, ecology_hash, descriptor_snapshot, tampered_render).is_empty(),
		"VIS4.8 rejects render identity bound to another descriptor"
	)

	_source_guard()

	var live_status := String(report.get("live_diversity_status", ""))
	print("VIS4.8 RENDERER FIDELITY: PASS")
	print("VIS4.8 LIVE DIVERSITY: %s" % live_status)

	playground.queue_free()
	await process_frame
	_finish(live_status)


func _controlled_renderer_fidelity() -> void:
	var seed := 424242

	var low := _ph5_probe("low", 1.6, 0.40, 0.35, 0.75, 42.0, 0.90, 3, 2.0, seed)
	var tall := _ph5_probe("tall", 8.0, 0.40, 0.35, 0.75, 42.0, 0.90, 3, 2.0, seed)
	_check(not low.is_empty() and not tall.is_empty(), "controlled PH5 tall/low probes build")
	_check(float(tall["height_m"]) > float(low["height_m"]) + 5.0, "controlled PH5 tall/low changes rendered bounds height")
	_check(String(tall["render_hash"]) != String(low["render_hash"]), "controlled PH5 tall/low changes render description")

	var narrow := _ph5_probe("narrow", 5.0, 0.80, 0.0, 1.0, 55.0, 2.0, 6, 0.25, seed)
	var wide := _ph5_probe("wide", 5.0, 0.80, 0.0, 1.0, 55.0, 2.0, 6, 6.0, seed)
	_check(float(wide["radius_m"]) > float(narrow["radius_m"]) + 0.20, "controlled PH5 narrow/wide changes horizontal crown extent")
	_check(String(wide["render_hash"]) != String(narrow["render_hash"]), "controlled PH5 narrow/wide changes render description")

	var vertical := _ph5_probe("vertical", 5.0, 0.45, 0.35, 0.0, 42.0, 0.90, 4, 2.5, seed)
	var bushy := _ph5_probe("bushy", 5.0, 0.45, 0.0, 1.0, 42.0, 1.10, 4, 2.5, seed)
	_check(int(vertical["lateral_segments"]) == 0, "controlled PH5 vertical fixture has no lateral branches")
	_check(int(bushy["lateral_segments"]) > int(vertical["lateral_segments"]), "controlled PH5 bushy fixture has more lateral branches")
	_check(int(bushy["foliage_count"]) > int(vertical["foliage_count"]), "controlled PH5 bushy fixture produces denser structural foliage")

	var sparse := _ph5_probe("sparse", 5.0, 0.50, 0.0, 1.0, 45.0, 1.0, 1, 3.0, seed)
	var dense := _ph5_probe("dense", 5.0, 0.50, 0.0, 1.0, 45.0, 1.0, 6, 3.0, seed)
	_check(int(dense["lateral_segments"]) > int(sparse["lateral_segments"]), "controlled PH5 sparse/dense changes branch primitive population")
	_check(int(dense["foliage_count"]) > int(sparse["foliage_count"]), "controlled PH5 sparse/dense changes foliage anchor population")

	var low_angle := _ph5_probe("angle-low", 5.0, 0.50, 0.0, 1.0, 12.0, 1.0, 4, 3.0, seed)
	var high_angle := _ph5_probe("angle-high", 5.0, 0.50, 0.0, 1.0, 70.0, 1.0, 4, 3.0, seed)
	_check(float(high_angle["mean_angle_deg"]) > float(low_angle["mean_angle_deg"]) + 30.0, "controlled PH5 branch angle changes actual lateral geometry")
	_check(String(high_angle["render_hash"]) != String(low_angle["render_hash"]), "controlled PH5 branch angle changes render description")

	# VIS4.2 remains the accepted explicit realized-crown-density cue.
	var overlay = DiagnosticOverlay.new()
	var sparse_crown := {"realized_crown_density": 0.10}
	var dense_crown := {"realized_crown_density": 0.90}
	_check(overlay.crown_alpha(dense_crown) > overlay.crown_alpha(sparse_crown), "controlled realized crown density changes accepted visual alpha")
	_check(overlay.foliage_cluster_count(dense_crown) > overlay.foliage_cluster_count(sparse_crown), "controlled realized crown density changes accepted foliage cluster cue")
	overlay.free()


func _ph5_probe(
	id: String,
	max_height: float,
	internode: float,
	apical: float,
	branch_probability: float,
	angle_deg: float,
	length_ratio: float,
	depth: int,
	crown_spread: float,
	seed: int
) -> Dictionary:
	var traits: Dictionary = Traits.create(
		"vis4.8/" + id,
		max_height,
		internode,
		apical,
		branch_probability,
		angle_deg,
		length_ratio,
		depth,
		crown_spread
	)
	if not bool(Traits.validate(traits).get("success", false)):
		return {}
	var graph: Dictionary = GrowthGraph.build(traits, seed)
	if graph.is_empty():
		return {}
	var description: Dictionary = RenderDescription.build(graph)
	if description.is_empty():
		return {}
	var metrics: Dictionary = Dictionary(graph.get("metrics", {}))
	var bounds: Dictionary = Dictionary(description.get("bounds", {}))
	return {
		"graph_hash": String(graph.get("graph_hash", "")),
		"render_hash": String(description.get("render_description_hash", "")),
		"height_m": float(bounds.get("height_m", 0.0)),
		"radius_m": float(bounds.get("radius_xz_m", 0.0)),
		"lateral_segments": int(metrics.get("lateral_segment_count", 0)),
		"mean_angle_deg": float(metrics.get("mean_lateral_angle_deg", 0.0)),
		"foliage_count": Array(description.get("foliage_anchors", [])).size(),
	}


func _controlled_live_diversity_contract() -> void:
	var collapsed_descriptors: Array = []
	var collapsed_renders: Array = []
	for i in range(8):
		var pair := _controlled_pair(i, false)
		collapsed_descriptors.append(pair["descriptor"])
		collapsed_renders.append(pair["render"])
	var collapsed_snapshot := {
		"generation": 1,
		"source_ecology_state_hash": "a".repeat(64),
		"adapter_hash": "b".repeat(64),
		"descriptor_count": collapsed_descriptors.size(),
		"descriptors": collapsed_descriptors,
	}
	var collapsed: Dictionary = DiversityEvidence.build(1, "a".repeat(64), collapsed_snapshot, collapsed_renders)
	_check(not collapsed.is_empty() and DiversityEvidence.validate(collapsed), "controlled collapsed diversity report validates")
	_check(int(collapsed.get("lineage_count_diagnostic_only", 0)) == 8, "collapsed fixture has eight distinct lineages")
	_check(int(collapsed.get("unique_render_description_count", 0)) == 8, "collapsed fixture has eight distinct render identities")
	_check(int(collapsed.get("cluster_count", 0)) == 1, "distinct lineages/render identities do not fabricate morphology clusters")
	_check(int(collapsed.get("varying_field_count", -1)) == 0, "collapsed morphology has zero varying morphology fields")
	_check(String(collapsed.get("live_diversity_status", "")) == DiversityEvidence.LIVE_STATUS_INSUFFICIENT, "collapsed morphology reports LIVE_DIVERSITY_INSUFFICIENT")

	var diverse_descriptors: Array = []
	var diverse_renders: Array = []
	for i in range(8):
		var pair := _controlled_pair(i, true)
		diverse_descriptors.append(pair["descriptor"])
		diverse_renders.append(pair["render"])
	var diverse_snapshot := {
		"generation": 1,
		"source_ecology_state_hash": "c".repeat(64),
		"adapter_hash": "d".repeat(64),
		"descriptor_count": diverse_descriptors.size(),
		"descriptors": diverse_descriptors,
	}
	var diverse: Dictionary = DiversityEvidence.build(1, "c".repeat(64), diverse_snapshot, diverse_renders)
	_check(not diverse.is_empty() and DiversityEvidence.validate(diverse), "controlled diverse report validates")
	_check(int(diverse.get("cluster_count", 0)) >= DiversityEvidence.MIN_CLUSTER_COUNT, "controlled diverse morphology crosses cluster threshold")
	_check(int(diverse.get("varying_field_count", 0)) >= DiversityEvidence.MIN_VARYING_FIELDS, "controlled diverse morphology crosses varying-field threshold")
	_check(String(diverse.get("live_diversity_status", "")) == DiversityEvidence.LIVE_STATUS_SUFFICIENT, "controlled diverse morphology reports LIVE_DIVERSITY_SUFFICIENT")


func _controlled_pair(index: int, varied: bool) -> Dictionary:
	var record_id := "vis4.8/record/%02d" % index
	var descriptor_hash := (record_id + "/descriptor").sha256_text()
	var graph_hash := (record_id + "/graph").sha256_text()
	var delta := float(index) if varied else 0.0
	var descriptor := {
		"record_id": record_id,
		"lineage_id": "lineage/%02d" % index,
		"descriptor_hash": descriptor_hash,
		"growth_graph_hash": graph_hash,
		"functional_morphology": {
			"realized_height_m": 3.0 + delta * 0.50,
			"realized_crown_radius_m": 1.0 + delta * 0.20,
			"realized_crown_density": 0.40 + delta * 0.05,
			"leaf_area_index_proxy": 1.5 + delta * 0.10,
			"structural_investment": 0.40 + delta * 0.05,
			"realized_root_depth_m": 1.0 + delta * 0.10,
			"realized_root_spread_m": 1.4 + delta * 0.10,
		},
		"realized_topology": {
			"apical_dominance": 0.40 + delta * 0.04,
			"branch_probability": 0.35 + delta * 0.06,
			"branch_angle_deg": 30.0 + delta * 3.0,
			"branch_length_ratio": 0.70 + delta * 0.05,
			"branching_depth": 2 + (index % 3 if varied else 0),
			"crown_spread_m": 1.5 + delta * 0.15,
		},
		"potential_morphology": {
			"foliage_density": 0.45 + delta * 0.05,
		},
	}
	var render := {
		"record_id": record_id,
		"source_descriptor_hash": descriptor_hash,
		"source_growth_graph_hash": graph_hash,
		"render_description_hash": (record_id + "/render").sha256_text(),
	}
	return {"descriptor": descriptor, "render": render}


func _source_guard() -> void:
	var evidence_source := FileAccess.get_file_as_string("res://scripts/labs/ecology/eco_evo7_vis4_8_diversity_evidence.gd").to_lower()
	var playground_source := FileAccess.get_file_as_string("res://scripts/labs/ecology/eco_evo7_play0_live_planet_playground.gd").to_lower()

	_check(playground_source.contains("key_f7"), "VIS4.8 PLAY0 binds F7")
	_check(playground_source.contains("_refresh_diversity_evidence"), "VIS4.8 PLAY0 refreshes evidence only from published source")
	_check(evidence_source.contains("lineage_counts_as_morphology") and evidence_source.contains("false"), "VIS4.8 explicitly excludes lineage as morphology")
	_check(evidence_source.contains("seed_counts_as_morphology") and evidence_source.contains("false"), "VIS4.8 explicitly excludes seed as morphology")
	_check(evidence_source.contains("yaw_counts_as_morphology") and evidence_source.contains("false"), "VIS4.8 explicitly excludes yaw as morphology")
	_check(evidence_source.contains("scatter_counts_as_morphology") and evidence_source.contains("false"), "VIS4.8 explicitly excludes VIS4.6 scatter as morphology")
	_check(not evidence_source.contains("randi") and not evidence_source.contains("randf") and not evidence_source.contains("randomize"), "VIS4.8 uses no process RNG")
	for token in ["tree_type", "bush_type", "grass_type", "tree_class", "bush_class", "grass_class", "tree_bush_grass"]:
		_check(not evidence_source.contains(token), "VIS4.8 defines no canonical archetype %s" % token)
	_check(not evidence_source.contains("growthgraph.build"), "VIS4.8 live evidence model does not invoke GrowthGraph")
	_check(not evidence_source.contains("functionalphenotype") and not evidence_source.contains("coupleddevelopment"), "VIS4.8 live evidence model does not recompute biology")
	_check(not evidence_source.contains("fileaccess.open") and not evidence_source.contains("diraccess") and not evidence_source.contains("multiplayer"), "VIS4.8 live evidence owns no persistence/network authority")


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
		push_error("ECO.EVO7 VIS4.8 watchdog timeout")
		print("ECO.EVO7 VIS4.8 Diversity Evidence: FAIL (watchdog timeout)")
		quit(1)


func _check(condition: bool, label: String) -> void:
	assertions += 1
	if not condition:
		failures.append(label)
		push_error("VIS4.8: " + label)


func _finish(live_status: String) -> void:
	if _finished:
		return
	_finished = true
	if failures.is_empty():
		if not live_status.is_empty():
			print("ECO.EVO7 VIS4.8 live population qualification: %s" % live_status)
		print("ECO.EVO7 VIS4.8 Diversity Evidence: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		print("FAIL: " + failure)
	print("ECO.EVO7 VIS4.8 Diversity Evidence: FAIL (%d/%d)" % [failures.size(), assertions])
	quit(1)
