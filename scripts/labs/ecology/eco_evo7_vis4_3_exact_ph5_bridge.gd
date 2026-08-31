extends RefCounted

## ECO.EVO7 VIS4.3 — exact Live Phenotype -> accepted PH5 bridge.
##
## Consumes sealed VIS4.1 Descriptor V2 plus VIS4.3 reconstruction evidence.
## Reconstructs GrowthGraph only through the accepted PH5 skeleton, requires exact
## source graph-hash equality, then builds accepted PH5 RenderDescription and LOD
## representation. No environment/phenotype/competition biology is recomputed.

const DescriptorV2 = preload("res://scripts/labs/ecology/eco_evo7_vis4_morphology_render_adapter.gd")
const ReconstructionEvidence = preload("res://scripts/research/ecology/plant_growth_graph_reconstruction_evidence_v1.gd")
const Traits = preload("res://scripts/research/ecology/plant_development_traits_v1.gd")
const GrowthGraph = preload("res://scripts/research/ecology/plant_growth_graph_skeleton_v1.gd")
const RenderDescription = preload("res://scripts/research/ecology/plant_render_description_v1.gd")
const Representation = preload("res://scripts/research/ecology/plant_multiscale_representation_v1.gd")
const Materializer = preload("res://scripts/research/ecology/plant_multiscale_materializer_v1.gd")

const SCHEMA := "distributed_world_simulator.ecology.evo7_vis4_3_ph5_bridge.v1"
const VERSION := "1.0.0"
const REVISION := "ECO.EVO7-VIS4.3.R1"

var _perf_chain_build_count := 0
var _perf_growth_graph_usec := 0
var _perf_render_description_usec := 0
var _perf_representation_usec := 0
var _perf_materializer_usec := 0


func get_performance_counters() -> Dictionary:
	return {
		"chain_build_count": _perf_chain_build_count,
		"growth_graph_ms": float(_perf_growth_graph_usec) / 1000.0,
		"render_description_ms": float(_perf_render_description_usec) / 1000.0,
		"representation_ms": float(_perf_representation_usec) / 1000.0,
		"materializer_ms": float(_perf_materializer_usec) / 1000.0,
		"timings_diagnostic_only": true,
	}


const RESULT_FIELDS: Array[String] = [
	"schema", "version", "revision", "generation", "tier",
	"source_descriptor_adapter_hash", "source_ecology_state_hash",
	"source_morphology_evidence_hash", "source_reconstruction_evidence_hash",
	"descriptor_count", "descriptors", "bridge_hash",
]

const DESCRIPTOR_FIELDS: Array[String] = [
	"record_id", "cell_index", "bundle_checksum", "lineage_id",
	"source_descriptor_hash", "source_reconstruction_record_hash",
	"source_realized_traits_hash", "source_growth_graph_hash",
	"development_individual_seed", "tier",
	"reconstructed_graph_hash", "render_description_hash", "representation_hash",
	"branch_primitive_count", "foliage_instance_count", "canopy_primitive_count",
	"impostor_count", "cost_units", "bridge_descriptor_hash",
]

func build(
	descriptor_snapshot: Dictionary,
	reconstruction_snapshot: Dictionary,
	tier: String = Representation.TIER_1_REDUCED
) -> Dictionary:
	if not DescriptorV2.new().validate_result(descriptor_snapshot):
		return {}
	if not ReconstructionEvidence.validate_snapshot(reconstruction_snapshot):
		return {}
	if not tier in Representation.TIER_ORDER:
		return {}
	var generation := int(descriptor_snapshot.get("generation", -1))
	if generation < 1 or generation != int(reconstruction_snapshot.get("generation", -2)):
		return {}
	if int(descriptor_snapshot.get("founder_marker_count", -1)) != 0:
		return {}
	if int(descriptor_snapshot.get("descriptor_count", -1)) != int(reconstruction_snapshot.get("record_count", -2)):
		return {}
	if String(descriptor_snapshot.get("source_competition_hash", "")) != String(reconstruction_snapshot.get("source_competition_hash", "")):
		return {}

	var reconstruction_by_id := {}
	for value in Array(reconstruction_snapshot.get("records", [])):
		if not value is Dictionary:
			return {}
		var item: Dictionary = value
		var record_id := String(item.get("record_id", ""))
		if record_id.is_empty() or reconstruction_by_id.has(record_id):
			return {}
		reconstruction_by_id[record_id] = item

	var descriptors: Array[Dictionary] = []
	for value in Array(descriptor_snapshot.get("descriptors", [])):
		if not value is Dictionary:
			return {}
		var source: Dictionary = value
		var record_id := String(source.get("record_id", ""))
		if not reconstruction_by_id.has(record_id):
			return {}
		var built := _bridge_record(source, Dictionary(reconstruction_by_id[record_id]), tier)
		if built.is_empty():
			return {}
		descriptors.append(built)
	descriptors.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a["record_id"]) < String(b["record_id"])
	)

	var result := {
		"schema": SCHEMA,
		"version": VERSION,
		"revision": REVISION,
		"generation": generation,
		"tier": tier,
		"source_descriptor_adapter_hash": String(descriptor_snapshot.get("adapter_hash", "")),
		"source_ecology_state_hash": String(descriptor_snapshot.get("source_ecology_state_hash", "")),
		"source_morphology_evidence_hash": String(descriptor_snapshot.get("source_morphology_evidence_hash", "")),
		"source_reconstruction_evidence_hash": String(reconstruction_snapshot.get("evidence_hash", "")),
		"descriptor_count": descriptors.size(),
		"descriptors": descriptors,
	}
	result["bridge_hash"] = _bridge_hash(result)
	return result if validate_result(result) else {}

func validate_result(result: Dictionary) -> bool:
	if not _exact_keys(result, RESULT_FIELDS):
		return false
	if String(result.get("schema", "")) != SCHEMA or String(result.get("version", "")) != VERSION or String(result.get("revision", "")) != REVISION:
		return false
	if int(result.get("generation", -1)) < 1 or not String(result.get("tier", "")) in Representation.TIER_ORDER:
		return false
	for key in [
		"source_descriptor_adapter_hash", "source_ecology_state_hash",
		"source_morphology_evidence_hash", "source_reconstruction_evidence_hash",
	]:
		if String(result.get(key, "")).length() != 64:
			return false
	var descriptors_value = result.get("descriptors")
	if not descriptors_value is Array:
		return false
	var descriptors: Array = descriptors_value
	if int(result.get("descriptor_count", -1)) != descriptors.size():
		return false
	var previous_id := ""
	for value in descriptors:
		if not value is Dictionary or not _validate_bridge_descriptor(value):
			return false
		var item: Dictionary = value
		if String(item.get("tier", "")) != String(result.get("tier", "")):
			return false
		var record_id := String(item.get("record_id", ""))
		if not previous_id.is_empty() and record_id <= previous_id:
			return false
		previous_id = record_id
	return String(result.get("bridge_hash", "")) == _bridge_hash(result)

func materialize_record(
	source_descriptor: Dictionary,
	reconstruction_record: Dictionary,
	tier: String = Representation.TIER_1_REDUCED
) -> Dictionary:
	var chain := _build_exact_chain(source_descriptor, reconstruction_record, tier)
	if chain.is_empty():
		return {}
	var description: Dictionary = chain["render_description"]
	var representation: Dictionary = chain["representation"]
	var materializer_started := Time.get_ticks_usec()
	var materialization := Materializer.build(description, representation)
	_perf_materializer_usec += Time.get_ticks_usec() - materializer_started
	if not bool(materialization.get("success", false)):
		return {}
	if String(materialization.get("ecological_truth_hash", "")) != String(source_descriptor.get("growth_graph_hash", "")):
		return {}
	if String(materialization.get("render_description_hash", "")) != String(description.get("render_description_hash", "")):
		return {}
	return materialization

func _bridge_record(source: Dictionary, reconstruction: Dictionary, tier: String) -> Dictionary:
	var chain := _build_exact_chain(source, reconstruction, tier)
	if chain.is_empty():
		return {}
	var graph: Dictionary = chain["growth_graph"]
	var description: Dictionary = chain["render_description"]
	var representation: Dictionary = chain["representation"]
	var descriptor := {
		"record_id": String(source.get("record_id", "")),
		"cell_index": int(source.get("cell_index", -1)),
		"bundle_checksum": String(source.get("bundle_checksum", "")),
		"lineage_id": String(source.get("lineage_id", "")),
		"source_descriptor_hash": String(source.get("descriptor_hash", "")),
		"source_reconstruction_record_hash": String(reconstruction.get("reconstruction_evidence_hash", "")),
		"source_realized_traits_hash": String(reconstruction.get("source_realized_traits_hash", "")),
		"source_growth_graph_hash": String(source.get("growth_graph_hash", "")),
		"development_individual_seed": int(source.get("development_individual_seed", -1)),
		"tier": tier,
		"reconstructed_graph_hash": String(graph.get("graph_hash", "")),
		"render_description_hash": String(description.get("render_description_hash", "")),
		"representation_hash": String(representation.get("representation_hash", "")),
		"branch_primitive_count": int(representation.get("branch_primitive_count", -1)),
		"foliage_instance_count": int(representation.get("foliage_instance_count", -1)),
		"canopy_primitive_count": int(representation.get("canopy_primitive_count", -1)),
		"impostor_count": int(representation.get("impostor_count", -1)),
		"cost_units": int(representation.get("cost_units", -1)),
	}
	descriptor["bridge_descriptor_hash"] = _descriptor_hash(descriptor)
	return descriptor if _validate_bridge_descriptor(descriptor) else {}

func _build_exact_chain(source: Dictionary, reconstruction: Dictionary, tier: String) -> Dictionary:
	if not tier in Representation.TIER_ORDER:
		return {}
	if String(source.get("evidence_level", "")) != DescriptorV2.MORPHOLOGY_EVIDENCE:
		return {}
	for key in ["descriptor_hash", "growth_graph_hash", "source_evidence_record_hash"]:
		if String(source.get(key, "")).length() != 64:
			return {}
	if not ReconstructionEvidence.validate_record(reconstruction):
		return {}
	if String(source.get("record_id", "")) != String(reconstruction.get("record_id", "")):
		return {}
	if int(source.get("cell_index", -1)) != int(reconstruction.get("cell_index", -2)):
		return {}
	if String(source.get("bundle_checksum", "")) != String(reconstruction.get("bundle_checksum", "")):
		return {}
	if String(source.get("lineage_id", "")) != String(reconstruction.get("lineage_id", "")):
		return {}
	if int(source.get("hereditary_individual_seed", -1)) != int(reconstruction.get("hereditary_individual_seed", -2)):
		return {}
	if int(source.get("development_individual_seed", -1)) != int(reconstruction.get("development_individual_seed", -2)):
		return {}
	if String(source.get("growth_graph_hash", "")) != String(reconstruction.get("source_growth_graph_hash", "")):
		return {}

	var realized_value = reconstruction.get("realized_development_traits")
	if not realized_value is Dictionary:
		return {}
	var realized: Dictionary = Dictionary(realized_value).duplicate(true)
	if not bool(Traits.validate(realized).get("success", false)):
		return {}
	if String(realized.get("checksum", "")) != String(reconstruction.get("source_realized_traits_hash", "")):
		return {}

	# Exact reconstruction through the accepted PH5 GrowthGraph implementation.
	var graph_started := Time.get_ticks_usec()
	var graph := GrowthGraph.build(realized, int(reconstruction.get("development_individual_seed", -1)))
	_perf_growth_graph_usec += Time.get_ticks_usec() - graph_started
	_perf_chain_build_count += 1
	if graph.is_empty():
		return {}
	if String(graph.get("graph_hash", "")) != String(source.get("growth_graph_hash", "")):
		return {}
	if String(graph.get("development_traits_checksum", "")) != String(realized.get("checksum", "")):
		return {}
	if String(graph.get("traits_id", "")) != String(realized.get("traits_id", "")):
		return {}

	var description_started := Time.get_ticks_usec()
	var description := RenderDescription.build(graph)
	_perf_render_description_usec += Time.get_ticks_usec() - description_started
	if description.is_empty() or not bool(RenderDescription.validate(description).get("success", false)):
		return {}
	if String(description.get("source_graph_hash", "")) != String(source.get("growth_graph_hash", "")):
		return {}

	var representation_started := Time.get_ticks_usec()
	var representation := Representation.build(description, tier)
	_perf_representation_usec += Time.get_ticks_usec() - representation_started
	if not bool(representation.get("success", false)):
		return {}
	if String(representation.get("ecological_truth_hash", "")) != String(source.get("growth_graph_hash", "")):
		return {}
	return {
		"growth_graph": graph,
		"render_description": description,
		"representation": representation,
	}

func _validate_bridge_descriptor(value: Dictionary) -> bool:
	if not _exact_keys(value, DESCRIPTOR_FIELDS):
		return false
	if String(value.get("record_id", "")).is_empty() or int(value.get("cell_index", -1)) < 0 or int(value.get("cell_index", -1)) >= 1024:
		return false
	if String(value.get("bundle_checksum", "")).length() != 64 or String(value.get("lineage_id", "")).is_empty():
		return false
	if int(value.get("development_individual_seed", -1)) < 0 or not String(value.get("tier", "")) in Representation.TIER_ORDER:
		return false
	for key in [
		"source_descriptor_hash", "source_reconstruction_record_hash", "source_realized_traits_hash",
		"source_growth_graph_hash", "reconstructed_graph_hash", "render_description_hash",
		"representation_hash", "bridge_descriptor_hash",
	]:
		if String(value.get(key, "")).length() != 64:
			return false
	if String(value.get("reconstructed_graph_hash", "")) != String(value.get("source_growth_graph_hash", "")):
		return false
	for key in ["branch_primitive_count", "foliage_instance_count", "canopy_primitive_count", "impostor_count", "cost_units"]:
		if int(value.get(key, -1)) < 0:
			return false
	return String(value.get("bridge_descriptor_hash", "")) == _descriptor_hash(value)

func _descriptor_hash(value: Dictionary) -> String:
	return "|".join(PackedStringArray([
		SCHEMA, VERSION, REVISION, "descriptor",
		String(value.get("record_id", "")),
		str(int(value.get("cell_index", -1))),
		String(value.get("bundle_checksum", "")),
		String(value.get("lineage_id", "")),
		String(value.get("source_descriptor_hash", "")),
		String(value.get("source_reconstruction_record_hash", "")),
		String(value.get("source_realized_traits_hash", "")),
		String(value.get("source_growth_graph_hash", "")),
		str(int(value.get("development_individual_seed", -1))),
		String(value.get("tier", "")),
		String(value.get("reconstructed_graph_hash", "")),
		String(value.get("render_description_hash", "")),
		String(value.get("representation_hash", "")),
		str(int(value.get("branch_primitive_count", -1))),
		str(int(value.get("foliage_instance_count", -1))),
		str(int(value.get("canopy_primitive_count", -1))),
		str(int(value.get("impostor_count", -1))),
		str(int(value.get("cost_units", -1))),
	])).sha256_text()

func _bridge_hash(result: Dictionary) -> String:
	var tokens := PackedStringArray([
		SCHEMA, VERSION, REVISION,
		str(int(result.get("generation", -1))),
		String(result.get("tier", "")),
		String(result.get("source_descriptor_adapter_hash", "")),
		String(result.get("source_ecology_state_hash", "")),
		String(result.get("source_morphology_evidence_hash", "")),
		String(result.get("source_reconstruction_evidence_hash", "")),
		str(int(result.get("descriptor_count", -1))),
	])
	for value in Array(result.get("descriptors", [])):
		if value is Dictionary:
			tokens.append(String(Dictionary(value).get("bridge_descriptor_hash", "")))
	return "|".join(tokens).sha256_text()

func _exact_keys(value: Dictionary, expected: Array[String]) -> bool:
	if value.keys().size() != expected.size():
		return false
	for key in expected:
		if not value.has(key):
			return false
	return true
