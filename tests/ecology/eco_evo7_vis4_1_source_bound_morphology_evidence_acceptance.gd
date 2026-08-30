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
	if result.is_empty():
		return
	_check(adapter.validate_result(result), "generation-zero Descriptor V2 validates")
	_check(int(result.get("descriptor_count", -1)) == int(ecology.get("record_count", -2)), "founder descriptor count matches living records")
	_check(int(result.get("morphology_evidence_count", -1)) == 0, "founders carry no realized morphology evidence")
	_check(int(result.get("founder_marker_count", -1)) == int(result.get("descriptor_count", -2)), "every generation-zero descriptor is explicitly founder-only")

	var descriptors: Array = Array(result.get("descriptors", []))
	_check(not descriptors.is_empty(), "generation-zero descriptor set is non-empty")
	if descriptors.is_empty() or not descriptors[0] is Dictionary:
		return
	var first: Dictionary = descriptors[0]
	_check(String(first.get("evidence_level", "")) == AdapterV2.FOUNDER_EVIDENCE, "founder evidence level explicit")
	_check(int(first.get("hereditary_individual_seed", -1)) >= 0, "founder descriptor exposes hereditary individual seed")
	_check(int(first.get("development_individual_seed", -2)) == -1, "founder descriptor fabricates no development seed")
	_check(String(first.get("phenotype_hash", "")).is_empty(), "founder descriptor fabricates no phenotype hash")
	_check(Dictionary(first.get("realized_topology", {})).is_empty(), "founder descriptor fabricates no realized topology")
	_check(Dictionary(first.get("functional_morphology", {})).is_empty(), "founder descriptor fabricates no functional morphology")
	_check(Dictionary(first.get("competition_context", {})).is_empty(), "founder descriptor fabricates no competition context")
	_check(Dictionary(first.get("potential_morphology", {})).keys().size() == MorphologyEvidence.POTENTIAL_FIELDS.size(), "founder descriptor exposes genetic potential only")
	_check(String(wb.get_ecology_snapshot().get("state_hash", "")) == state_hash, "reading founder presentation data cannot change ecology")

func _generation_one_evidence(wb) -> void:
	var advanced: Dictionary = wb.advance_generations(1)
	_check(not advanced.is_empty(), "real ecology advances one generation")
	if advanced.is_empty():
		return

	var ecology: Dictionary = wb.get_ecology_snapshot()
	var state_hash := String(ecology.get("state_hash", ""))
	var evidence: Dictionary = wb.get_morphology_evidence()
	var current_records: Array = Array(ecology.get("records", []))
	_check(int(ecology.get("generation", -1)) == 1, "ecology source is generation one")
	_check(not current_records.is_empty(), "generation-one fixture has living plants")
	_check(not evidence.is_empty(), "LS3.4 publishes non-empty morphology sidecar after phenotype pass")
	if evidence.is_empty():
		return

	_check(MorphologyEvidence.validate_snapshot(evidence), "morphology evidence contract validates")
	_check(wb.validate_morphology_evidence(evidence), "Workbench validates current source binding")
	_check(bool(evidence.get("derived_representation", false)), "morphology evidence is explicitly derived")
	_check(bool(evidence.get("presentation_only", false)), "morphology evidence is explicitly presentation-only")
	_check(String(evidence.get("source_precompetition_population_hash", "")) == String(ecology.get("precompetition_population_hash", "")), "evidence binds precompetition population")
	_check(String(evidence.get("source_competition_hash", "")) == String(ecology.get("competition_hash", "")), "evidence binds exact competition field")
	_check(String(evidence.get("source_postcompetition_population_hash", "")) == String(ecology.get("postcompetition_population_hash", "")), "evidence binds exact survivor population")
	_check(int(evidence.get("record_count", -1)) == current_records.size(), "evidence contains exactly current living plants")
	_check(int(evidence.get("record_count", -1)) > 0, "morphology evidence is non-vacuous")
	_check(String(wb.get_ecology_snapshot().get("state_hash", "")) == state_hash, "publishing/reading morphology evidence leaves ecology state hash unchanged")

	var evidence_records: Array = Array(evidence.get("records", []))
	var evidence_by_id := _by_id(evidence_records, "record_id")
	var evaluations_by_id := _by_id(Array(Dictionary(ecology.get("competition_field", {})).get("evaluations", [])), "record_id")
	_check(evidence_records.size() == current_records.size(), "one sealed evidence record exists per living plant")
	_check(evidence_by_id.size() == current_records.size(), "evidence record ids are unique and complete")

	var saw_distinct_seed_domains := false
	for value in current_records:
		if not value is Dictionary:
			_check(false, "living record dictionary")
			continue
		var record: Dictionary = value
		var record_id := String(record.get("record_id", ""))
		_check(evidence_by_id.has(record_id), "evidence matches living record %s" % record_id)
		if not evidence_by_id.has(record_id):
			continue
		var item: Dictionary = evidence_by_id[record_id]
		var bundle_value = record.get("hereditary_bundle")
		_check(bundle_value is Dictionary, "living record exposes hereditary bundle %s" % record_id)
		if not bundle_value is Dictionary:
			continue
		var bundle: Dictionary = bundle_value
		_check(String(item.get("bundle_checksum", "")) == String(record.get("bundle_checksum", "")), "evidence bundle checksum exact for %s" % record_id)
		_check(int(item.get("cell_index", -1)) == int(record.get("cell_index", -2)), "evidence cell identity exact for %s" % record_id)
		_check(int(item.get("hereditary_individual_seed", -1)) == int(bundle.get("individual_seed", -2)), "evidence preserves hereditary seed for %s" % record_id)
		_check(int(item.get("development_individual_seed", -1)) >= 0, "evidence exposes development seed for %s" % record_id)
		if int(item.get("hereditary_individual_seed", -1)) != int(item.get("development_individual_seed", -1)):
			saw_distinct_seed_domains = true
		_check(evaluations_by_id.has(record_id) and bool(Dictionary(evaluations_by_id.get(record_id, {})).get("survives", false)), "evidence record corresponds to surviving LS3.4 evaluation")
		if evaluations_by_id.has(record_id):
			_check(String(item.get("source_phenotype_hash", "")) == String(Dictionary(evaluations_by_id[record_id]).get("phenotype_hash", "")), "evidence phenotype hash equals LS3.4 evaluation")
	_check(saw_distinct_seed_domains, "fixture proves hereditary seed and PH2 development seed are distinct identity domains")

	var adapter = AdapterV2.new()
	var result: Dictionary = adapter.build(ecology, evidence)
	_check(not result.is_empty(), "Descriptor V2 consumes exact ecology + morphology sidecar")
	if result.is_empty():
		_tamper_suite(adapter, wb, ecology, evidence)
		return

	_check(adapter.validate_result(result), "Descriptor V2 validates")
	_check(String(result.get("source_ecology_state_hash", "")) == state_hash, "Descriptor V2 binds exact ecology state")
	_check(String(result.get("source_competition_hash", "")) == String(ecology.get("competition_hash", "")), "Descriptor V2 binds exact competition")
	_check(String(result.get("source_morphology_evidence_hash", "")) == String(evidence.get("evidence_hash", "")), "Descriptor V2 binds exact morphology sidecar")
	_check(int(result.get("descriptor_count", -1)) == current_records.size(), "Descriptor V2 count equals living population")
	_check(int(result.get("morphology_evidence_count", -1)) == current_records.size(), "all live descriptors are morphology-evidence backed")
	_check(int(result.get("founder_marker_count", -1)) == 0, "generation one contains no founder fallback")

	var descriptors: Array = Array(result.get("descriptors", []))
	_check(not descriptors.is_empty(), "generation-one Descriptor V2 is non-vacuous")
	if not descriptors.is_empty() and descriptors[0] is Dictionary:
		var descriptor: Dictionary = descriptors[0]
		var record_id := String(descriptor.get("record_id", ""))
		var item: Dictionary = evidence_by_id.get(record_id, {})
		var evaluation: Dictionary = evaluations_by_id.get(record_id, {})
		_check(not item.is_empty() and not evaluation.is_empty(), "descriptor has exact evidence/evaluation sources")
		if not item.is_empty() and not evaluation.is_empty():
			_check(int(descriptor.get("hereditary_individual_seed", -1)) == int(item.get("hereditary_individual_seed", -2)), "Descriptor V2 preserves hereditary individual seed")
			_check(int(descriptor.get("development_individual_seed", -1)) == int(item.get("development_individual_seed", -2)), "Descriptor V2 preserves PH2 development seed")
			_check(String(descriptor.get("phenotype_hash", "")) == String(item.get("source_phenotype_hash", "")), "Descriptor V2 preserves phenotype hash")
			_check(String(descriptor.get("plasticity_phenotype_hash", "")) == String(item.get("source_plasticity_phenotype_hash", "")), "Descriptor V2 preserves PH2 phenotype seal")
			_check(String(descriptor.get("growth_graph_hash", "")) == String(item.get("source_growth_graph_hash", "")), "Descriptor V2 preserves exact GrowthGraph seal")
			_check(String(descriptor.get("source_evidence_record_hash", "")) == String(item.get("evidence_hash", "")), "Descriptor V2 preserves evidence-record seal")
			_check(String(descriptor.get("source_evaluation_hash", "")) == String(evaluation.get("evaluation_hash", "")), "Descriptor V2 preserves LS3.4 evaluation seal")
			_check(Dictionary(descriptor.get("potential_morphology", {})) == Dictionary(item.get("potential_morphology", {})), "genetic potential passes through byte-semantically")
			_check(Dictionary(descriptor.get("realized_topology", {})) == Dictionary(item.get("realized_topology", {})), "realized PH2 topology passes through without renderer recomputation")
			_check(Dictionary(descriptor.get("functional_morphology", {})) == Dictionary(item.get("functional_morphology", {})), "functional morphology passes through without renderer recomputation")
			var context: Dictionary = descriptor.get("competition_context", {})
			_check(is_equal_approx(float(context.get("water_satisfaction", NAN)), float(evaluation.get("water_satisfaction", NAN))), "competition water context exact")
			_check(is_equal_approx(float(context.get("effective_light", NAN)), float(evaluation.get("effective_light", NAN))), "competition light context exact")
			_check(is_equal_approx(float(context.get("realized_resource_balance", NAN)), float(evaluation.get("realized_resource_balance", NAN))), "competition resource context exact")
			_check(Dictionary(descriptor.get("functional_morphology", {})).has("realized_crown_radius_m"), "Descriptor V2 exposes realized crown radius")
			_check(Dictionary(descriptor.get("functional_morphology", {})).has("realized_crown_density"), "Descriptor V2 exposes realized crown density")
			_check(Dictionary(descriptor.get("functional_morphology", {})).has("structural_investment"), "Descriptor V2 exposes structural investment")
			_check(Dictionary(descriptor.get("realized_topology", {})).has("branch_angle_deg"), "Descriptor V2 exposes realized branch angle")
			_check(Dictionary(descriptor.get("realized_topology", {})).has("branch_probability"), "Descriptor V2 exposes realized branch probability")
			_check(Dictionary(descriptor.get("potential_morphology", {})).has("branch_angle_deg"), "Descriptor V2 keeps genetic potential separately")

	_tamper_suite(adapter, wb, ecology, evidence)

func _tamper_suite(adapter, wb, ecology: Dictionary, evidence: Dictionary) -> void:
	var records: Array = Array(evidence.get("records", []))
	_check(not records.is_empty(), "tamper suite has non-empty morphology evidence")
	if records.is_empty() or not records[0] is Dictionary:
		return

	var tampered_value: Dictionary = evidence.duplicate(true)
	var changed_value: Dictionary = Dictionary(Array(tampered_value.get("records", []))[0]).duplicate(true)
	changed_value["functional_morphology"] = Dictionary(changed_value.get("functional_morphology", {})).duplicate(true)
	changed_value["functional_morphology"]["realized_crown_radius_m"] = float(changed_value["functional_morphology"].get("realized_crown_radius_m", 0.0)) + 0.25
	tampered_value["records"][0] = changed_value
	_check(not MorphologyEvidence.validate_snapshot(tampered_value), "morphology value tamper fails sealed evidence validation")
	_check(adapter.build(ecology, tampered_value).is_empty(), "Descriptor V2 fails closed on stale hash after morphology tamper")

	var wrong_source: Dictionary = evidence.duplicate(true)
	wrong_source["source_postcompetition_population_hash"] = "f".repeat(64)
	wrong_source["evidence_hash"] = MorphologyEvidence.snapshot_hash(wrong_source)
	_check(MorphologyEvidence.validate_snapshot(wrong_source), "rehash can make standalone morphology envelope internally valid")
	_check(not wb.validate_morphology_evidence(wrong_source), "Workbench rejects internally valid evidence bound to wrong live population")
	_check(adapter.build(ecology, wrong_source).is_empty(), "Descriptor V2 rejects wrong population binding")

	var forged_competition: Dictionary = ecology.duplicate(true)
	forged_competition["competition_field"] = Dictionary(forged_competition.get("competition_field", {})).duplicate(true)
	forged_competition["competition_field"]["field_hash"] = "e".repeat(64)
	_check(adapter.build(forged_competition, evidence).is_empty(), "Descriptor V2 rejects competition field seal mismatch")

	var wrong_hereditary: Dictionary = evidence.duplicate(true)
	var wrong_records: Array = Array(wrong_hereditary.get("records", []))
	var changed_identity: Dictionary = Dictionary(wrong_records[0]).duplicate(true)
	changed_identity["hereditary_individual_seed"] = int(changed_identity.get("hereditary_individual_seed", 0)) + 1
	changed_identity["evidence_hash"] = MorphologyEvidence.record_hash(changed_identity)
	wrong_records[0] = changed_identity
	wrong_hereditary["records"] = wrong_records
	wrong_hereditary["evidence_hash"] = MorphologyEvidence.snapshot_hash(wrong_hereditary)
	_check(MorphologyEvidence.validate_snapshot(wrong_hereditary), "rehashed hereditary-seed tamper is internally self-consistent")
	_check(not wb.validate_morphology_evidence(wrong_hereditary), "Workbench rejects rehashed hereditary seed not matching live bundle")
	_check(adapter.build(ecology, wrong_hereditary).is_empty(), "Descriptor V2 rejects rehashed hereditary seed not matching live bundle")

func _deterministic_replay(world, reference_wb) -> void:
	var reference_ecology: Dictionary = reference_wb.get_ecology_snapshot()
	var reference_evidence: Dictionary = reference_wb.get_morphology_evidence()
	_check(not reference_evidence.is_empty(), "determinism reference morphology evidence is non-empty")
	_check(int(reference_evidence.get("record_count", 0)) > 0, "determinism reference morphology evidence is non-vacuous")
	var reference_adapter: Dictionary = AdapterV2.new().build(reference_ecology, reference_evidence)
	_check(not reference_adapter.is_empty(), "determinism reference Descriptor V2 is non-empty")

	var replay = Workbench.new()
	_check(replay.setup(world), "deterministic replay Workbench initializes")
	var replay_step: Dictionary = replay.advance_generations(1)
	_check(not replay_step.is_empty(), "deterministic replay advances")
	if replay_step.is_empty():
		return
	var replay_ecology: Dictionary = replay.get_ecology_snapshot()
	var replay_evidence: Dictionary = replay.get_morphology_evidence()
	var replay_adapter: Dictionary = AdapterV2.new().build(replay_ecology, replay_evidence)
	_check(not replay_evidence.is_empty(), "replay morphology evidence is non-empty")
	_check(int(replay_evidence.get("record_count", 0)) > 0, "replay morphology evidence is non-vacuous")
	_check(not replay_adapter.is_empty(), "replay Descriptor V2 is non-empty")
	_check(String(replay_ecology.get("state_hash", "")) == String(reference_ecology.get("state_hash", "")), "VIS4.1 does not perturb deterministic ecology replay")
	if not reference_evidence.is_empty() and not replay_evidence.is_empty():
		_check(String(replay_evidence.get("evidence_hash", "")) == String(reference_evidence.get("evidence_hash", "")), "non-vacuous morphology evidence hash deterministic")
	else:
		_check(false, "morphology evidence hash comparison requires two non-empty sidecars")
	if not reference_adapter.is_empty() and not replay_adapter.is_empty():
		_check(String(replay_adapter.get("adapter_hash", "")) == String(reference_adapter.get("adapter_hash", "")), "non-vacuous Descriptor V2 hash deterministic")
	else:
		_check(false, "Descriptor V2 hash comparison requires two non-empty adapters")

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
	_check(ls34.contains("int(post.get(\"record_count\", -1))"), "LS3.4 seals morphology evidence only when survivor record count is complete")
	_check(ls34.contains("get_morphology_evidence"), "LS3.4 exposes separate sidecar API")
	_check(evidence.contains("hereditary_individual_seed"), "evidence contract names hereditary seed explicitly")
	_check(evidence.contains("development_individual_seed"), "evidence contract names PH2 development seed explicitly")
	_check(not evidence.contains("hereditary_individual_seed != int(ph2.get"), "evidence contract never conflates hereditary and PH2 seed domains")
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
		print("ECO.EVO7 VIS4.1 Source-Bound Morphology Evidence R2: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error("ECO.EVO7 VIS4.1 R2 FAIL: %s" % failure)
	print("ECO.EVO7 VIS4.1 Source-Bound Morphology Evidence R2: FAIL (%d assertions, %d failures)" % [assertions, failures.size()])
	quit(1)
