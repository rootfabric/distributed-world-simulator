extends SceneTree

const EarthWorld = preload("res://scripts/world/earth/procedural_earth_world.gd")
const Workbench = preload("res://scripts/ecology/shadow/eco_evo7_ls36_rule_workbench_v1.gd")
const MorphologyEvidence = preload("res://scripts/research/ecology/plant_morphology_evidence_v1.gd")
const AdapterV2 = preload("res://scripts/labs/ecology/eco_evo7_vis4_morphology_render_adapter.gd")

var assertions := 0
var failures: Array[String] = []

func _init() -> void:
	var world = EarthWorld.new()
	root.add_child(world)
	_check(world.setup(null), "real Earth initializes")

	var wb = Workbench.new()
	_check(wb.setup(world), "Workbench initializes from accepted ecology chain")

	_generation_zero_contract(wb)
	_generation_one_evidence(wb)
	_deterministic_replay(world, wb)
	_source_guard()

	world.queue_free()
	_finish()

func _generation_zero_contract(wb) -> void:
	var ecology: Dictionary = wb.get_ecology_snapshot()
	var state_hash := String(ecology.get("state_hash", ""))
	_check(int(ecology.get("generation", -1)) == 0, "VIS4.1 source starts at generation zero")
	_check(state_hash.length() == 64, "generation-zero ecology state hash valid")
	_check(wb.get_morphology_evidence().is_empty(), "generation zero has no fabricated realized morphology evidence")

	var adapter = AdapterV2.new()
	var result: Dictionary = adapter.build(ecology, {})
	_check(not result.is_empty(), "Descriptor V2 builds generation-zero founder view")
	_check(adapter.validate_result(result), "generation-zero Descriptor V2 validates")
	_check(int(result.get("descriptor_count", -1)) == int(ecology.get("record_count", -2)), "founder descriptor count matches living records")
	_check(int(result.get("morphology_evidence_count", -1)) == 0, "founders carry no realized morphology evidence")
	_check(int(result.get("founder_marker_count", -1)) == int(result.get("descriptor_count", -2)), "every generation-zero descriptor is explicitly founder-only")
	var first: Dictionary = Array(result["descriptors"])[0]
	_check(String(first.get("evidence_level", "")) == AdapterV2.FOUNDER_EVIDENCE, "founder evidence level explicit")
	_check(String(first.get("phenotype_hash", "")).is_empty(), "founder descriptor fabricates no phenotype hash")
	_check(Dictionary(first.get("realized_topology", {})).is_empty(), "founder descriptor fabricates no realized topology")
	_check(Dictionary(first.get("functional_morphology", {})).is_empty(), "founder descriptor fabricates no functional morphology")
	_check(Dictionary(first.get("potential_morphology", {})).keys().size() == MorphologyEvidence.POTENTIAL_FIELDS.size(), "founder descriptor exposes genetic potential only")
	_check(String(wb.get_ecology_snapshot().get("state_hash", "")) == state_hash, "reading founder presentation data cannot change ecology")

func _generation_one_evidence(wb) -> void:
	_check(not wb.advance_generations(1).is_empty(), "real ecology advances one generation")
	var ecology: Dictionary = wb.get_ecology_snapshot()
	var state_hash := String(ecology.get("state_hash", ""))
	var evidence: Dictionary = wb.get_morphology_evidence()

	_check(int(ecology.get("generation", -1)) == 1, "ecology source is generation one")
	_check(not evidence.is_empty(), "LS3.4 publishes morphology sidecar after phenotype pass")
	_check(MorphologyEvidence.validate_snapshot(evidence), "morphology evidence contract validates")
	_check(wb.validate_morphology_evidence(evidence), "Workbench validates current source binding")
	_check(bool(evidence.get("derived_representation", false)), "morphology evidence is explicitly derived")
	_check(bool(evidence.get("presentation_only", false)), "morphology evidence is explicitly presentation-only")
	_check(String(evidence.get("source_precompetition_population_hash", "")) == String(ecology.get("precompetition_population_hash", "")), "evidence binds precompetition population")
	_check(String(evidence.get("source_competition_hash", "")) == String(ecology.get("competition_hash", "")), "evidence binds exact competition field")
	_check(String(evidence.get("source_postcompetition_population_hash", "")) == String(ecology.get("postcompetition_population_hash", "")), "evidence binds exact survivor population")
	_check(int(evidence.get("record_count", -1)) == int(ecology.get("record_count", -2)), "evidence contains exactly current living plants")
	_check(String(wb.get_ecology_snapshot().get("state_hash", "")) == state_hash, "publishing/reading morphology evidence leaves ecology state hash unchanged")

	var evidence_by_id := _by_id(Array(evidence.get("records", [])), "record_id")
	var evaluations_by_id := _by_id(Array(Dictionary(ecology.get("competition_field", {})).get("evaluations", [])), "record_id")
	var current_records: Array = Array(ecology.get("records", []))
	_check(evidence_by_id.size() == current_records.size(), "every living plant has one evidence record")
	for value in current_records:
		if not value is Dictionary:
			_check(false, "living record dictionary")
			continue
		var record: Dictionary = value
		var record_id := String(record["record_id"])
		_check(evidence_by_id.has(record_id), "evidence matches living record %s" % record_id)
		if not evidence_by_id.has(record_id):
			continue
		var item: Dictionary = evidence_by_id[record_id]
		_check(String(item["bundle_checksum"]) == String(record["bundle_checksum"]), "evidence bundle checksum exact for %s" % record_id)
		_check(int(item["cell_index"]) == int(record["cell_index"]), "evidence cell identity exact for %s" % record_id)
		_check(evaluations_by_id.has(record_id) and bool(Dictionary(evaluations_by_id[record_id]).get("survives", false)), "evidence record corresponds to surviving LS3.4 evaluation")
		if evaluations_by_id.has(record_id):
			_check(String(item["source_phenotype_hash"]) == String(Dictionary(evaluations_by_id[record_id]).get("phenotype_hash", "")), "evidence phenotype hash equals LS3.4 evaluation")

	var adapter = AdapterV2.new()
	var result: Dictionary = adapter.build(ecology, evidence)
	_check(not result.is_empty(), "Descriptor V2 consumes exact ecology + morphology sidecar")
	_check(adapter.validate_result(result), "Descriptor V2 validates")
	_check(String(result.get("source_ecology_state_hash", "")) == state_hash, "Descriptor V2 binds exact ecology state")
	_check(String(result.get("source_competition_hash", "")) == String(ecology.get("competition_hash", "")), "Descriptor V2 binds exact competition")
	_check(String(result.get("source_morphology_evidence_hash", "")) == String(evidence.get("evidence_hash", "")), "Descriptor V2 binds exact morphology sidecar")
	_check(int(result.get("morphology_evidence_count", -1)) == int(ecology.get("record_count", -2)), "all live descriptors are morphology-evidence backed")
	_check(int(result.get("founder_marker_count", -1)) == 0, "generation one contains no founder fallback")

	if not Array(result["descriptors"]).is_empty():
		var descriptor: Dictionary = Array(result["descriptors"])[0]
		var record_id := String(descriptor["record_id"])
		var item: Dictionary = evidence_by_id[record_id]
		var evaluation: Dictionary = evaluations_by_id[record_id]
		_check(int(descriptor["individual_seed"]) == int(item["individual_seed"]), "Descriptor V2 preserves individual seed")
		_check(String(descriptor["phenotype_hash"]) == String(item["source_phenotype_hash"]), "Descriptor V2 preserves phenotype hash")
		_check(String(descriptor["plasticity_phenotype_hash"]) == String(item["source_plasticity_phenotype_hash"]), "Descriptor V2 preserves PH2 phenotype seal")
		_check(String(descriptor["growth_graph_hash"]) == String(item["source_growth_graph_hash"]), "Descriptor V2 preserves exact GrowthGraph seal")
		_check(String(descriptor["source_evidence_record_hash"]) == String(item["evidence_hash"]), "Descriptor V2 preserves evidence-record seal")
		_check(String(descriptor["source_evaluation_hash"]) == String(evaluation["evaluation_hash"]), "Descriptor V2 preserves LS3.4 evaluation seal")
		_check(Dictionary(descriptor["potential_morphology"]) == Dictionary(item["potential_morphology"]), "genetic potential passes through byte-semantically")
		_check(Dictionary(descriptor["realized_topology"]) == Dictionary(item["realized_topology"]), "realized PH2 topology passes through without renderer recomputation")
		_check(Dictionary(descriptor["functional_morphology"]) == Dictionary(item["functional_morphology"]), "functional morphology passes through without renderer recomputation")
		var context: Dictionary = descriptor["competition_context"]
		_check(is_equal_approx(float(context["water_satisfaction"]), float(evaluation["water_satisfaction"])), "competition water context exact")
		_check(is_equal_approx(float(context["effective_light"]), float(evaluation["effective_light"])), "competition light context exact")
		_check(is_equal_approx(float(context["realized_resource_balance"]), float(evaluation["realized_resource_balance"])), "competition resource context exact")
		_check(Dictionary(descriptor["functional_morphology"]).has("realized_crown_radius_m"), "Descriptor V2 exposes realized crown radius")
		_check(Dictionary(descriptor["functional_morphology"]).has("realized_crown_density"), "Descriptor V2 exposes realized crown density")
		_check(Dictionary(descriptor["functional_morphology"]).has("structural_investment"), "Descriptor V2 exposes structural investment")
		_check(Dictionary(descriptor["realized_topology"]).has("branch_angle_deg"), "Descriptor V2 exposes realized branch angle")
		_check(Dictionary(descriptor["realized_topology"]).has("branch_probability"), "Descriptor V2 exposes realized branch probability")
		_check(Dictionary(descriptor["potential_morphology"]).has("branch_angle_deg"), "Descriptor V2 keeps genetic potential separately")

	var tampered: Dictionary = evidence.duplicate(true)
	if not Array(tampered["records"]).is_empty():
		var changed: Dictionary = Dictionary(Array(tampered["records"])[0]).duplicate(true)
		changed["functional_morphology"] = Dictionary(changed["functional_morphology"]).duplicate(true)
		changed["functional_morphology"]["realized_crown_radius_m"] = float(changed["functional_morphology"]["realized_crown_radius_m"]) + 0.25
		tampered["records"][0] = changed
		_check(not MorphologyEvidence.validate_snapshot(tampered), "morphology value tamper fails sealed evidence validation")
		_check(adapter.build(ecology, tampered).is_empty(), "Descriptor V2 fails closed on tampered morphology evidence")

	var wrong_source: Dictionary = evidence.duplicate(true)
	wrong_source["source_postcompetition_population_hash"] = "f".repeat(64)
	wrong_source["evidence_hash"] = MorphologyEvidence.snapshot_hash(wrong_source)
	_check(MorphologyEvidence.validate_snapshot(wrong_source), "rehash can make standalone morphology envelope internally valid")
	_check(not wb.validate_morphology_evidence(wrong_source), "Workbench rejects internally valid evidence bound to wrong live population")
	_check(adapter.build(ecology, wrong_source).is_empty(), "Descriptor V2 rejects wrong population binding")

func _deterministic_replay(world, reference_wb) -> void:
	var reference_ecology: Dictionary = reference_wb.get_ecology_snapshot()
	var reference_evidence: Dictionary = reference_wb.get_morphology_evidence()
	var reference_adapter := AdapterV2.new().build(reference_ecology, reference_evidence)

	var replay = Workbench.new()
	_check(replay.setup(world), "deterministic replay Workbench initializes")
	_check(not replay.advance_generations(1).is_empty(), "deterministic replay advances")
	var replay_ecology: Dictionary = replay.get_ecology_snapshot()
	var replay_evidence: Dictionary = replay.get_morphology_evidence()
	var replay_adapter := AdapterV2.new().build(replay_ecology, replay_evidence)
	_check(String(replay_ecology.get("state_hash", "")) == String(reference_ecology.get("state_hash", "")), "VIS4.1 does not perturb deterministic ecology replay")
	_check(String(replay_evidence.get("evidence_hash", "")) == String(reference_evidence.get("evidence_hash", "")), "morphology evidence hash deterministic")
	_check(String(replay_adapter.get("adapter_hash", "")) == String(reference_adapter.get("adapter_hash", "")), "Descriptor V2 hash deterministic")

func _source_guard() -> void:
	var ls34 := FileAccess.get_file_as_string("res://scripts/ecology/shadow/eco_evo7_ls34_local_competition_v1.gd")
	var adapter := FileAccess.get_file_as_string("res://scripts/labs/ecology/eco_evo7_vis4_morphology_render_adapter.gd").to_lower()
	var evidence := FileAccess.get_file_as_string("res://scripts/research/ecology/plant_morphology_evidence_v1.gd").to_lower()
	_check(_count(ls34, "CoupledDevelopment.realize(") == 1, "LS3.4 contains one PH2 realization call site")
	_check(_count(ls34, "FunctionalPhenotype.compile(") == 1, "LS3.4 contains one FunctionalPhenotype compile call site")
	_check(ls34.contains("MorphologyEvidence.build_record("), "LS3.4 packages evidence from already-computed PH2/functional values")
	var evidence_build_at := ls34.find("var morphology_evidence := MorphologyEvidence.build_record(")
	var provisional_at := ls34.find("provisional.append({", evidence_build_at)
	var evidence_build_block := ls34.substr(evidence_build_at, provisional_at - evidence_build_at) if evidence_build_at >= 0 and provisional_at > evidence_build_at else ""
	_check(not evidence_build_block.contains("return {}"), "morphology evidence packaging cannot abort ecology generation")
	_check(ls34.contains("get_morphology_evidence"), "LS3.4 exposes separate sidecar API")
	_check(not adapter.contains("plant_environment_coupled_development") and not adapter.contains("plant_functional_phenotype") and not adapter.contains("resource_model"), "Descriptor V2 imports no biology implementation")
	_check(not evidence.contains("plant_environment_coupled_development") and not evidence.contains("plant_functional_phenotype") and not evidence.contains("resource_model"), "morphology evidence contract contains no biology implementation")
	for source in [adapter, evidence]:
		_check(not source.contains("reproduce_bundle(") and not source.contains("mutation_seed(") and not source.contains("dispersal_seed("), "VIS4.1 owns no mutation/reproduction/dispersal authority")
		_check(not source.contains("fileaccess.open") and not source.contains("diraccess") and not source.contains("multiplayer"), "VIS4.1 owns no persistence/network authority")
	_check(not adapter.contains("coupleddevelopment.realize") and not adapter.contains("functionalphenotype.compile"), "Descriptor V2 cannot recompute phenotype")
	for archetype_token in ["tree_type", "bush_type", "grass_type", "tree_class", "bush_class", "grass_class", "tree_bush_grass"]:
		_check(not adapter.contains(archetype_token), "Descriptor V2 defines no canonical archetype token %s" % archetype_token)

func _by_id(values: Array, key: String) -> Dictionary:
	var out := {}
	for value in values:
		if not value is Dictionary:
			continue
		var item: Dictionary = value
		var identity := String(item.get(key, ""))
		if not identity.is_empty():
			out[identity] = item
	return out

func _count(source: String, token: String) -> int:
	var count := 0
	var offset := 0
	while true:
		var index := source.find(token, offset)
		if index < 0:
			return count
		count += 1
		offset = index + token.length()
	return count

func _check(condition: bool, label: String) -> void:
	assertions += 1
	if not condition:
		failures.append(label)

func _finish() -> void:
	if failures.is_empty():
		print("ECO.EVO7 VIS4.1 Source-Bound Morphology Evidence: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error("ECO.EVO7 VIS4.1 FAIL: %s" % failure)
	print("ECO.EVO7 VIS4.1 Source-Bound Morphology Evidence: FAIL (%d assertions, %d failures)" % [assertions, failures.size()])
	quit(1)
