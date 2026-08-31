extends SceneTree

const EarthWorld = preload("res://scripts/world/earth/procedural_earth_world.gd")
const Workbench = preload("res://scripts/ecology/shadow/eco_evo7_ls36_rule_workbench_v1.gd")
const DescriptorV2 = preload("res://scripts/labs/ecology/eco_evo7_vis4_morphology_render_adapter.gd")
const ReconstructionEvidence = preload("res://scripts/research/ecology/plant_growth_graph_reconstruction_evidence_v1.gd")
const Traits = preload("res://scripts/research/ecology/plant_development_traits_v1.gd")
const Representation = preload("res://scripts/research/ecology/plant_multiscale_representation_v1.gd")
const Bridge = preload("res://scripts/labs/ecology/eco_evo7_vis4_3_exact_ph5_bridge.gd")

var assertions := 0
var failures: Array[String] = []

func _init() -> void:
	var world = EarthWorld.new()
	root.add_child(world)
	_check(world.setup(null), "real Earth initializes")

	var wb = Workbench.new()
	_check(wb.setup(world), "Workbench initializes from accepted ecology chain")

	_generation_zero_gate(wb)
	_generation_one_exact_bridge(wb)
	_deterministic_replay(world, wb)
	_source_guard()

	world.queue_free()
	_finish()

func _generation_zero_gate(wb) -> void:
	var ecology: Dictionary = wb.get_ecology_snapshot()
	var state_hash := String(ecology.get("state_hash", ""))
	_check(int(ecology.get("generation", -1)) == 0, "VIS4.3 source starts at generation zero")
	_check(wb.get_graph_reconstruction_evidence().is_empty(), "generation zero has no fabricated reconstruction evidence")
	var descriptor: Dictionary = DescriptorV2.new().build(ecology, {})
	_check(not descriptor.is_empty(), "generation-zero Descriptor V2 founder source remains valid")
	_check(Bridge.new().build(descriptor, {}).is_empty(), "VIS4.3 refuses PH5 reconstruction without realized evidence")
	_check(String(wb.get_ecology_snapshot().get("state_hash", "")) == state_hash, "generation-zero bridge reads cannot mutate ecology")

func _generation_one_exact_bridge(wb) -> void:
	_check(not wb.advance_generations(1).is_empty(), "real ecology advances one generation")
	var ecology: Dictionary = wb.get_ecology_snapshot()
	var ecology_state_hash := String(ecology.get("state_hash", ""))
	var morphology: Dictionary = wb.get_morphology_evidence()
	var reconstruction: Dictionary = wb.get_graph_reconstruction_evidence()

	_check(int(ecology.get("generation", -1)) == 1, "VIS4.3 source is generation one")
	_check(int(ecology.get("record_count", 0)) == 61, "generation-one accepted fixture has 61 survivors")
	_check(not morphology.is_empty() and wb.validate_morphology_evidence(morphology), "VIS4.1 morphology evidence remains valid")
	_check(not reconstruction.is_empty(), "VIS4.3 reconstruction evidence exists")
	_check(ReconstructionEvidence.validate_snapshot(reconstruction), "reconstruction evidence contract validates")
	_check(wb.validate_graph_reconstruction_evidence(reconstruction), "Workbench validates reconstruction evidence against live population")
	_check(bool(reconstruction.get("derived_representation", false)), "reconstruction sidecar is explicitly derived")
	_check(bool(reconstruction.get("presentation_only", false)), "reconstruction sidecar is explicitly presentation-only")
	_check(int(reconstruction.get("record_count", -1)) == 61, "reconstruction evidence is complete for all 61 survivors")
	_check(String(reconstruction.get("source_precompetition_population_hash", "")) == String(ecology.get("precompetition_population_hash", "")), "reconstruction evidence binds precompetition population")
	_check(String(reconstruction.get("source_competition_hash", "")) == String(ecology.get("competition_hash", "")), "reconstruction evidence binds competition field")
	_check(String(reconstruction.get("source_postcompetition_population_hash", "")) == String(ecology.get("postcompetition_population_hash", "")), "reconstruction evidence binds survivor population")

	var descriptor: Dictionary = DescriptorV2.new().build(ecology, morphology)
	_check(not descriptor.is_empty(), "Descriptor V2 source builds for VIS4.3")
	_check(int(descriptor.get("descriptor_count", -1)) == 61, "Descriptor V2 has 61 live records")

	var bridge := Bridge.new()
	var result: Dictionary = bridge.build(descriptor, reconstruction, Representation.TIER_1_REDUCED)
	_check(not result.is_empty(), "VIS4.3 exact PH5 bridge builds")
	_check(bridge.validate_result(result), "VIS4.3 bridge result validates")
	_check(int(result.get("descriptor_count", -1)) == 61, "VIS4.3 bridges all 61 living plants")
	_check(String(result.get("source_descriptor_adapter_hash", "")) == String(descriptor.get("adapter_hash", "")), "bridge binds exact Descriptor V2 adapter hash")
	_check(String(result.get("source_ecology_state_hash", "")) == ecology_state_hash, "bridge binds exact ecology state hash")
	_check(String(result.get("source_morphology_evidence_hash", "")) == String(morphology.get("evidence_hash", "")), "bridge binds exact morphology evidence hash")
	_check(String(result.get("source_reconstruction_evidence_hash", "")) == String(reconstruction.get("evidence_hash", "")), "bridge binds exact reconstruction evidence hash")
	_check(String(result.get("bridge_hash", "")).length() == 64, "bridge hash valid")

	var source_by_id := _by_id(Array(descriptor.get("descriptors", [])), "record_id")
	var reconstruction_by_id := _by_id(Array(reconstruction.get("records", [])), "record_id")
	var bridge_by_id := _by_id(Array(result.get("descriptors", [])), "record_id")
	_check(source_by_id.size() == 61 and reconstruction_by_id.size() == 61 and bridge_by_id.size() == 61, "source/reconstruction/bridge record sets all complete")

	for record_id_value in bridge_by_id.keys():
		var record_id := String(record_id_value)
		var source: Dictionary = source_by_id.get(record_id, {})
		var evidence: Dictionary = reconstruction_by_id.get(record_id, {})
		var bridged: Dictionary = bridge_by_id.get(record_id, {})
		_check(not source.is_empty() and not evidence.is_empty(), "bridge record has exact source/evidence %s" % record_id)
		if source.is_empty() or evidence.is_empty():
			continue
		var realized: Dictionary = evidence.get("realized_development_traits", {})
		_check(bool(Traits.validate(realized).get("success", false)), "realized development traits validate %s" % record_id)
		_check(not String(realized.get("traits_id", "")).is_empty(), "exact realized traits_id preserved %s" % record_id)
		_check(String(realized.get("checksum", "")) == String(evidence.get("source_realized_traits_hash", "")), "realized traits checksum exact %s" % record_id)
		_check(int(evidence.get("development_individual_seed", -1)) == int(source.get("development_individual_seed", -2)), "development seed exact %s" % record_id)
		_check(String(evidence.get("source_growth_graph_hash", "")) == String(source.get("growth_graph_hash", "")), "reconstruction sidecar graph seal equals Descriptor V2 %s" % record_id)
		_check(String(bridged.get("source_growth_graph_hash", "")) == String(source.get("growth_graph_hash", "")), "bridge source graph seal exact %s" % record_id)
		_check(String(bridged.get("reconstructed_graph_hash", "")) == String(source.get("growth_graph_hash", "")), "reconstructed GrowthGraph hash exactly equals PH2 source %s" % record_id)
		_check(String(bridged.get("render_description_hash", "")).length() == 64, "accepted PH5 RenderDescription hash exists %s" % record_id)
		_check(String(bridged.get("representation_hash", "")).length() == 64, "accepted PH5 representation hash exists %s" % record_id)
		_check(int(bridged.get("branch_primitive_count", -1)) >= 0 and int(bridged.get("foliage_instance_count", -1)) >= 0, "PH5 primitive counts valid %s" % record_id)

	var first_source: Dictionary = Array(descriptor.get("descriptors", []))[0]
	var first_reconstruction: Dictionary = reconstruction_by_id.get(String(first_source.get("record_id", "")), {})
	_check(not first_reconstruction.is_empty(), "materialization probe has reconstruction record")
	for tier in Representation.TIER_ORDER:
		var materialized: Dictionary = bridge.materialize_record(first_source, first_reconstruction, tier)
		_check(not materialized.is_empty() and bool(materialized.get("success", false)), "accepted PH5 materializes tier %s" % tier)
		if materialized.is_empty():
			continue
		_check(String(materialized.get("ecological_truth_hash", "")) == String(first_source.get("growth_graph_hash", "")), "materialized tier %s preserves exact GrowthGraph truth" % tier)
		_check(String(materialized.get("materialization_hash", "")).length() == 64, "materialized tier %s has deterministic PH5 hash" % tier)

	_tamper_suite(bridge, descriptor, reconstruction)
	_check(String(wb.get_ecology_snapshot().get("state_hash", "")) == ecology_state_hash, "reconstruction/PH5 bridge cannot mutate ecology state")

func _tamper_suite(bridge, descriptor: Dictionary, reconstruction: Dictionary) -> void:
	var records: Array = Array(reconstruction.get("records", []))
	_check(not records.is_empty(), "VIS4.3 tamper suite has non-empty reconstruction records")
	if records.is_empty() or not records[0] is Dictionary:
		return

	var stale_traits: Dictionary = reconstruction.duplicate(true)
	var stale_records: Array = Array(stale_traits.get("records", []))
	var stale_record: Dictionary = Dictionary(stale_records[0]).duplicate(true)
	var stale_realized: Dictionary = Dictionary(stale_record.get("realized_development_traits", {})).duplicate(true)
	stale_realized["branch_angle_deg"] = minf(float(stale_realized.get("branch_angle_deg", 0.0)) + 1.0, 89.0)
	stale_record["realized_development_traits"] = stale_realized
	stale_records[0] = stale_record
	stale_traits["records"] = stale_records
	_check(not ReconstructionEvidence.validate_snapshot(stale_traits), "stale realized-traits tamper fails evidence seal")
	_check(bridge.build(descriptor, stale_traits).is_empty(), "bridge rejects stale realized-traits tamper")

	var rehashed_traits_id: Dictionary = reconstruction.duplicate(true)
	var id_records: Array = Array(rehashed_traits_id.get("records", []))
	var id_record: Dictionary = Dictionary(id_records[0]).duplicate(true)
	var id_realized: Dictionary = Dictionary(id_record.get("realized_development_traits", {})).duplicate(true)
	id_realized["traits_id"] = String(id_realized.get("traits_id", "")) + "/forged"
	id_realized["checksum"] = Traits.compute_checksum(id_realized)
	id_record["realized_development_traits"] = id_realized
	id_record["source_realized_traits_hash"] = String(id_realized["checksum"])
	id_record["reconstruction_evidence_hash"] = ReconstructionEvidence.record_hash(id_record)
	id_records[0] = id_record
	rehashed_traits_id["records"] = id_records
	rehashed_traits_id["evidence_hash"] = ReconstructionEvidence.snapshot_hash(rehashed_traits_id)
	_check(ReconstructionEvidence.validate_snapshot(rehashed_traits_id), "rehashed traits_id tamper is internally valid reconstruction evidence")
	_check(bridge.build(descriptor, rehashed_traits_id).is_empty(), "exact bridge rejects rehashed traits_id because reconstructed GrowthGraph hash diverges")

	var competition_tamper: Dictionary = reconstruction.duplicate(true)
	competition_tamper["source_competition_hash"] = "e".repeat(64)
	competition_tamper["evidence_hash"] = ReconstructionEvidence.snapshot_hash(competition_tamper)
	_check(ReconstructionEvidence.validate_snapshot(competition_tamper), "rehashed competition-seal tamper is internally valid reconstruction evidence")
	_check(bridge.build(descriptor, competition_tamper).is_empty(), "bridge rejects reconstruction evidence from wrong competition field")

	var seed_tamper: Dictionary = reconstruction.duplicate(true)
	var seed_records: Array = Array(seed_tamper.get("records", []))
	var seed_record: Dictionary = Dictionary(seed_records[0]).duplicate(true)
	seed_record["development_individual_seed"] = int(seed_record.get("development_individual_seed", 0)) + 1
	seed_record["reconstruction_evidence_hash"] = ReconstructionEvidence.record_hash(seed_record)
	seed_records[0] = seed_record
	seed_tamper["records"] = seed_records
	seed_tamper["evidence_hash"] = ReconstructionEvidence.snapshot_hash(seed_tamper)
	_check(ReconstructionEvidence.validate_snapshot(seed_tamper), "rehashed development-seed tamper is internally valid evidence")
	_check(bridge.build(descriptor, seed_tamper).is_empty(), "bridge rejects rehashed development seed against Descriptor V2/source graph")

func _deterministic_replay(world, reference_wb) -> void:
	var reference_ecology: Dictionary = reference_wb.get_ecology_snapshot()
	var reference_morphology: Dictionary = reference_wb.get_morphology_evidence()
	var reference_reconstruction: Dictionary = reference_wb.get_graph_reconstruction_evidence()
	var reference_descriptor := DescriptorV2.new().build(reference_ecology, reference_morphology)
	var reference_bridge := Bridge.new().build(reference_descriptor, reference_reconstruction, Representation.TIER_1_REDUCED)
	_check(not reference_bridge.is_empty() and int(reference_bridge.get("descriptor_count", 0)) > 0, "reference PH5 bridge is non-vacuous")

	var replay = Workbench.new()
	_check(replay.setup(world), "VIS4.3 deterministic replay Workbench initializes")
	_check(not replay.advance_generations(1).is_empty(), "VIS4.3 deterministic replay advances")
	var replay_ecology: Dictionary = replay.get_ecology_snapshot()
	var replay_morphology: Dictionary = replay.get_morphology_evidence()
	var replay_reconstruction: Dictionary = replay.get_graph_reconstruction_evidence()
	var replay_descriptor := DescriptorV2.new().build(replay_ecology, replay_morphology)
	var replay_bridge := Bridge.new().build(replay_descriptor, replay_reconstruction, Representation.TIER_1_REDUCED)
	_check(not replay_bridge.is_empty() and int(replay_bridge.get("descriptor_count", 0)) > 0, "replay PH5 bridge is non-vacuous")
	_check(String(replay_ecology.get("state_hash", "")) == String(reference_ecology.get("state_hash", "")), "VIS4.3 preserves deterministic ecology replay")
	_check(String(replay_reconstruction.get("evidence_hash", "")) == String(reference_reconstruction.get("evidence_hash", "")), "reconstruction evidence hash deterministic")
	_check(String(replay_descriptor.get("adapter_hash", "")) == String(reference_descriptor.get("adapter_hash", "")), "Descriptor V2 hash deterministic through VIS4.3")
	_check(String(replay_bridge.get("bridge_hash", "")) == String(reference_bridge.get("bridge_hash", "")), "exact PH5 bridge hash deterministic")

func _source_guard() -> void:
	var ls34 := FileAccess.get_file_as_string("res://scripts/ecology/shadow/eco_evo7_ls34_local_competition_v1.gd")
	var evidence := FileAccess.get_file_as_string("res://scripts/research/ecology/plant_growth_graph_reconstruction_evidence_v1.gd").to_lower()
	var bridge := FileAccess.get_file_as_string("res://scripts/labs/ecology/eco_evo7_vis4_3_exact_ph5_bridge.gd").to_lower()

	_check(_count(ls34, "CoupledDevelopment.realize(") == 1, "VIS4.3 keeps one LS3.4 PH2 realization call site")
	_check(_count(ls34, "FunctionalPhenotype.compile(") == 1, "VIS4.3 keeps one LS3.4 FunctionalPhenotype compile call site")
	_check(_count(ls34, "GraphReconstructionEvidence.build_record(") == 1, "LS3.4 packages one reconstruction record from same PH2 object")
	var reconstruction_at := ls34.find("var graph_reconstruction_evidence := GraphReconstructionEvidence.build_record(")
	var provisional_at := ls34.find("provisional.append({", reconstruction_at)
	var packaging_block := ls34.substr(reconstruction_at, provisional_at - reconstruction_at) if reconstruction_at >= 0 and provisional_at > reconstruction_at else ""
	_check(not packaging_block.contains("return {}"), "reconstruction evidence packaging cannot abort ecology generation")
	_check(not evidence.contains("plant_environment_coupled_development") and not evidence.contains("plant_functional_phenotype") and not evidence.contains("plant_growth_graph_skeleton"), "reconstruction evidence packages source PH2 data without biology/graph recomputation")
	_check(bridge.contains("plant_growth_graph_skeleton_v1.gd"), "VIS4.3 bridge reuses accepted GrowthGraph skeleton")
	_check(bridge.contains("plant_render_description_v1.gd"), "VIS4.3 bridge reuses accepted RenderDescription")
	_check(bridge.contains("plant_multiscale_representation_v1.gd") and bridge.contains("plant_multiscale_materializer_v1.gd"), "VIS4.3 bridge reuses accepted PH5 LOD/materializer stack")
	_check(_count(bridge, "growthgraph.build(") == 1, "VIS4.3 has one exact GrowthGraph reconstruction call site")
	_check(not bridge.contains("plant_environment_coupled_development") and not bridge.contains("plant_functional_phenotype") and not bridge.contains("plant_resource_model"), "VIS4.3 bridge contains no biology recomputation")
	_check(not bridge.contains("branch/%d") and not bridge.contains("azimuth/%d") and not bridge.contains("angle/%d") and not bridge.contains("length/%d/%d"), "VIS4.3 does not copy GrowthGraph stochastic algorithm")
	for source in [evidence, bridge]:
		_check(not source.contains("reproduce_bundle(") and not source.contains("mutation_seed(") and not source.contains("dispersal_seed("), "VIS4.3 owns no mutation/reproduction/dispersal authority")
		_check(not source.contains("fileaccess.open") and not source.contains("diraccess") and not source.contains("multiplayer"), "VIS4.3 owns no persistence/network authority")

	var state_hash_at := ls34.find("func _state_hash(")
	var authority_hash_at := ls34.find("func _authority_hash(", state_hash_at)
	var state_hash_block := ls34.substr(state_hash_at, authority_hash_at - state_hash_at) if state_hash_at >= 0 and authority_hash_at > state_hash_at else ""
	_check(not state_hash_block.to_lower().contains("reconstruction"), "VIS4.3 reconstruction sidecar stays outside ecology state hash")

func _by_id(values: Array, key: String) -> Dictionary:
	var out := {}
	for value in values:
		if value is Dictionary:
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
		print("ECO.EVO7 VIS4.3 Exact Live Phenotype -> PH5 Bridge: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error("ECO.EVO7 VIS4.3 FAIL: %s" % failure)
	print("ECO.EVO7 VIS4.3 Exact Live Phenotype -> PH5 Bridge: FAIL (%d assertions, %d failures)" % [assertions, failures.size()])
	quit(1)
